// End-to-end tests for the garden's Cloud Functions (onTimeTreeMetaWritten,
// onCouplePurged, the push ledger and the remote switch), against the
// Firestore and Functions emulators. Run from the repo root (both emulators
// need Java 21):
//
//   firebase emulators:exec --only firestore,functions --project demo-coupley-rules \
//     "node --test functions/test/garden.emulator.test.mjs"
//
// The existing functions read the OPENAI_API_KEY secret when they load, so
// put a dummy one in functions/.secret.local first (git-ignored, never
// deployed):  echo 'OPENAI_API_KEY=dummy' > functions/.secret.local
//
// Every test is skipped unless FIRESTORE_EMULATOR_HOST is set. A `demo-`
// project keeps everything offline. Documents are seeded and written as
// `owner` through the REST harness (the rules are P1's suite; here the
// functions are under test). Under the emulator `sendNotification` records
// each push in `pushDryRun` instead of calling FCM, and the tests poll that
// outbox. Each test has its own couple and users, so the tests never share a
// daily cap or read each other's pushes, and nothing needs a reset.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { randomBytes } from 'node:crypto'
import { forDatabase, PROJECT } from '../../firestore-tests/emulator.mjs'

const skip = process.env.FIRESTORE_EMULATOR_HOST
  ? false
  : 'needs the Firestore and Functions emulators (FIRESTORE_EMULATOR_HOST is not set)'

// Triggers fire on the (default) database only.
const { setDoc, deleteDoc, getDoc, listDocs } = forDatabase()

const HOUR = 3600e3
const DAY = 24 * HOUR
/** How long a push may take to land. The first trigger also loads the functions. */
const POLL_MS = 15_000
/** How long to keep watching once a "no push" decision could have been made. */
const SETTLE_MS = 2_500
const RUN = Date.now().toString(36)

const etest = (name, fn) => test(name, { skip, timeout: 60_000 }, fn)
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const ok = (r, why = '') => assert.ok(r.ok, `${why}: ${r.status} ${JSON.stringify(r.body)}`)

// MARK: - REST decoding

function decodeValue(f) {
  if (!f) return undefined
  if ('stringValue' in f) return f.stringValue
  if ('integerValue' in f) return Number(f.integerValue)
  if ('doubleValue' in f) return f.doubleValue
  if ('booleanValue' in f) return f.booleanValue
  if ('timestampValue' in f) return new Date(f.timestampValue)
  if ('nullValue' in f) return null
  if ('mapValue' in f) return decodeFields(f.mapValue.fields || {})
  if ('arrayValue' in f) return (f.arrayValue.values || []).map(decodeValue)
  return f
}
const decodeFields = (fields) => Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, decodeValue(v)]))
const decodeDoc = (doc) => ({ id: doc.name.split('/').pop(), ...decodeFields(doc.fields || {}) })

// MARK: - Fixtures

const alnum = (n) => {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  return Array.from(randomBytes(n), (b) => chars[b % chars.length]).join('')
}
const waterId = () => `water_${alnum(20)}`

