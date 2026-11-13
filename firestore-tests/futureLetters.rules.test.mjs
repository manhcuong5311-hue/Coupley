// Rules tests for future letters (firestore.rules, "Future letters" block).
//
//   firebase emulators:exec --only firestore --project demo-coupley-rules \
//     "node --test firestore-tests/futureLetters.rules.test.mjs"
//
// Writes mirror what the iOS client sends: a sealed letter is ONE batch of two
// plain sets (envelope + body), `sealedAt`/`openedAt` are server timestamps.

import { test, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { reset, commit, setDoc, updateDoc, getDoc, listDocs, W, SERVER_TIME } from './emulator.mjs'

const A = 'alice' // sender in most tests
const B = 'bob' // recipient
const M = 'mallory' // not in the couple
const COUPLE = 'couples/c1'
const ENVELOPES = `${COUPLE}/futureLetters`
const BODIES = `${COUPLE}/futureLetterBodies`
const ENV = (id) => `${ENVELOPES}/${id}`
const BODY = (id) => `${BODIES}/${id}`

const HOUR = 3600e3
const DAY = 24 * HOUR
const at = (ms) => new Date(Date.now() + ms)

const ok = (r, why = '') =>
  assert.ok(r.ok, `expected ALLOW ${why}: ${r.status} ${JSON.stringify(r.body)}`)
// A denial must be the rules saying no (403), not a malformed request (400)
// or a missing document (404) that would make the test pass for nothing.
const no = (r, why = '') =>
  assert.equal(r.status, 403, `expected DENY (403) ${why}, got ${r.status} ${JSON.stringify(r.body)}`)

/** The two writes of one sealed letter. */
function seal(id, o = {}) {
  const { from = A, to = B, opensAt = at(HOUR), text = 'hello', env = {}, body = {}, bodyOpensAt = opensAt } = o
  return [
    W.set(ENV(id), { id, fromUserId: from, toUserId: to, opensAt, sealedAt: SERVER_TIME, ...env }),
    W.set(BODY(id), { fromUserId: from, toUserId: to, opensAt: bodyOpensAt, text, ...body }),
  ]
}

const couple = async (status = 'active') =>
  ok(await setDoc(COUPLE, { userIds: [A, B], status }, 'owner'), 'seed couple')

/** L1 opens in an hour (sealed); L2 opened a minute ago (ready, unopened). */
async function seedTwo() {
  ok(await commit(seal('L1'), A), 'seal L1')
  ok(await commit(seal('L2', { opensAt: at(-60e3) }), A), 'seal L2 (already due)')
}

beforeEach(async () => {
  await reset()
  await couple()
})

// 1. Sealing

test('seal: envelope and body in one batch is allowed', async () => {
  ok(await commit(seal('L1'), A))
})

test('seal: envelope alone or body alone is denied', async () => {
  const [env, body] = seal('L1')
  no(await commit([env], A), 'envelope alone')
  no(await commit([body], A), 'body alone')
})

// 2. Create validation

test('seal: every malformed or foreign letter is denied', async () => {
  const cases = [
    ['from B under A token', seal('X1', { from: B, to: A }), A],
    ['to self', seal('X2', { to: A }), A],
    ['to someone outside the couple', seal('X3', { to: M }), A],
    ['envelope id differs from doc id', seal('X4', { env: { id: 'Y' } }), A],
    ['extra envelope key', seal('X5', { env: { preview: 'Dear Bob' } }), A],
    ['extra body key', seal('X6', { body: { label: 'birthday' } }), A],
    ['openedAt preset', seal('X7', { env: { openedAt: new Date() } }), A],
    ['client sealedAt', seal('X8', { env: { sealedAt: new Date() } }), A],
    ['opensAt not a timestamp', seal('X9', { opensAt: 'tomorrow' }), A],
    ['opensAt beyond 3700 days', seal('X10', { opensAt: at(3701 * DAY) }), A],
    ['body opensAt differs', seal('X11', { bodyOpensAt: at(2 * HOUR) }), A],
    ['empty text', seal('X12', { text: '' }), A],
    ['text over 100,000 chars', seal('X13', { text: 'x'.repeat(100001) }), A],
    ['writer outside the couple', seal('X14', { from: M, to: B }), M],
    ['signed out', seal('X15'), null],
  ]
  for (const [why, writes, auth] of cases) no(await commit(writes, auth), why)
})

test('seal: a letter due in the past still lands (late offline sync)', async () => {
  ok(await commit(seal('L2', { opensAt: at(-60e3) }), A))
})

test('seal: a disconnected couple cannot seal', async () => {
  await couple('disconnected')
  no(await commit(seal('L1'), A))
})

test('seal: an existing body cannot be overwritten', async () => {
  ok(await commit(seal('L1'), A))
  no(await setDoc(BODY('L1'), { fromUserId: A, toUserId: B, opensAt: at(HOUR), text: 'changed' }, A))
  no(await commit(seal('L1'), A), 'resealing the same id')
})

// 3. Envelopes are readable by both partners only

test('envelopes: both partners list and get, outsiders cannot', async () => {
  await seedTwo()
  ok(await listDocs(ENVELOPES, A), 'A lists')
  ok(await listDocs(ENVELOPES, B), 'B lists')
  no(await listDocs(ENVELOPES, M), 'M lists')
  ok(await getDoc(ENV('L1'), B), 'B gets')
  no(await getDoc(ENV('L1'), M), 'M gets')
  no(await getDoc(ENV('L1'), null), 'signed out gets')
})

// 4. THE SEAL

test('body: the recipient cannot read it before opensAt; the sender can', async () => {
  await seedTwo()
  no(await getDoc(BODY('L1'), B), 'B before opensAt')
  ok(await getDoc(BODY('L1'), A), 'A (sender)')
  no(await getDoc(BODY('L1'), M), 'M')
})

test('body: nobody can list bodies, not even after they open', async () => {
  await seedTwo()
  no(await listDocs(BODIES, A), 'A lists')
  no(await listDocs(BODIES, B), 'B lists')
})

test('body: the recipient reads it once opensAt has passed', async () => {
  await seedTwo()
  ok(await getDoc(BODY('L2'), B))
})

test('body: a missing body is denied, not "not found"', async () => {
  no(await getDoc(BODY('nope'), B))
})

// 5. Opening receipt

test('openedAt: only the recipient, only after opensAt, only once, only server time', async () => {
  await seedTwo()
  no(await updateDoc(ENV('L1'), { openedAt: SERVER_TIME }, B), 'B on a sealed letter')
  no(await updateDoc(ENV('L2'), { openedAt: new Date() }, B), 'client time')
  no(await updateDoc(ENV('L2'), { openedAt: SERVER_TIME }, A), 'the sender')
  no(await updateDoc(ENV('L2'), { openedAt: SERVER_TIME, opensAt: at(-2 * HOUR) }, B), 'with another field')
  ok(await updateDoc(ENV('L2'), { openedAt: SERVER_TIME }, B), 'B stamps')
  no(await updateDoc(ENV('L2'), { openedAt: SERVER_TIME }, B), 'second stamp')
})

test('nothing else is editable after sealing', async () => {
  await seedTwo()
  no(await updateDoc(ENV('L1'), { opensAt: at(-HOUR) }, A), 'sender moves opensAt earlier')
  no(await updateDoc(ENV('L1'), { toUserId: A }, A), 'sender redirects')
  no(await updateDoc(BODY('L2'), { text: 'x' }, A), 'sender edits body')
  no(await updateDoc(BODY('L2'), { text: 'x' }, B), 'recipient edits body')
})

// 6. Unsend

test('unsend: only the sender, only both docs together, only before opensAt', async () => {
  await seedTwo()
  no(await commit([W.del(ENV('L1'))], A), 'envelope alone')
  no(await commit([W.del(BODY('L1'))], A), 'body alone')
  no(await commit([W.del(BODY('L1')), W.del(ENV('L1'))], B), 'by the recipient')
  no(await commit([W.del(BODY('L2')), W.del(ENV('L2'))], A), 'after it opened')
  ok(await commit([W.del(BODY('L1')), W.del(ENV('L1'))], A), 'sender, sealed, both docs')
  assert.equal((await getDoc(ENV('L1'), A)).status, 404, 'envelope gone')
})

// 7. Disconnect

test('disconnect: delivery freezes, either member can purge', async () => {
  await seedTwo()
  await couple('disconnected')
  no(await getDoc(BODY('L2'), B), 'recipient after disconnect')
  ok(await getDoc(BODY('L2'), A), 'sender keeps own copy')
  ok(await listDocs(ENVELOPES, B), 'envelopes still listable for the purge')
  ok(await commit([W.del(BODY('L2')), W.del(ENV('L2'))], B), 'recipient purges')
  ok(await commit([W.del(BODY('missing'))], A), 'deleting a missing body is fine')
})

test('disconnect: purging 200 letters (400 deletes) fits in one batch', async () => {
  const writes = []
  for (let i = 0; i < 200; i++) writes.push(...seal(`P${i}`, { opensAt: at((i - 100) * HOUR) }))
  // Seed as owner: rules do not apply, and SERVER_TIME transforms still work.
  ok(await commit(writes, 'owner'), 'seed 200 letters')
  await couple('disconnected')
  const deletes = []
  for (let i = 0; i < 200; i++) deletes.push(W.del(BODY(`P${i}`)), W.del(ENV(`P${i}`)))
  ok(await commit(deletes, A), '400 deletes in one batch')
})

// 8. Nothing else changed

test('regression: existing collections behave as before', async () => {
  ok(await setDoc(`${COUPLE}/moods/m1`, { userId: A }, A), 'mood')
  no(await getDoc(`${COUPLE}/moods/m1`, M), 'outsider reads mood')
  ok(await setDoc(`${COUPLE}/photoOfDay/p1`, { id: 'p1' }, A), 'photo of the day')
})
