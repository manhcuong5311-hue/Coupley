// Rules tests for memories and capsules (firestore.rules, "Time Tree memories" block).
//
//   firebase emulators:exec --only firestore --project demo-coupley-rules \
//     "node --test firestore-tests/"
//
// Writes mirror what the shipped clients send. TimeTreeMemoryService is the
// same in 1.1 and 1.2: a create is setData(payload), a plain set with the
// unset optional fields left out; an edit is setData(payload, merge: true),
// which re-sends every field (unlockDate included) and deletes the unset
// optional ones with FieldValue.delete(); a delete is delete().

import { test, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { forDatabase, value } from './emulator.mjs'

// node --test runs the test files in parallel and each one resets its database
// before every test, so this file keeps to a database of its own.
const { reset, commit, setDoc, getDoc, listDocs, deleteDoc, W } = forDatabase('memories-rules')

const A = 'alice' // the author in most tests
const B = 'bob' // her partner
const M = 'mallory' // not in the couple
const COUPLE = 'couples/c1'
const MEMORIES = `${COUPLE}/memories`
const MEM = (id) => `${MEMORIES}/${id}`

const SECOND = 1e3
const HOUR = 3600 * SECOND
const DAY = 24 * HOUR
const at = (ms) => new Date(Date.now() + ms)
const shift = (date, ms) => new Date(date.getTime() + ms)

const ok = (r, why = '') =>
  assert.ok(r.ok, `expected ALLOW ${why}: ${r.status} ${JSON.stringify(r.body)}`)
// A denial must be the rules saying no (403), not a malformed request (400)
// or a missing document (404) that would make the test pass for nothing.
const no = (r, why = '') =>
  assert.equal(r.status, 403, `expected DENY (403) ${why}, got ${r.status} ${JSON.stringify(r.body)}`)

const PAST_DAY = at(-30 * DAY) // the day a plain memory is about
const CREATED = at(-7 * DAY) // when the memories were first saved

/**
 * A memory as TimeTreeMemoryService.payload(from:forCreate:) writes it in 1.1
 * and 1.2: every required field always; photoURL, unlockDate and
 * anniversaryId only when set. `unset` names the optional fields left out,
 * which an edit deletes. A capsule's date is its unlock day, as the editor
 * saves it.
 */
function payload(id, o = {}) {
  const {
    by = A,
    kind = 'firstTrip',
    title = 'First Trip',
    note = 'Lisbon in the rain',
    emotions = ['adventurous', 'joyful', 'loved'],
    attribution = '',
    photoURL,
    unlockDate,
    anniversaryId,
    date = unlockDate ?? PAST_DAY,
    createdAt = CREATED,
    updatedAt = createdAt,
  } = o
  const data = { id, kind, title, date, note, emotions, attribution, createdBy: by, createdAt, updatedAt }
  const unset = []
  for (const [key, v] of Object.entries({ photoURL, unlockDate, anniversaryId })) {
    if (v === undefined) unset.push(key)
    else data[key] = v
  }
  return { data, unset }
}

/** Create: setData(payload). */
const create = (id, o, auth) => commit([W.set(MEM(id), payload(id, o).data)], auth)

/** Edit: setData(payload, merge: true), stamped with a fresh updatedAt. */
function edit(id, o, auth) {
  const { data, unset } = payload(id, { ...o, updatedAt: new Date() })
  return commit([W.merge(MEM(id), data, unset)], auth)
}

/** The memory as stored, read by a member. */
async function stored(id) {
  const r = await getDoc(MEM(id), A)
  ok(r, `read ${id}`)
  return r.body
}

beforeEach(async () => {
  await reset()
  ok(await setDoc(COUPLE, { userIds: [A, B] }, 'owner'), 'seed couple')
})

// 1. Create

test('create: a member adds her own memory or capsule', async () => {
  ok(await create('m1', { by: A }, A), 'memory')
  ok(await create('m2', { by: B, photoURL: 'https://example.com/photo.jpg', anniversaryId: 'a1' }, B), 'every optional field')
  ok(await create('c1', { by: A, unlockDate: at(30 * DAY) }, A), 'capsule')
})

test('create: a memory authored by the partner is denied', async () => {
  no(await create('m1', { by: B }, A))
})

test('create: an id field that names another document is denied', async () => {
  no(await commit([W.set(MEM('m1'), payload('m2').data)], A))
})

test('create: an outsider cannot add a memory', async () => {
  no(await create('m1', { by: M }, M), 'mallory')
  no(await create('m1', { by: A }, null), 'signed out')
})

test('create: a legacy memory without createdBy (or without an id field) is still allowed', async () => {
  const { data } = payload('m1')
  delete data.createdBy
  ok(await commit([W.set(MEM('m1'), data)], A), 'no createdBy')
  const { data: noId } = payload('m2')
  delete noId.id
  ok(await commit([W.set(MEM('m2'), noId)], A), 'no id field')
})

// 2. Edits

test('update: the partner edits a normal memory with a full merge', async () => {
  const seed = { by: A, photoURL: 'https://example.com/photo.jpg', anniversaryId: 'a1' }
  ok(await create('m1', seed, A), 'seed')
  ok(await edit('m1', { ...seed, title: 'Lisbon, again', photoURL: undefined }, B), 'retitled, photo removed')
  const doc = await stored('m1')
  assert.equal(value(doc, 'title'), 'Lisbon, again')
  assert.equal(value(doc, 'photoURL'), undefined, 'the merge deleted photoURL')
  assert.equal(value(doc, 'anniversaryId'), 'a1')
  assert.equal(value(doc, 'createdBy'), A)
})

test('update: neither partner can change createdBy', async () => {
  const seed = { by: A }
  ok(await create('m1', seed, A), 'seed')
  no(await edit('m1', { ...seed, by: B }, B), 'the partner claims it')
  no(await edit('m1', { ...seed, by: B }, A), 'the author gives it away')
  no(await commit([W.update(MEM('m1'), { createdBy: B })], B), 'a partial update')
  const { data, unset } = payload('m1', seed)
  delete data.createdBy
  no(await commit([W.merge(MEM('m1'), data, [...unset, 'createdBy'])], A), 'removed')
})

test('update: the id field cannot change', async () => {
  const seed = { by: A }
  ok(await create('m1', seed, A), 'seed')
  const { data, unset } = payload('m1', seed)
  no(await commit([W.merge(MEM('m1'), { ...data, id: 'm2' }, unset)], B), 'by the partner')
  no(await commit([W.merge(MEM('m1'), { ...data, id: 'm2' }, unset)], A), 'by the author')
})

test('update: an outsider cannot edit a memory', async () => {
  const seed = { by: A }
  ok(await create('m1', seed, A), 'seed')
  no(await edit('m1', { ...seed, title: 'mine now' }, M))
})

// 3. Sealed capsules

test('sealed capsule: the partner edits its title, re-sending the same unlockDate', async () => {
  const seed = { by: A, unlockDate: at(30 * DAY) }
  ok(await create('c1', seed, A), 'seed')
  ok(await edit('c1', { ...seed, title: 'Open on our anniversary' }, B), 'full merge')
  ok(await commit([W.update(MEM('c1'), { note: 'p.s.', updatedAt: new Date() })], B), 'partial update')
  const doc = await stored('c1')
  assert.equal(value(doc, 'title'), 'Open on our anniversary')
  assert.equal(value(doc, 'unlockDate').getTime(), seed.unlockDate.getTime())
})

test('sealed capsule: an unlockDate re-sent within a second counts as unchanged', async () => {
  const seed = { by: A, unlockDate: at(30 * DAY) }
  ok(await create('c1', seed, A), 'seed')
  ok(await edit('c1', { ...seed, unlockDate: shift(seed.unlockDate, 500) }, B), '+500 ms')
  ok(await edit('c1', seed, B), 'back by 500 ms')
})

test('sealed capsule: the partner cannot remove or move its unlockDate', async () => {
  const seed = { by: A, unlockDate: at(30 * DAY) }
  ok(await create('c1', seed, A), 'seed')
  no(await edit('c1', { ...seed, unlockDate: undefined }, B), 'removed (capsule switched off)')
  no(await edit('c1', { ...seed, unlockDate: shift(seed.unlockDate, -29 * DAY) }, B), 'earlier')
  no(await edit('c1', { ...seed, unlockDate: at(-HOUR) }, B), 'into the past, opening it now')
  no(await edit('c1', { ...seed, unlockDate: shift(seed.unlockDate, DAY) }, B), 'later by a day')
  no(await edit('c1', { ...seed, unlockDate: shift(seed.unlockDate, 2 * SECOND) }, B), 'later by 2 s')
  no(await commit([W.update(MEM('c1'), { unlockDate: null })], B), 'set to null')
  no(await commit([W.update(MEM('c1'), { unlockDate: '2030-01-01' })], B), 'set to a string')
  assert.equal(value(await stored('c1'), 'unlockDate').getTime(), seed.unlockDate.getTime(), 'still as sealed')

  const bobs = { by: B, unlockDate: at(30 * DAY) }
  ok(await create('c2', bobs, B), 'seed a capsule by bob')
  no(await edit('c2', { ...bobs, unlockDate: undefined }, A), 'alice removes bob\'s')
})

test('sealed capsule: its author can move or remove her own unlockDate', async () => {
  const seed = { by: A, unlockDate: at(30 * DAY) }
  ok(await create('c1', seed, A), 'seed')
  ok(await edit('c1', { ...seed, unlockDate: shift(seed.unlockDate, DAY) }, A), 'later')
  ok(await edit('c1', { ...seed, unlockDate: at(7 * DAY) }, A), 'earlier')
  ok(await edit('c1', { ...seed, unlockDate: undefined }, A), 'removed')
  assert.equal(value(await stored('c1'), 'unlockDate'), undefined)
})

test('opened capsule: the partner can remove its unlockDate', async () => {
  const seed = { by: A, unlockDate: at(-DAY) }
  ok(await create('c1', seed, A), 'seed, opened yesterday')
  ok(await edit('c1', { ...seed, unlockDate: undefined }, B))
})

// 4. Delete

test('delete: the partner can delete a sealed capsule (1.2 offers Delete to both)', async () => {
  ok(await create('c1', { by: A, unlockDate: at(30 * DAY) }, A), 'seed')
  ok(await deleteDoc(MEM('c1'), B))
  assert.equal((await getDoc(MEM('c1'), A)).status, 404, 'gone')
})

test('delete: an outsider cannot delete a memory', async () => {
  ok(await create('m1', { by: A }, A), 'seed')
  no(await deleteDoc(MEM('m1'), M), 'mallory')
  no(await deleteDoc(MEM('m1'), null), 'signed out')
})

// 5. Reads did not change

test('read: both partners get and list memories, outsiders cannot', async () => {
  ok(await create('m1', { by: A }, A), 'seed')
  ok(await listDocs(MEMORIES, A), 'A lists')
  ok(await listDocs(MEMORIES, B), 'B lists')
  no(await listDocs(MEMORIES, M), 'M lists')
  ok(await getDoc(MEM('m1'), B), 'B gets')
  no(await getDoc(MEM('m1'), M), 'M gets')
  no(await getDoc(MEM('m1'), null), 'signed out gets')
})
