// Rules tests for the couple document itself (firestore.rules,
// "/couples/{coupleId}"): pairing, disconnect, the purge, every field the app
// merges into it, and the two things nobody may rewrite once a couple exists:
// its userIds and a disconnected status.
//
//   firebase emulators:exec --only firestore --project demo-coupley-rules \
//     "node --test firestore-tests/"
//
// Writes mirror what the iOS client sends; 1.1, 1.2, 1.3 and the garden build
// send the same ones. Pairing is ONE batch that creates a new couple (never an
// update of an old one). Every later write to the couple is
// setData(_:merge: true): the SDK sends a mask of every leaf path (a nested
// map such as `premium` merges field by field), server times as transforms
// and FieldValue.delete() as a masked field with no value. `merge()` below
// builds exactly that.

import { test, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { forDatabase, SERVER_TIME, encode, value } from './emulator.mjs'

// node --test runs the test files in parallel and each one resets its database
// before every test, so this file keeps to a database of its own.
const { reset, commit, setDoc, getDoc, W } = forDatabase('couples-rules')

const A = 'alice'
const B = 'bob'
const M = 'mallory' // not in the couple
const C = 'couples/c1'
const user = (uid) => `users/${uid}`

const ok = (r, why = '') =>
  assert.ok(r.ok, `expected ALLOW ${why}: ${r.status} ${JSON.stringify(r.body)}`)
// A denial must be the rules saying no (403), not a malformed request (400)
// or a missing document (404) that would make the test pass for nothing.
const no = (r, why = '') =>
  assert.equal(r.status, 403, `expected DENY (403) ${why}, got ${r.status} ${JSON.stringify(r.body)}`)

/** FieldValue.delete() inside `merge()`. */
const DELETE = Symbol('delete')

/**
 * setData(data, merge: true) as the iOS SDK sends it: the mask is every leaf
 * path (nested maps merge field by field), SERVER_TIME at any depth becomes a
 * REQUEST_TIME transform, and DELETE removes that field.
 */
function merge(path, data) {
  const mask = []
  const transforms = []
  const leaves = (obj, prefix) => Object.fromEntries(Object.entries(obj).flatMap(([k, v]) => {
    const p = prefix + k
    if (v === SERVER_TIME) {
      transforms.push({ fieldPath: p, setToServerValue: 'REQUEST_TIME' })
      return []
    }
    if (v === DELETE) {
      mask.push(p)
      return []
    }
    if (v && typeof v === 'object' && !(v instanceof Date) && !Array.isArray(v)) {
      const inner = leaves(v, `${p}.`)
      return Object.keys(inner).length ? [[k, inner]] : []
    }
    mask.push(p)
    return [[k, v]]
  }))
  const w = W.set(path, leaves(data, ''))
  w.updateMask = { fieldPaths: mask }
  if (transforms.length) w.updateTransforms = transforms
  return w
}

/** updateData([field: FieldValue.arrayUnion(values)]). */
function arrayUnion(path, field, ...values) {
  const w = W.update(path, {})
  w.updateTransforms = [{ fieldPath: field, appendMissingElements: { values: values.map(encode) } }]
  return w
}

/** A REST array field as a list of strings. */
const strings = (doc, name) => doc?.fields?.[name]?.arrayValue?.values?.map((v) => v.stringValue)

async function stored(path) {
  const r = await getDoc(path, A)
  ok(r, `read ${path}`)
  return r.body
}

/** A couple as pairing left it, and both user docs pointing at it. */
async function paired(status = 'active') {
  ok(await setDoc(C, { userIds: [A, B], createdAt: new Date(), currentStreak: 0, longestStreak: 0, status }, 'owner'),
    'seed couple')
  ok(await setDoc(user(A), { displayName: 'Alice', coupleId: 'c1', partnerId: B }, 'owner'), 'seed alice')
  ok(await setDoc(user(B), { displayName: 'Bob', coupleId: 'c1', partnerId: A }, 'owner'), 'seed bob')
}

/** ConnectionService.disconnect's two couple writes (its user-doc writes are in test 3). */
const disconnect = (by) => [
  merge(C, { status: 'disconnected', disconnectedAt: SERVER_TIME, disconnectedBy: by }),
  merge(C, { premium: { active: false } }),
]

beforeEach(async () => {
  await reset()
})

// ====================================================================
// pairing
// ====================================================================

test('1. pairing: the joiner creates the couple, both links and deletes the code in one batch', async () => {
  ok(await setDoc(user(A), { displayName: 'Alice' }, 'owner'), 'seed alice, unpaired')
  ok(await setDoc(user(B), { displayName: 'Bob', lastCoupleId: 'c0', lastPartnerId: M }, 'owner'),
    'seed bob, unpaired after an earlier couple')
  ok(await setDoc('pairingCodes/K7Q2ZP', { creatorId: A, expiresAt: new Date(Date.now() + 3600e3) }, 'owner'),
    'seed alice\'s code')
  const cleared = { lastCoupleId: DELETE, lastPartnerId: DELETE, lastPartnerName: DELETE, pendingDisconnectNotice: DELETE }
  ok(await commit([
    W.set('couples/c2', { userIds: [A, B], createdAt: SERVER_TIME, currentStreak: 0, longestStreak: 0, status: 'active' }),
    merge(user(A), { coupleId: 'c2', partnerId: B, ...cleared }),
    merge(user(B), { coupleId: 'c2', partnerId: A, ...cleared }),
    W.del('pairingCodes/K7Q2ZP'),
  ], B), 'bob joins with alice\'s code')
  const couple = await stored('couples/c2')
  assert.deepEqual(strings(couple, 'userIds'), [A, B])
  assert.equal(value(couple, 'status'), 'active')
})

test('2. pairing: a new couple has exactly two ids, mine among them', async () => {
  no(await setDoc('couples/c2', { userIds: [A, B, M], status: 'active' }, A), 'three ids')
  no(await setDoc('couples/c2', { userIds: [B, M], status: 'active' }, A), 'without me')
  no(await setDoc('couples/c2', { userIds: [A], status: 'active' }, A), 'only me')
  no(await setDoc('couples/c2', { userIds: [A, B], status: 'active' }, null), 'signed out')
})

// ====================================================================
// disconnect and purge
// ====================================================================

test('3. disconnect: the batch every version sends (two couple merges, both user docs)', async () => {
  await paired()
  ok(await commit([
    ...disconnect(A),
    merge(user(A), { coupleId: DELETE, partnerId: DELETE, lastCoupleId: 'c1', lastPartnerId: B }),
    merge(user(B), { coupleId: DELETE, partnerId: DELETE, lastCoupleId: 'c1', lastPartnerId: A,
                     pendingDisconnectNotice: true, lastPartnerName: 'Alice' }),
  ], A), 'alice disconnects')
  const couple = await stored(C)
  assert.equal(value(couple, 'status'), 'disconnected')
  assert.equal(value(couple, 'disconnectedBy'), A)
  assert.deepEqual(strings(couple, 'userIds'), [A, B], 'the ids are kept')
})

test('4. disconnect: sent again on a disconnected couple (another device, a retry) it still lands', async () => {
  await paired('disconnected')
  for (const auth of [A, B]) ok(await commit(disconnect(auth), auth), `${auth} disconnects again`)
  assert.equal(value(await stored(C), 'status'), 'disconnected')
})

test('5. purge: after the disconnect a member deletes shared data, then the couple', async () => {
  await paired()
  ok(await setDoc(`${C}/moods/m1`, { userId: A }, 'owner'), 'seed a mood')
  no(await commit([W.del(C)], A), 'the couple while it is active')
  ok(await commit(disconnect(A), A), 'alice disconnects')
  ok(await getDoc(C, B), 'bob reads it (the purge guard)')
  ok(await commit([W.del(`${C}/moods/m1`)], B), 'bob deletes a mood')
  ok(await commit([W.del(C)], B), 'then the couple')
  ok(await commit([merge(user(B), { lastCoupleId: DELETE, lastPartnerId: DELETE, lastPartnerName: DELETE })], B),
    'and clears his pointer')
})

// ====================================================================
// everything the app merges
// ====================================================================

test('6. merges: premium, streak, chat, daily question and photo land on an active and a disconnected couple', async () => {
  const writes = [
    ['premium bought', { premium: { active: true, plan: 'removeAds', purchaserId: A, purchasedAt: SERVER_TIME,
                                    expiresAt: DELETE } }],
    ['premium cleared', { premium: { active: false } }],
    ['streak counted', { currentStreak: 3, longestStreak: 5, lastStreakDate: new Date() }],
    ['streak reset', { currentStreak: 0, lastStreakDate: DELETE }],
    ['quiz suggested', { lastQuizSuggestedAt: SERVER_TIME, lastMessageAt: SERVER_TIME }],
    ['message sent', { lastMessageAt: SERVER_TIME }],
    ['daily question', { qotdSequence: 4, qotdCurrentId: 'qotd-4', qotdLastCreatedAt: SERVER_TIME,
                         lastMessageAt: SERVER_TIME }],
    ['daily photo', { potdSequence: 2, potdCurrentId: 'potd-2', potdLastCreatedAt: SERVER_TIME }],
  ]
  for (const status of ['active', 'disconnected']) {
    await paired(status)
    for (const auth of [A, B]) {
      for (const [why, data] of writes) ok(await commit([merge(C, data)], auth), `${why} by ${auth} (${status})`)
    }
    const couple = await stored(C)
    assert.equal(value(couple, 'status'), status, 'status kept')
    assert.deepEqual(strings(couple, 'userIds'), [A, B], 'ids kept')
    assert.equal(value(couple, 'qotdCurrentId'), 'qotd-4')
  }
})

test('7. merges: a couple paired before the status field existed merges and disconnects', async () => {
  ok(await setDoc(C, { userIds: [A, B], currentStreak: 0, longestStreak: 0 }, 'owner'), 'seed an old couple')
  ok(await commit([merge(C, { lastMessageAt: SERVER_TIME })], A), 'a message')
  ok(await commit(disconnect(B), B), 'bob disconnects')
  no(await commit([merge(C, { status: 'active' })], A), 'and it stays disconnected')
})

// ====================================================================
// what nobody rewrites
// ====================================================================

test('8. status: once disconnected, no member makes the couple active again', async () => {
  await paired('disconnected')
  for (const auth of [A, B]) {
    no(await commit([merge(C, { status: 'active' })], auth), `${auth} sets it back to active`)
    no(await commit([merge(C, { status: DELETE })], auth), `${auth} removes it`)
    no(await commit([merge(C, { status: 'paused' })], auth), `${auth} sets another value`)
    no(await commit([W.update(C, { status: 'active' })], auth), `${auth} updates it`)
    no(await commit([W.set(C, { userIds: [A, B], status: 'active' })], auth), `${auth} rewrites the couple`)
  }
  assert.equal(value(await stored(C), 'status'), 'disconnected')
})

test('9. userIds: no member adds, drops, swaps or reorders an id', async () => {
  await paired()
  for (const auth of [A, B]) {
    const cases = [
      ['adds a third id', [A, B, M]],
      ['drops the partner', [auth]],
      ['swaps the partner', [auth, M]],
      ['reorders them', [B, A]],
      ['empties them', []],
    ]
    for (const [why, ids] of cases) no(await commit([merge(C, { userIds: ids })], auth), `${auth} ${why}`)
    no(await commit([arrayUnion(C, 'userIds', M)], auth), `${auth} adds one with arrayUnion`)
    no(await commit([merge(C, { userIds: DELETE })], auth), `${auth} removes the field`)
  }
  assert.deepEqual(strings(await stored(C), 'userIds'), [A, B])
})

test('10. userIds: a set without them is denied (it would lock both members out)', async () => {
  await paired()
  no(await commit([W.set(C, { status: 'active', premium: { active: false } })], A), 'alice')
  no(await commit([W.set(C, { lastMessageAt: new Date() })], B), 'bob')
  ok(await getDoc(C, B), 'still readable by its members')
})

test('11. outsiders: nobody else updates the couple', async () => {
  await paired()
  no(await commit([merge(C, { premium: { active: false } })], M), 'mallory')
  no(await commit([merge(C, { userIds: [A, B, M] })], M), 'mallory adds herself')
  no(await commit([merge(C, { lastMessageAt: SERVER_TIME })], null), 'signed out')
})