/** An `Etc/GMT±N` zone whose local hour is `hour` right now. */
function zoneAtHour(hour) {
  for (let offset = -12; offset <= 14; offset++) {
    const zone = offset === 0 ? 'Etc/GMT' : `Etc/GMT${offset > 0 ? '-' : '+'}${Math.abs(offset)}`
    const h = Number(new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', hourCycle: 'h23' }).format(new Date()))
    if (h === hour) return zone
  }
  throw new Error(`no zone at ${hour}:00`)
}
/** Far from both edges of the quiet hours (22:00–06:59), so a test never straddles one. */
const CALM_ZONE = zoneAtHour(14)
const QUIET_ZONE = zoneAtHour(2)

const utcDayKey = () => new Date().toISOString().slice(0, 10).replace(/-/g, '')

let fixtures = 0

/**
 * A couple of Sam (`a`, the actor in most tests) and Alex (`b`). Each user is
 * 'garden' (token device runs a garden build), 'legacy' (a token, no
 * gardenPushToken) or 'off' (garden build, Garden toggle off).
 */
async function couple({ a = 'garden', b = 'garden', bZone = CALM_ZONE, status = 'active' } = {}) {
  const n = ++fixtures
  const c = `c-${RUN}-${n}`
  const A = `sam${RUN}x${n}`
  const B = `alex${RUN}x${n}`
  const user = (firstName, kind, timezone) => {
    const token = `tok-${firstName}-${RUN}-${n}`
    const doc = { firstName, fcmToken: token, timezone, notificationPreferences: { garden: kind !== 'off' } }
    if (kind !== 'legacy') doc.gardenPushToken = token
    return doc
  }
  ok(await setDoc(`users/${A}`, user('Sam', a, CALM_ZONE), 'owner'), 'seed Sam')
  ok(await setDoc(`users/${B}`, user('Alex', b, bZone), 'owner'), 'seed Alex')
  ok(await setDoc(`couples/${c}`, { userIds: [A, B], status }, 'owner'), 'seed couple')
  return { c, A, B, meta: (id) => `couples/${c}/timeTreeMeta/${id}` }
}

async function water(f, by, { at = new Date(), note } = {}) {
  const id = waterId()
  const doc = { docType: 'water', by, wateredAt: at, effect: 'can' }
  if (note !== undefined) doc.note = note
  ok(await setDoc(f.meta(id), doc, 'owner'), `water ${id}`)
  return { id, atMs: at.getTime() }
}

/** A tree seeded silently (`recorded` never pushes). */
async function recordedTree(f, slot, title) {
  ok(await setDoc(f.meta(`tree_${slot}`), {
    docType: 'tree', slot, key: `key-${slot}-${RUN}`, title, preset: slot === 'our' ? 'ourTree' : 'custom',
    scene: 'meadow', species: 'oak', origin: 'legacy', agreementKind: 'recorded', agreementBy: [f.A],
    agreementAt: new Date(), agreedStartDay: new Date(Date.UTC(2023, 2, 12, 10)), updatedAt: new Date(),
  }, 'owner'), `tree_${slot}`)
}

// MARK: - The outbox

async function dryRuns(f) {
  const r = await listDocs('pushDryRun?pageSize=1000', 'owner')
  ok(r, 'list pushDryRun')
  return (r.body?.documents || []).map(decodeDoc).filter((p) => p.data?.coupleId === f.c)
}

async function waitFor(what, probe, ms = POLL_MS) {
  const until = Date.now() + ms
  for (;;) {
    const found = await probe()
    if (found) return found
    if (Date.now() > until) assert.fail(`timed out after ${ms} ms waiting for ${what}`)
    await sleep(250)
  }
}

/** The one push matching `match`, once it lands. */
async function expectPush(f, what, match) {
  return waitFor(what, async () => (await dryRuns(f)).find(match))
}

const claimExists = async (key) => (await getDoc(`gardenPushClaims/${key}`, 'owner')).ok

/**
 * Asserts that no push matching `match` is sent. With `claimKey` it first
 * waits until the trigger has claimed the event (so the function did run),
 * then gives it time to finish; otherwise it waits a fixed while.
 */
async function expectNoPush(f, what, match, claimKey) {
  if (claimKey) await waitFor(`the claim ${claimKey}`, () => claimExists(claimKey))
  await sleep(claimKey ? SETTLE_MS : POLL_MS / 2)
  assert.equal((await dryRuns(f)).filter(match).length, 0, `unexpected push: ${what}`)
}

const forWatering = (id) => (p) => p.data.wateringId === id

// MARK: - Waterings

etest('watered: plain, one tree, with every payload key', async () => {
  const f = await couple()
  await recordedTree(f, 'our', 'Our tree')
  const before = await water(f, f.A, { at: new Date(Date.now() - 2 * DAY) })
  await expectPush(f, 'the earlier watering', forWatering(before.id))
  const w = await water(f, f.A)
  const p = await expectPush(f, 'the plain watering', forWatering(w.id))
  assert.equal(p.userId, f.B)
  assert.equal(p.type, 'garden_watered')
  assert.equal(p.title, 'Sam watered your garden 💧')
  assert.equal(p.body, 'Your tree had a drink. Peek when you have a moment.')
  assert.deepEqual(p.data, {
    type: 'garden_watered', coupleId: f.c, navigateTo: 'journey', gardenFocus: 'watering',
    wateringId: w.id, moment: 'plain', wateredAtMs: String(w.atMs),
  })
  assert.deepEqual(p.options, { threadId: `coupley-garden-${f.c}`, quiet: false, contentAvailable: true })
})

etest('watered: a note, and every tree had a drink', async () => {
  const f = await couple()
  await recordedTree(f, 'our', 'Our tree')
  await recordedTree(f, 'p1', 'Our first trip')
  const before = await water(f, f.A, { at: new Date(Date.now() - 3 * DAY) })
  await expectPush(f, 'the earlier watering', forWatering(before.id))
  const w = await water(f, f.A, { note: 'Miss\n you  too.' })
  const p = await expectPush(f, 'the watering with a note', forWatering(w.id))
  assert.equal(p.data.moment, 'plain')
  assert.equal(p.body, '“Miss you too.”')

  const bare = await water(f, f.A, { at: new Date(Date.now() + 1000) })
  const q = await expectPush(f, 'the watering without a note', forWatering(bare.id))
  assert.equal(q.body, 'Every tree had a drink. Peek when you have a moment.')
})

etest('watered: the first watering ever', async () => {
  const f = await couple()
  const w = await water(f, f.A)
  const p = await expectPush(f, 'the first watering', forWatering(w.id))
  assert.equal(p.data.moment, 'first')
  assert.equal(p.title, 'Sam gave your tree its first water 💧')
  assert.equal(p.body, 'Your garden is growing on Journey.')
})

etest('watered: together, Sam then Alex and Alex then Sam', async () => {
  for (const [first, second, name] of [['A', 'B', 'Alex'], ['B', 'A', 'Sam']]) {
    const f = await couple({ a: 'garden', b: 'garden' })
    const earlier = await water(f, f[first], { at: new Date(Date.now() - 3 * HOUR) })
    await expectPush(f, 'the earlier watering', forWatering(earlier.id))
    const w = await water(f, f[second])
    const p = await expectPush(f, `${name} watering back`, forWatering(w.id))
    assert.equal(p.userId, f[first])
    assert.equal(p.data.moment, 'together')
    assert.equal(p.title, 'You watered together 💧')
    assert.equal(p.body, `${name} watered back, 3 hours after you.`)
  }
})

etest('watered: after 7 days the garden wakes up', async () => {
  const f = await couple()
  const old = await water(f, f.B, { at: new Date(Date.now() - 8 * DAY) })
  await expectPush(f, 'the old watering', forWatering(old.id))
  const w = await water(f, f.A)
  const p = await expectPush(f, 'the returning watering', forWatering(w.id))
  assert.equal(p.data.moment, 'returned')
  assert.equal(p.title, 'Sam woke up the garden 🌧️')
  assert.equal(p.body, "It rested a while. It's green again.")
})

etest('watered: no push to a legacy partner', async () => {
  const f = await couple({ b: 'legacy' })
  const w = await water(f, f.A)
  await expectNoPush(f, 'legacy partner', forWatering(w.id), `w_${f.c}_${w.id}`)
})

etest('watered: no push with the Garden toggle off', async () => {
  const f = await couple({ b: 'off' })
  const w = await water(f, f.A)
  await expectNoPush(f, 'toggle off', forWatering(w.id), `w_${f.c}_${w.id}`)
})

etest('watered: no push for a disconnected couple', async () => {
  const f = await couple({ status: 'disconnected' })
  const w = await water(f, f.A)
  await expectNoPush(f, 'disconnected couple', forWatering(w.id), `w_${f.c}_${w.id}`)
})

etest('watered: the seventh garden push of the day is dropped', async () => {
  const f = await couple()
  const daily = `gardenPushDaily/${f.B}_${utcDayKey()}`
  ok(await setDoc(daily, { count: 5, day: utcDayKey(), at: new Date() }, 'owner'), 'five pushes already today')
  const sixth = await water(f, f.A, { at: new Date(Date.now() - HOUR) })
  await expectPush(f, 'the sixth push', forWatering(sixth.id))
  const seventh = await water(f, f.A)
  await expectNoPush(f, 'the seventh push', forWatering(seventh.id), `w_${f.c}_${seventh.id}`)
  const counter = await getDoc(daily, 'owner')
  ok(counter, 'daily counter')
  assert.equal(decodeDoc(counter.body).count, 6)
})

etest('watered: a quiet hour sends a passive push', async () => {
  const f = await couple({ bZone: QUIET_ZONE })
  const w = await water(f, f.A)
  const p = await expectPush(f, 'the night watering', forWatering(w.id))
  assert.equal(p.options.quiet, true)
  assert.equal(p.options.contentAvailable, true)
})

etest('watered: an event already claimed is not pushed again', async () => {
  const f = await couple()
  const id = waterId()
  ok(await setDoc(`gardenPushClaims/w_${f.c}_${id}`, { at: new Date() }, 'owner'), 'claim first')
  ok(await setDoc(f.meta(id), { docType: 'water', by: f.A, wateredAt: new Date(), effect: 'can' }, 'owner'), 'water')
  await expectNoPush(f, 'a duplicated event', forWatering(id))
})

etest('claimOnce: true the first time, false after', async () => {
  process.env.GCLOUD_PROJECT ||= PROJECT
  const require = createRequire(import.meta.url)
  const { gardenEmulatorHooks } = require('../index.js')
  try {
    assert.ok(gardenEmulatorHooks, 'index.js exports its emulator hooks when FIRESTORE_EMULATOR_HOST is set')
    const key = `test_${RUN}_${alnum(8)}`
    assert.equal(await gardenEmulatorHooks.claimOnce(key), true)
    assert.equal(await gardenEmulatorHooks.claimOnce(key), false)
  } finally {
    // index.js opened an Admin SDK client in this process; close it so the
    // test process can exit.
    await require('firebase-admin/firestore').getFirestore().terminate()
  }
})

// MARK: - Proposals and agreements

const proposalDoc = (o) => ({ docType: 'proposal', kind: 'plant', slot: 'new', key: `seed-${alnum(12)}`, rev: 1, ...o })
const forProposal = (id, to) => (p) => p.data.proposalId === id && p.userId === to

etest('proposal: a seed pushes, an edit by its proposer does not, a counter does', async () => {
  const f = await couple()
  const id = `seed_${f.A}_1`
  const t0 = Date.now()
  ok(await setDoc(f.meta(id), proposalDoc({ by: f.A, at: new Date(t0), title: 'Where we first met',
                                             note: 'Remember?' }), 'owner'), 'seed')
  const p = await expectPush(f, 'the seed', forProposal(id, f.B))
  assert.equal(p.type, 'garden_proposal')
  assert.equal(p.title, 'Sam wants to plant a tree with you 🌱')
  assert.equal(p.body, "For “Where we first met”. It's planted when you say yes.")
  assert.deepEqual(p.data, { type: 'garden_proposal', coupleId: f.c, navigateTo: 'journey',
                             gardenFocus: 'proposal', proposalId: id, kind: 'plant' })
  assert.equal(p.options.contentAvailable, false)

  ok(await setDoc(f.meta(id), proposalDoc({ by: f.A, at: new Date(t0 + 1000), rev: 2,
                                             title: 'Where we met' }), 'owner'), 'edit')
  ok(await setDoc(f.meta(id), proposalDoc({ by: f.B, at: new Date(t0 + 2000), rev: 3,
                                             title: 'Our first trip' }), 'owner'), 'counter')
  const counter = await expectPush(f, 'the counter', forProposal(id, f.A))
  assert.equal(counter.title, 'Alex suggested a change 🌱')
  assert.equal(counter.body, 'To your seed for “Our first trip”. Take a look on Journey.')
  await sleep(SETTLE_MS)
  assert.equal((await dryRuns(f)).filter(forProposal(id, f.B)).length, 1, 'the edit pushed')
})

etest('proposal: a rest request names its tree, a start date names both days', async () => {
  const f = await couple()
  await recordedTree(f, 'p3', 'Our first trip')
  ok(await setDoc(f.meta('rest_p3'), proposalDoc({ kind: 'rest', slot: 'p3', by: f.A, at: new Date() }), 'owner'), 'rest')
  const rest = await expectPush(f, 'the rest request', forProposal('rest_p3', f.B))
  assert.equal(rest.title, 'Sam asked to let a tree rest')
  assert.equal(rest.body, '“Our first trip” stays in your garden until you agree.')

  ok(await setDoc(f.meta('startdate'), proposalDoc({
    kind: 'startDate', slot: 'our', by: f.A, at: new Date(),
    startDay: new Date(Date.UTC(2023, 2, 10, 10)), fromStartDay: new Date(Date.UTC(2023, 2, 12, 10)),
  }), 'owner'), 'start date')
  const start = await expectPush(f, 'the start date', forProposal('startdate', f.B))
  assert.equal(start.title, 'Sam suggested a new start date')
  assert.equal(start.body, '10 March 2023 instead of 12 March 2023. It changes only if you agree.')
  assert.equal(start.data.kind, 'startDate')
})

const forTree = (slot, to) => (p) => p.data.treeSlot === slot && p.userId === to

etest('agreement: pushed to the proposer only', async () => {
  const f = await couple()
  ok(await setDoc(f.meta('tree_p1'), {
    docType: 'tree', slot: 'p1', key: `key-${alnum(12)}`, title: 'Where we first met', preset: 'firstMet',
    scene: 'meadow', species: 'cherry', origin: 'together', plantedAt: new Date(), plantedBy: [f.A, f.B],
    agreementKind: 'plant', agreementBy: [f.A, f.B], agreementAt: new Date(), fromProposal: `seed_${f.A}_1`,
    updatedAt: new Date(),
  }, 'owner'), 'planted')
  const p = await expectPush(f, 'the agreement', forTree('p1', f.A))
  assert.equal(p.type, 'garden_agreed')
  assert.equal(p.title, 'Alex said yes 🌳')
  assert.equal(p.body, 'Your tree for “Where we first met” is planted. Come see it grow.')
  assert.deepEqual(p.data, { type: 'garden_agreed', coupleId: f.c, navigateTo: 'journey',
                             gardenFocus: 'tree', treeSlot: 'p1', kind: 'plant' })
  await sleep(SETTLE_MS)
  assert.equal((await dryRuns(f)).filter(forTree('p1', f.B)).length, 0, 'the accepter was pushed')

  // A proposer who is not the accepter's partner is never pushed.
  const agreementAt = new Date(Date.now() + 1000)
  ok(await setDoc(f.meta('tree_p2'), {
    docType: 'tree', slot: 'p2', key: `key-${alnum(12)}`, title: 'Our first trip', preset: 'firstTrip',
    scene: 'meadow', species: 'oak', origin: 'together', agreementKind: 'plant',
    agreementBy: ['mallory', f.B], agreementAt, updatedAt: new Date(),
  }, 'owner'), 'planted with a stranger')
  await expectNoPush(f, 'a stranger proposer', (x) => x.data.treeSlot === 'p2',
    `a_${f.c}_p2_${agreementAt.getTime()}`)
})

etest('agreement: a recorded Our tree is silent', async () => {
  const f = await couple()
  await recordedTree(f, 'our', 'Our tree')
  await expectNoPush(f, 'a recording', (p) => p.data.treeSlot === 'our')
})

// MARK: - Purge

etest('onCouplePurged: deleting the couple empties timeTreeMeta, memories and futureLetters', async () => {
  const f = await couple({ b: 'legacy' })
  ok(await setDoc(f.meta('config'), { startDate: new Date(Date.UTC(2023, 2, 12, 10)), setBy: f.A }, 'owner'), 'config')
  await recordedTree(f, 'our', 'Our tree')
  ok(await setDoc(f.meta(`waterer_${f.A}`), { docType: 'waterer', lastWateredAt: new Date(),
                                               lastWateringId: waterId() }, 'owner'), 'waterer')
  ok(await setDoc(`couples/${f.c}/memories/m1`, { title: 'A memory', createdAt: new Date() }, 'owner'), 'memory')
  ok(await setDoc(`couples/${f.c}/futureLetters/l1`, { fromUserId: f.A, toUserId: f.B, opensAt: new Date() }, 'owner'), 'letter')
  ok(await setDoc(`couples/${f.c}/futureLetterBodies/l1`, { fromUserId: f.A, text: 'hello' }, 'owner'), 'letter body')

  ok(await deleteDoc(`couples/${f.c}`, 'owner'), 'delete the couple')
  const left = async () => {
    const counts = await Promise.all(['timeTreeMeta', 'memories', 'futureLetters', 'futureLetterBodies']
      .map(async (sub) => ((await listDocs(`couples/${f.c}/${sub}`, 'owner')).body?.documents || []).length))
    return counts.every((n) => n === 0)
  }
  await waitFor('the subtree to be deleted', left, 2 * POLL_MS)
})

// MARK: - The remote switch
//
// Last in the file: appConfig/garden is global, so no other test's trigger may
// run while the garden is switched off.

etest('switched off: appConfig/garden {enabled: false} pushes nothing and claims nothing', async () => {
  const f = await couple()
  ok(await setDoc('appConfig/garden', { enabled: false }, 'owner'), 'switch the garden off')
  let off
  try {
    off = await water(f, f.A)
    ok(await setDoc(f.meta(`seed_${f.A}_1`), proposalDoc({ by: f.A, at: new Date(), title: 'Where we first met' }),
      'owner'), 'a seed')
    ok(await setDoc(f.meta('tree_p1'), {
      docType: 'tree', slot: 'p1', key: `key-${alnum(12)}`, title: 'Where we first met', preset: 'firstMet',
      scene: 'meadow', species: 'cherry', origin: 'together', plantedAt: new Date(), plantedBy: [f.B, f.A],
      agreementKind: 'plant', agreementBy: [f.B, f.A], agreementAt: new Date(), fromProposal: `seed_${f.B}_1`,
      updatedAt: new Date(),
    }, 'owner'), 'an agreement')
    await sleep(POLL_MS / 2)
    assert.deepEqual(await dryRuns(f), [], 'a garden push while switched off')
    assert.equal(await claimExists(`w_${f.c}_${off.id}`), false, 'the watering was claimed')
  } finally {
    ok(await deleteDoc('appConfig/garden', 'owner'), 'switch it back on')
  }
  // Back on, the next watering pushes again; the one made while off never does.
  const back = await water(f, f.A, { at: new Date(Date.now() + 1000) })
  await expectPush(f, 'the watering once switched back on', forWatering(back.id))
  assert.equal((await dryRuns(f)).filter(forWatering(off.id)).length, 0, 'the watering made while off was pushed')
})
