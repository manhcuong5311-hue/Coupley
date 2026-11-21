// Rules tests for the shared garden (firestore.rules, "Time Tree metadata"
// block, and the top-level appConfig probe).
//
//   firebase emulators:exec --only firestore --project demo-coupley-rules \
//     "node --test firestore-tests/"
//
// Writes mirror what the clients send. A 1.1/1.2 start-date edit is
// setData(payload, merge: true) on `config`; every garden write is a plain
// set, an updateData mask, or a delete, and every garden transaction is
// tested as ONE commit (the rules judge a transaction's commit like a batch).
// Every server time is a top-level SERVER_TIME transform (request.time).
//
// Test numbers follow docs/garden/SPEC.md F3.

import { test, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { forDatabase, SERVER_TIME, value } from './emulator.mjs'

// node --test runs the test files in parallel and each one resets its database
// before every test, so this file keeps to a database of its own.
const { reset, commit, setDoc, getDoc, listDocs, W } = forDatabase('garden-rules')

const A = 'alice' // proposes in most tests
const B = 'bob' // her partner, who answers
const M = 'mallory' // not in the couple
const C = 'couples/c1'
const META = `${C}/timeTreeMeta`
const D = (id) => `${META}/${id}`

const HOUR = 3600e3
const DAY = 24 * HOUR
const at = (ms) => new Date(Date.now() + ms)
const shift = (date, ms) => new Date(date.getTime() + ms)
/** A calendar day as JourneyCalendarDay.storedMoment writes it: 10:00 UTC. */
const day10 = (y, m, d) => new Date(Date.UTC(y, m - 1, d, 10))

const SEED = `seed_${A}_1`
const wid = (c) => 'water_' + c.repeat(20)
const W1 = wid('w')
const W2 = wid('x')
const W3 = wid('y')
const START = day10(2024, 1, 26)
const NEW_START = day10(2024, 2, 14)
const OUR_KEY = 'k-our-00001'
const SEED_KEY = 'k-seed-0001'

const ok = (r, why = '') =>
  assert.ok(r.ok, `expected ALLOW ${why}: ${r.status} ${JSON.stringify(r.body)}`)
// A denial must be the rules saying no (403), not a malformed request (400)
// or a missing document (404) that would make the test pass for nothing.
const no = (r, why = '') =>
  assert.equal(r.status, 403, `expected DENY (403) ${why}, got ${r.status} ${JSON.stringify(r.body)}`)

/** `obj` without `keys` (an optional field left out, as the client does). */
const without = (obj, ...keys) => Object.fromEntries(Object.entries(obj).filter(([k]) => !keys.includes(k)))

/** A REST array field as a list of strings. */
const strings = (doc, name) => doc?.fields?.[name]?.arrayValue?.values?.map((v) => v.stringValue)

const place = {
  name: 'Café Giảng', locality: 'Hoàn Kiếm, Hà Nội', lat: 21.0345, lng: 105.8543,
  precision: 'exact', poi: 'MKPOICategoryCafe', tz: 'Asia/Ho_Chi_Minh',
}
const content = {
  title: 'Where we first met', preset: 'firstMet', momentDay: day10(2023, 3, 12),
  place, scene: 'cityLights', species: 'cherry',
}
const ourContent = { title: 'Our tree', preset: 'ourTree', scene: 'meadow', species: 'oak' }

// ---------- proposals ----------

/** T0: a place seed (`by` is the field; the writer is the commit's auth). */
const seed = (o = {}, id = SEED, by = A) =>
  W.set(D(id), {
    docType: 'proposal', kind: 'plant', slot: 'new', key: SEED_KEY, by,
    at: SERVER_TIME, rev: 1, note: 'Remember?', ...content, ...o,
  })

/** T1: the proposal to plant Our tree with a start day. */
const seedOurData = (o = {}) => ({
  docType: 'proposal', kind: 'plant', slot: 'our', key: OUR_KEY, by: A,
  at: SERVER_TIME, rev: 1, startDay: START, ...ourContent, ...o,
})
const seedOur = (o = {}) => W.set(D('seed_our'), seedOurData(o))

/** T8: a proposed new name / place / moment / look for a planted tree. */
const change = (slot, body, o = {}, by = A) =>
  W.set(D(`change_${slot}`), {
    docType: 'proposal', kind: 'change', slot, key: slot === 'our' ? OUR_KEY : SEED_KEY, by,
    at: SERVER_TIME, rev: 1, ...body, ...o,
  })

/** T9: a request to let a place tree go. */
const rest = (slot = 'p1', o = {}, by = A) =>
  W.set(D(`rest_${slot}`), {
    docType: 'proposal', kind: 'rest', slot, key: SEED_KEY, by, at: SERVER_TIME, rev: 1, ...o,
  })

/** T2: a new start date, against the start date as the proposer saw it. */
const startdate = (o = {}, by = A) =>
  W.set(D('startdate'), {
    docType: 'proposal', kind: 'startDate', slot: 'our', key: OUR_KEY, by,
    at: SERVER_TIME, rev: 1, startDay: NEW_START, fromStartDay: START, ...o,
  })

// ---------- carrying out ----------

/** A place tree planted from the seed `id` by `by`, as T7 writes it. */
const plantedTree = (slot = 'p1', o = {}, by = B, proposer = A, id = SEED) => ({
  docType: 'tree', slot, key: SEED_KEY, ...content, origin: 'together',
  plantedAt: SERVER_TIME, plantedBy: [proposer, by], agreementKind: 'plant',
  agreementBy: [proposer, by], agreementAt: SERVER_TIME, fromProposal: id, updatedAt: SERVER_TIME, ...o,
})
/** T7: the tree and the seed's delete, one commit. */
const plant = (slot = 'p1', o = {}, by = B, proposer = A, id = SEED) => [
  W.set(D(`tree_${slot}`), plantedTree(slot, o, by, proposer, id)),
  W.del(D(id)),
]

/** T6: the start date (1.2 format), Our tree and the seed's delete, one commit. */
const plantOur = ({ by = B, proposer = A, configDay = START, tree = {} } = {}) => [
  W.set(D('config'), { startDate: configDay, setBy: proposer, setAt: SERVER_TIME, updatedAt: SERVER_TIME }),
  W.set(D('tree_our'), {
    docType: 'tree', slot: 'our', key: OUR_KEY, ...ourContent, origin: 'together',
    plantedAt: SERVER_TIME, plantedBy: [proposer, by], agreedStartDay: START, agreementKind: 'plant',
    agreementBy: [proposer, by], agreementAt: SERVER_TIME, fromProposal: 'seed_our',
    updatedAt: SERVER_TIME, ...tree,
  }),
  W.del(D('seed_our')),
]

/** T13: Our tree recorded from an existing start date. */
const record = (by = B, o = {}) =>
  W.set(D('tree_our'), {
    docType: 'tree', slot: 'our', key: OUR_KEY, ...ourContent, origin: 'legacy',
    agreedStartDay: START, agreementKind: 'recorded', agreementBy: [by],
    agreementAt: SERVER_TIME, updatedAt: SERVER_TIME, ...o,
  })

/**
 * T10: the tree takes the proposal's content (absent optional fields are
 * deleted with FieldValue.delete(), which is a masked field with no value).
 */
const agreeChange = (slot, body, { by = B, proposer = A, o = {} } = {}) => {
  const data = {
    ...body, fromProposal: `change_${slot}`, agreementKind: 'change',
    agreementBy: [proposer, by], agreementAt: SERVER_TIME, updatedAt: SERVER_TIME, ...o,
  }
  const absent = ['place', 'momentDay'].filter((k) => !(k in data))
  return [W.merge(D(`tree_${slot}`), data, absent), W.del(D(`change_${slot}`))]
}

/** T11: config and Our tree move together; the suggestion goes. */
const agreeStart = ({ by = B, proposer = A, configDay = NEW_START, treeDay = NEW_START } = {}) => [
  W.update(D('config'), { startDate: configDay, updatedAt: SERVER_TIME }),
  W.update(D('tree_our'), {
    agreedStartDay: treeDay, fromProposal: 'startdate', agreementKind: 'startDate',
    agreementBy: [proposer, by], agreementAt: SERVER_TIME, updatedAt: SERVER_TIME,
  }),
  W.del(D('startdate')),
]

// ---------- waterings ----------

/** The watering batch: the watering and the waterer's own turn. */
const water = (id = W1, by = A, o = {}) => [
  W.set(D(id), { docType: 'water', by, wateredAt: SERVER_TIME, effect: 'can', ...o }),
  W.set(D(`waterer_${by}`), { docType: 'waterer', lastWateredAt: SERVER_TIME, lastWateringId: id }),
]

// ---------- seeding (owner: no rules) ----------

const couple = (status = 'active') => setDoc(C, { userIds: [A, B], status }, 'owner')
const anchor = (startDate = START) =>
  setDoc(D('config'), { startDate, setBy: A, setAt: at(-DAY), updatedAt: at(-DAY) }, 'owner')
const ourTree = (o = {}) =>
  setDoc(D('tree_our'), {
    docType: 'tree', slot: 'our', key: OUR_KEY, ...ourContent, origin: 'legacy',
    agreedStartDay: START, agreementKind: 'recorded', agreementBy: [A],
    agreementAt: at(-DAY), updatedAt: at(-DAY), ...o,
  }, 'owner')
/** tree_p1 as B planted it from A's seed yesterday. */
const treeP1 = (o = {}) =>
  setDoc(D('tree_p1'), plantedTree('p1', {
    plantedAt: at(-DAY), agreementAt: at(-DAY), updatedAt: at(-DAY), ...o,
  }), 'owner')
const asOwner = (write) => commit([write], 'owner')
const ownerDelete = (id) => commit([W.del(D(id))], 'owner')
const turnAt = (by, when, id) =>
  setDoc(D(`waterer_${by}`), { docType: 'waterer', lastWateredAt: when, lastWateringId: id }, 'owner')

async function stored(id) {
  const r = await getDoc(D(id), A)
  ok(r, `read ${id}`)
  return r.body
}

beforeEach(async () => {
  await reset()
  ok(await couple(), 'seed couple')
})

// ====================================================================
// config: 1.2 parity
// ====================================================================

test('1. config: a member creates it with the 1.2 payload', async () => {
  ok(await setDoc(D('config'), {
    startDate: new Date(Date.UTC(2024, 0, 26, 17, 23, 45, 123)), // a raw instant, as 1.1/1.2 store it
    setBy: A, setByName: 'Alice', setAt: new Date(), updatedAt: new Date(),
  }, A))
})

test('2. config: a member merges an edit (deleting setByName); a member deletes it', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([W.merge(D('config'), {
    startDate: new Date(Date.UTC(2024, 1, 2, 8, 0, 0, 456)), setBy: A, setAt: at(-DAY), updatedAt: new Date(),
  }, ['setByName'])], B), 'B edits A\'s start date like 1.2')
  ok(await commit([W.del(D('config'))], A), 'A deletes')
})

test('3. config: outsiders and signed-out users cannot write it', async () => {
  const data = { startDate: START, setBy: M, setAt: new Date(), updatedAt: new Date() }
  no(await setDoc(D('config'), data, M), 'mallory')
  no(await setDoc(D('config'), data, null), 'signed out')
  ok(await anchor(), 'seed config')
  no(await commit([W.del(D('config'))], M), 'mallory deletes')
})

test('4. config: a 1.2 direct edit lands while a start-date suggestion waits', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  ok(await commit([startdate()], A), 'A suggests a new start date')
  ok(await commit([W.merge(D('config'), {
    startDate: new Date(Date.UTC(2024, 2, 1, 15, 30)), setBy: B, setAt: new Date(), updatedAt: new Date(),
  }, ['setByName'])], B), 'B edits on 1.2')
})

// ====================================================================
// probe
// ====================================================================

test('5. probe: appConfig/garden is readable when signed in, never writable', async () => {
  assert.equal((await getDoc('appConfig/garden', A)).status, 404, 'missing: not found, not denied')
  ok(await setDoc('appConfig/garden', { enabled: false }, 'owner'), 'admin writes it')
  ok(await getDoc('appConfig/garden', B), 'present')
  no(await getDoc('appConfig/garden', null), 'signed out')
  no(await setDoc('appConfig/garden', { enabled: true }, A), 'a member sets it')
  no(await setDoc('appConfig/other', { enabled: true }, A), 'a member creates another switch')
  no(await commit([W.del('appConfig/garden')], A), 'a member deletes it')
})

test('6. probe: appConfig cannot be listed', async () => {
  ok(await setDoc('appConfig/garden', { enabled: true }, 'owner'), 'admin writes it')
  no(await listDocs('appConfig', A))
})

// ====================================================================
// unknown ids
// ====================================================================

test('7. unknown ids: well-formed writes under any other id are denied', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  ok(await asOwner(seed()), 'seed A\'s seed')
  const cases = [
    ['notes', [seed({}, 'notes')], A],
    ['tree_p8', plant('p8'), B],
    // Below every place slot: only the id pattern refuses it (no lower slot to fill).
    ['tree_p0', plant('p0'), B],
    ['tree_new', plant('new'), B],
    ['water_short', water('water_short'), A],
    ['seed_x', [seed({}, 'seed_x')], A],
    ['seed_ + 20 alphanumerics (the old pattern)', [seed({}, 'seed_' + 'a1'.repeat(10))], A],
    ['change_p8', [change('p8', content)], A],
    ['rest_our', [rest('our', { key: OUR_KEY })], A],
    // A's own valid watering, plus a turn under bob's id pointing at it.
    ['waterer_bob (by A)', [...water(W1, A), W.set(D(`waterer_${B}`), {
      docType: 'waterer', lastWateredAt: SERVER_TIME, lastWateringId: W1,
    })], A],
  ]
  for (const [why, writes, auth] of cases) no(await commit(writes, auth), why)
})

// ====================================================================
// seeds
// ====================================================================

test('8. seeds: A sends a place seed once a start date exists', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A))
  const doc = await stored(SEED)
  assert.equal(value(doc, 'by'), A)
  assert.equal(value(doc, 'rev'), 1)
})

test('9. seeds: a place seed without a start date is denied', async () => {
  no(await commit([seed()], A))
})

test('10. seeds: every malformed or foreign seed is denied', async () => {
  ok(await anchor(), 'seed config')
  const cases = [
    ['by: B under A', [seed({ by: B })], A],
    ['client at', [seed({ at: new Date() })], A],
    ['rev: 2 on create', [seed({ rev: 2 })], A],
    ['extra key plantedAt', [seed({ plantedAt: new Date() })], A],
    ['title of 161 chars', [seed({ title: 't'.repeat(161) })], A],
    ['empty title', [seed({ title: '' })], A],
    ['note of 561 chars', [seed({ note: 'n'.repeat(561) })], A],
    ['scene "sea side"', [seed({ scene: 'sea side' })], A],
    ['preset ourTree', [seed({ preset: 'ourTree' })], A],
    ['slot p1', [seed({ slot: 'p1' })], A],
    ['momentDay in 3 days', [seed({ momentDay: at(3 * DAY) })], A],
    ['outsider', [seed({}, `seed_${M}_1`, M)], M],
    ['signed out', [seed()], null],
  ]
  for (const [why, writes, auth] of cases) no(await commit(writes, auth), why)

  ok(await commit([seed({ title: 't'.repeat(160), note: 'n'.repeat(560) })], A), 'at the limits')

  ok(await couple('disconnected'), 'disconnect')
  no(await commit([seed({}, `seed_${A}_2`)], A), 'disconnected couple')
})

test('11. seeds: places are validated and rounded by the rules', async () => {
  ok(await anchor(), 'seed config')
  const { precision, ...noPrecision } = place
  assert.equal(precision, 'exact')
  const cases = [
    ['lat 91', { ...place, lat: 91 }],
    ['lng "east"', { ...place, lng: 'east' }],
    ['no precision', noPrecision],
    ['extra accuracy', { ...place, accuracy: 5 }],
    ['area with 4 decimals', { ...place, precision: 'area', lat: 21.0345, lng: 105.85 }],
    ['exact with 5 decimals', { ...place, lat: 21.03451 }],
    ['no name', without(place, 'name')],
  ]
  for (const [why, p] of cases) no(await commit([seed({ place: p })], A), why)

  ok(await commit([seed({ place: { ...place, precision: 'area', lat: 21.03, lng: 105.85 } })], A), 'area, 2 dp')
  ok(await commit([seed({ place: { ...place, lat: -33.8688, lng: 151.2093 } }, `seed_${A}_2`)], A), 'exact, 4 dp')
  ok(await commit([seed({ place: { name: 'Hồ Gươm', lat: 21.03, lng: 105.85, precision: 'area' } }, `seed_${A}_3`)], A),
    'only the required keys')
})

test('12. seeds: the proposer edits her seed with rev + 1, same kind, slot and key', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  no(await commit([seed({ rev: 2, key: 'k-other-0001' })], A), 'key changed')
  no(await commit([seed({ rev: 2, slot: 'p1' })], A), 'slot changed')
  no(await commit([seed({ rev: 2, kind: 'change' })], A), 'kind changed')
  no(await commit([seed({ rev: 3 })], A), 'rev skips one')
  no(await commit([seed({ rev: 1 })], A), 'rev unchanged')
  ok(await commit([seed({ rev: 2, note: 'Remember the rain?' })], A), 'edit')
  assert.equal(value(await stored(SEED), 'rev'), 2)
})

test('13. seeds: the partner counters and becomes the proposer', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  no(await commit([seed({ rev: 2, title: 'Where it all began' })], B), 'B writes it keeping by: A')
  ok(await commit([seed({ rev: 2, title: 'Where it all began' }, SEED, B)], B), 'B counters')
  assert.equal(value(await stored(SEED), 'by'), B)
})

test('14. seeds: seed_our only while there is no start date', async () => {
  ok(await commit([seedOur()], A), 'seed_our without config')
  ok(await ownerDelete('seed_our'), 'clear it')
  ok(await anchor(), 'seed config')
  no(await commit([seedOur()], A), 'seed_our with config')
  no(await commit([W.set(D(SEED), seedOurData())], A), 'an Our-tree seed under seed_alice_1')
  no(await commit([seed({ slot: 'our' })], A), 'seed_alice_1 with slot: our')
})

test('15. seeds: either member deletes a seed, an outsider cannot', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  ok(await commit([W.del(D(SEED))], A), 'A takes it back')
  ok(await commit([seed()], A), 'A sends again')
  ok(await commit([W.del(D(SEED))], B), 'B lets it go')
  ok(await commit([seed()], A), 'A sends again')
  no(await commit([W.del(D(SEED))], M), 'mallory')
  no(await commit([W.del(D(SEED))], null), 'signed out')
})

// ====================================================================
// planting
// ====================================================================

test('16. planting: B plants A\'s seed', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  ok(await commit(plant(), B), 'B plants')
  const doc = await stored('tree_p1')
  assert.deepEqual(strings(doc, 'plantedBy'), [A, B])
  assert.deepEqual(strings(doc, 'agreementBy'), [A, B])
  assert.equal(value(doc, 'origin'), 'together')
  assert.equal((await getDoc(D(SEED), A)).status, 404, 'the seed is gone')
})

test('17. planting: the proposer cannot plant her own seed', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  no(await commit(plant('p1', {}, A, A), A))
})

test('18. planting: the tree must be exactly the seed (moments within a second)', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  const cases = [
    ['title', { title: 'Somewhere else' }],
    ['place', { place: { ...place, name: 'Café Đinh' } }],
    ['momentDay a day off', { momentDay: shift(content.momentDay, DAY) }],
    ['momentDay 2 s off', { momentDay: shift(content.momentDay, 2000) }],
    ['scene', { scene: 'seaside' }],
    ['species', { species: 'oak' }],
  ]
  for (const [why, o] of cases) no(await commit(plant('p1', o), B), why)
  ok(await commit(plant('p1', { momentDay: shift(content.momentDay, 1) }), B), 'momentDay 1 ms off')
})

test('19. planting: the seed must be deleted in the same commit', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  no(await commit([plant()[0]], B))
})

test('20. planting: times are the server\'s and the names are in order', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  const cases = [
    ['client plantedAt', { plantedAt: new Date() }],
    ['client agreementAt', { agreementAt: new Date() }],
    ['plantedBy [B, A]', { plantedBy: [B, A] }],
    ['agreementBy [B]', { agreementBy: [B] }],
    ['with lookBy', { lookBy: B, lookAt: SERVER_TIME }],
    ['origin legacy', { origin: 'legacy' }],
  ]
  for (const [why, o] of cases) no(await commit(plant('p1', o), B), why)
  ok(await commit(plant(), B), 'as the client writes it')
})

test('21. planting: the slot is the id, and the seed must exist', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  no(await commit([W.set(D('tree_p2'), plantedTree('p1')), W.del(D(SEED))], B), 'tree_p2 with slot p1')
  no(await commit(plant('p1', {}, B, A, `seed_${A}_3`), B), 'fromProposal names a missing seed')
})

test('22. planting: Our tree\'s first planting writes the start date in the same commit', async () => {
  ok(await commit([seedOur()], A), 'A sends seed_our')
  no(await commit(plantOur({ configDay: shift(START, DAY) }), B), 'config.startDate a day off')
  no(await commit(plantOur().slice(1), B), 'without the config write')
  no(await commit(plantOur({ by: A, proposer: A }), A), 'by the proposer')
  ok(await commit(plantOur(), B), 'B plants Our tree')
  const config = await stored('config')
  assert.equal(value(config, 'startDate').getTime(), START.getTime())
  assert.equal(value(config, 'setBy'), A)
  assert.deepEqual(strings(await stored('tree_our'), 'plantedBy'), [A, B])

  ok(await ownerDelete('tree_our'), 'remove the tree again')
  ok(await asOwner(seedOur({ at: at(-HOUR) })), 'and put a seed_our back, config still present')
  no(await commit(plantOur(), B), 'with config already present')
})

// ====================================================================
// recording Our tree
// ====================================================================

test('23. recording: either partner records Our tree from the existing start date', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([record(B)], B), 'B records')
  assert.equal(value(await stored('tree_our'), 'origin'), 'legacy')
  ok(await ownerDelete('tree_our'), 'clear it')
  ok(await commit([record(B, { agreedStartDay: shift(START, 1) })], B), 'agreedStartDay 1 ms off')
})

test('24. recording: only as it is, never with a place or a planting', async () => {
  ok(await anchor(), 'seed config')
  const cases = [
    ['with a place', { place }],
    ['with plantedAt', { plantedAt: SERVER_TIME }],
    ['preset firstMet', { preset: 'firstMet' }],
    ['agreedStartDay a day off', { agreedStartDay: shift(START, DAY) }],
    ['agreementBy [A, B]', { agreementBy: [A, B] }],
    ['client agreementAt', { agreementAt: new Date() }],
  ]
  for (const [why, o] of cases) no(await commit([record(B, o)], B), why)
  ok(await ownerDelete('config'), 'remove the start date')
  no(await commit([record(B)], B), 'without config')
})

test('25. recording: after a 1.2 edit moves config, Our tree is re-recorded to it', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  const moved = new Date(Date.UTC(2024, 2, 1, 15, 30, 0, 250))
  ok(await anchor(moved), 'a 1.2 client moves the start date')
  const rerecord = (day) => commit([W.update(D('tree_our'), {
    agreedStartDay: day, agreementKind: 'recorded', agreementBy: [A],
    agreementAt: SERVER_TIME, updatedAt: SERVER_TIME,
  })], A)
  no(await rerecord(shift(moved, DAY)), 'to any other value')
  ok(await rerecord(moved), 'to the new value')
})

// ====================================================================
// looks and changes
// ====================================================================

test('26. looks: either member changes scene and species, only those', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  const look = (by, o = {}) => commit([W.update(D('tree_p1'), {
    scene: 'seaside', species: 'palm', prevScene: 'cityLights', prevSpecies: 'cherry',
    lookBy: by, lookAt: SERVER_TIME, updatedAt: SERVER_TIME, ...o,
  })], by)
  no(await look(A, { title: 'By the sea' }), 'touching the title')
  no(await look(A, { lookAt: new Date() }), 'client lookAt')
  no(await look(A, { lookBy: B }), 'lookBy someone else')
  no(await look(A, { prevScene: 'city lights' }), 'prevScene not a token')
  no(await look(M), 'outsider')
  ok(await look(A), 'A changes the look')
  ok(await look(B, { scene: 'cityLights', species: 'cherry', prevScene: 'seaside', prevSpecies: 'palm' }),
    'B changes it back')
})

test('27. changes: A proposes, B carries it out exactly', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  const body = { ...content, title: 'Café Giảng, again', scene: 'meadow' }
  ok(await commit([change('p1', body)], A), 'A proposes')
  ok(await commit(agreeChange('p1', body), B), 'B agrees')
  const doc = await stored('tree_p1')
  assert.equal(value(doc, 'title'), 'Café Giảng, again')
  assert.equal(value(doc, 'agreementKind'), 'change')
  assert.deepEqual(strings(doc, 'plantedBy'), [A, B], 'planting kept')
  assert.equal((await getDoc(D('change_p1'), A)).status, 404, 'the proposal is gone')
})

test('28. changes: anything but the partner\'s exact change is denied', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  const body = { ...content, title: 'Café Giảng, again', scene: 'meadow' }
  ok(await commit([change('p1', body)], A), 'A proposes')
  no(await commit(agreeChange('p1', { ...body, title: 'Something else' }), B), 'different content')
  no(await commit(agreeChange('p1', body, { o: { plantedAt: new Date() } }), B), 'touching plantedAt')
  no(await commit(agreeChange('p1', body, { by: A, proposer: A }), A), 'by A herself')
  no(await commit([agreeChange('p1', body)[0]], B), 'without deleting the proposal')
  ok(await asOwner(change('p1', body, { key: 'k-other-0001', at: at(-HOUR) })), 'a proposal for another key')
  no(await commit(agreeChange('p1', body), B), 'key mismatch')
})

test('29. changes: change_our never carries a moment, may carry a place', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  no(await commit([change('our', { ...ourContent, momentDay: day10(2023, 3, 12) })], A), 'with a momentDay')
  const body = { ...ourContent, place }
  ok(await commit([change('our', body)], A), 'with a place')
  ok(await commit(agreeChange('our', body), B), 'carried out')
  assert.equal(value(await stored('tree_our'), 'place')?.mapValue?.fields?.name?.stringValue, place.name)
})

test('30. changes: a change can remove the place', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  const body = without(content, 'place')
  ok(await commit([change('p1', body)], A), 'A proposes without a place')
  no(await commit(agreeChange('p1', { ...body, place }), B), 'keeping the place')
  ok(await commit(agreeChange('p1', body), B), 'carried out with the field deleted')
  assert.equal(value(await stored('tree_p1'), 'place'), undefined)
})

// ====================================================================
// start date
// ====================================================================

test('31. start date: a suggestion names the start date as it is', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  ok(await commit([startdate()], A), 'fromStartDay = config')
  ok(await commit([W.del(D('startdate'))], A), 'taken back')
  ok(await commit([startdate({ fromStartDay: shift(START, 1) })], A), 'fromStartDay 1 ms off')
  ok(await commit([W.del(D('startdate'))], A), 'taken back')
  no(await commit([startdate({ fromStartDay: shift(START, DAY) })], A), 'fromStartDay a day off')
  no(await commit([startdate({ startDay: 'tomorrow' })], A), 'startDay not a timestamp')
  no(await commit([startdate({ title: 'Our tree' })], A), 'with tree content')
  ok(await ownerDelete('tree_our'), 'remove Our tree')
  no(await commit([startdate()], A), 'without tree_our')
})

test('32. start date: B agrees, moving config and Our tree together', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  ok(await commit([startdate()], A), 'A suggests')
  no(await commit(agreeStart({ configDay: shift(NEW_START, DAY) }), B), 'config written with another day')
  no(await commit(agreeStart({ treeDay: shift(NEW_START, DAY) }), B), 'tree written with another day')
  no(await commit(agreeStart({ by: A, proposer: A }), A), 'by A herself')
  ok(await commit(agreeStart(), B), 'B agrees')
  assert.equal(value(await stored('config'), 'startDate').getTime(), NEW_START.getTime())
  assert.equal(value(await stored('tree_our'), 'agreementKind'), 'startDate')
  assert.equal(value(await stored('config'), 'setBy'), A, 'setBy kept, as a 1.2 edit keeps it')
})

test('33. start date: a suggestion is void once a 1.2 client moves config', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  ok(await commit([startdate()], A), 'A suggests')
  ok(await anchor(day10(2024, 3, 1)), 'a 1.2 client moves the start date')
  no(await commit(agreeStart(), B))
})

test('34. start date: the agreement must write config', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  ok(await commit([startdate()], A), 'A suggests')
  no(await commit(agreeStart().slice(1), B))
})

// ====================================================================
// rest
// ====================================================================

test('35. rest: A asks, B lets the tree go with the request', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  ok(await commit([rest('p1')], A), 'A asks')
  ok(await commit([W.del(D('tree_p1')), W.del(D('rest_p1'))], B), 'B lets it go')
  assert.equal((await getDoc(D('tree_p1'), A)).status, 404, 'the tree is gone')
})

test('36. rest: no other way to remove a tree', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  ok(await treeP1(), 'seed tree_p1')
  no(await commit([W.del(D('tree_p1'))], B), 'B without a request')
  no(await commit([rest('our', { key: OUR_KEY })], A), 'rest_our')
  no(await commit([W.del(D('tree_our'))], B), 'tree_our while active')
  ok(await commit([rest('p1')], A), 'A asks')
  no(await commit([W.del(D('tree_p1')), W.del(D('rest_p1'))], A), 'A, the asker')
  no(await commit([W.del(D('tree_p1'))], B), 'B keeping the request')
})

test('37. rest: the request must name the tree\'s key', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  no(await commit([rest('p1', { key: 'k-other-0001' })], A))
  no(await commit([rest('p1', { title: 'Where we first met' })], A), 'with tree content')
})

// ====================================================================
// watering
// ====================================================================

test('38. watering: A waters (the watering and her turn, one batch)', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit(water(W1, A, { note: 'Missed you today' }), A))
  const turn = await stored(`waterer_${A}`)
  assert.equal(value(turn, 'lastWateringId'), W1)
  assert.equal(value(turn, 'lastWateredAt').getTime(), value(await stored(W1), 'wateredAt').getTime())
})

test('39. watering: the watering and the turn only travel together', async () => {
  ok(await anchor(), 'seed config')
  no(await commit([water()[0]], A), 'the watering alone')
  no(await commit([water()[1]], A), 'the turn alone')
})

test('40. watering: once per person per 12 hours (11 h 50 min by the server)', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit(water(W1), A), 'A waters')
  no(await commit(water(W2), A), 'A again at once')
  ok(await turnAt(A, at(-12 * HOUR), W1), 'her last turn 12 hours ago')
  ok(await commit(water(W2), A), 'after 12 hours')
  ok(await turnAt(A, at(-11 * HOUR), W2), 'her last turn 11 hours ago')
  no(await commit(water(W3), A), 'after 11 hours')
})

test('41. watering: each partner has a turn of their own', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit(water(W1, A), A), 'A waters')
  ok(await commit(water(W2, B), B), 'B right after')

  await reset()
  ok(await couple(), 'seed couple')
  ok(await anchor(), 'seed config')
  const [a, b] = await Promise.all([commit(water(W1, A), A), commit(water(W2, B), B)])
  ok(a, 'A, the same second')
  ok(b, 'B, the same second')
})

test('42. watering: needs a start date', async () => {
  no(await commit(water(), A))
})

test('43. watering: every malformed or foreign watering is denied', async () => {
  ok(await anchor(), 'seed config')
  const cases = [
    ['by: B under A', water(W1, A, { by: B }), A],
    ['client wateredAt', water(W1, A, { wateredAt: new Date() }), A],
    ['client lastWateredAt', [water()[0], W.set(D(`waterer_${A}`), {
      docType: 'waterer', lastWateredAt: new Date(), lastWateringId: W1,
    })], A],
    ['note of 401 chars', water(W1, A, { note: 'n'.repeat(401) }), A],
    ['empty note', water(W1, A, { note: '' }), A],
    ['extra key together', water(W1, A, { together: true }), A],
    ['effect "rain cloud"', water(W1, A, { effect: 'rain cloud' }), A],
    ['outsider', water(W1, M), M],
    ['signed out', water(), null],
  ]
  for (const [why, writes, auth] of cases) no(await commit(writes, auth), why)

  ok(await commit(water(W2, B, { note: 'n'.repeat(400), effect: 'moonlitDrizzle' }), B), 'at the limit')

  ok(await couple('disconnected'), 'disconnect')
  no(await commit(water(W1, A), A), 'disconnected couple')
})

test('44. watering: a watering never changes and stays while active', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit(water(W1, A), A), 'A waters')
  no(await commit([W.update(D(W1), { note: 'edited' })], A), 'A edits it')
  no(await commit([W.update(D(W1), { effect: 'together' })], B), 'B edits it')
  no(await commit([W.del(D(W1))], A), 'A deletes it')
  no(await commit([W.del(D(W1))], B), 'B deletes it')
})

// ====================================================================
// purge and reads
// ====================================================================

test('45. purge: a disconnected couple deletes waterings and turns', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit(water(W1, A), A), 'A waters')
  ok(await couple('disconnected'), 'disconnect')
  ok(await commit([W.del(D(`waterer_${A}`))], B), 'the turn')
  ok(await commit([W.del(D(W1))], B), 'the watering')
})

test('46. purge: one batch deletes the whole garden (one couple read)', async () => {
  const ids = ['config', 'tree_our', 'tree_p1', 'tree_p2', 'tree_p3', 'tree_p4', 'tree_p5', 'tree_p6', 'tree_p7',
    `seed_${A}_1`, 'change_p1', 'rest_p2', 'startdate', `waterer_${A}`, `waterer_${B}`]
  for (let i = 0; i < 20; i++) ids.push('water_' + String(i).padStart(20, '0'))
  ok(await commit(ids.map((id) => W.set(D(id), { docType: 'seeded', n: id })), 'owner'), 'seed 35 documents')
  ok(await couple('disconnected'), 'disconnect')
  ok(await commit(ids.map((id) => W.del(D(id))), B), '35 deletes in one batch')
  const list = await listDocs(META, A)
  ok(list, 'list after the purge')
  assert.equal(list.body?.documents?.length ?? 0, 0, 'nothing left')
})

test('47. purge: an active couple cannot delete garden history', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit(water(W1, A), A), 'A waters')
  ok(await treeP1(), 'seed tree_p1')
  for (const auth of [A, B]) {
    no(await commit([W.del(D(W1))], auth), `a watering (${auth})`)
    no(await commit([W.del(D(`waterer_${A}`))], auth), `a waterer (${auth})`)
    no(await commit([W.del(D('tree_p1'))], auth), `a planted tree (${auth})`)
  }
})

test('48. reads: members get and list timeTreeMeta, nobody else', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit(water(W1, A), A), 'A waters')
  for (const auth of [A, B]) {
    ok(await getDoc(D('config'), auth), `${auth} gets config`)
    ok(await getDoc(D(W1), auth), `${auth} gets a watering`)
    ok(await listDocs(META, auth), `${auth} lists`)
  }
  for (const auth of [M, null]) {
    no(await getDoc(D('config'), auth), `${auth} gets config`)
    no(await listDocs(META, auth), `${auth} lists`)
  }
})

// ====================================================================
// seed bounds
// ====================================================================

test('49. seed bounds: three open place seeds per member, only under her own ids', async () => {
  ok(await anchor(), 'seed config')
  for (const n of [1, 2, 3]) {
    ok(await commit([seed({ key: `k-seed-000${n}` }, `seed_${A}_${n}`)], A), `seed_${A}_${n}`)
  }
  for (const id of [`seed_${A}_4`, `seed_${A}_0`, `seed_${A}_x`, `seed_${B}_1`]) {
    no(await commit([seed({ key: 'k-seed-0009' }, id)], A), `${id} written by A`)
  }
})

test('50. seed bounds: a counter keeps the creator\'s id; the creator then plants it', async () => {
  ok(await anchor(), 'seed config')
  const id = `seed_${A}_2`
  ok(await commit([seed({}, id)], A), 'A sends')
  ok(await commit([seed({ rev: 2, scene: 'meadow' }, id, B)], B), 'B counters under A\'s id')
  ok(await commit(plant('p1', { scene: 'meadow' }, A, B, id), A), 'A plants B\'s version')
  assert.deepEqual(strings(await stored('tree_p1'), 'plantedBy'), [B, A])
})

// ====================================================================
// the couple document under the garden
// ====================================================================
//
// "Active" and "the partner" are read from couples/c1, so the garden is only
// as safe as that document: its status never goes back from 'disconnected'
// and its userIds never change (firestore-tests/couples.rules.test.mjs has
// the couple's own cases).

test('51. couple: a member cannot disconnect, purge and resume the garden', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  ok(await commit(water(W1, B, { note: 'Miss you' }), B), 'B waters')
  ok(await commit(water(W2, A), A), 'A waters')
  ok(await commit([W.merge(C, { status: 'disconnected' })], A), 'A marks the couple disconnected')
  ok(await commit([W.del(D('tree_p1')), W.del(D(W1)), W.del(D(`waterer_${A}`))], A),
    'A deletes a tree, B\'s watering and her own turn, as a disconnected couple may')
  for (const auth of [A, B]) no(await commit([W.merge(C, { status: 'active' })], auth), `${auth} makes it active again`)
  no(await commit(water(W3, A), A), 'so A never waters again with a fresh turn')
  no(await commit([seed({}, `seed_${A}_2`)], A), 'nor sends a seed')
})

test('52. couple: no third member is ever added to propose or answer', async () => {
  ok(await anchor(), 'seed config')
  ok(await ourTree(), 'seed Our tree')
  for (const auth of [A, B]) no(await commit([W.merge(C, { userIds: [A, B, M] })], auth), `${auth} adds mallory`)
  no(await commit([startdate({}, M)], M), 'mallory suggests a start date')
  no(await commit([seed({}, `seed_${M}_1`, M)], M), 'mallory sends a seed')
  ok(await commit([seed()], A), 'A sends a seed')
  no(await commit(plant('p1', {}, M), M), 'mallory plants it')
  ok(await commit([startdate()], A), 'A suggests a start date')
  no(await commit(agreeStart({ by: M }), M), 'mallory agrees to it')
  ok(await treeP1(), 'seed tree_p1')
  ok(await commit([rest('p1')], A), 'A asks to let tree_p1 go')
  no(await commit([W.del(D('tree_p1')), W.del(D('rest_p1'))], M), 'mallory lets it go')
})

// ====================================================================
// one seed, one slot
// ====================================================================

test('53. planting: one seed becomes one tree, never two slots in one commit', async () => {
  ok(await anchor(), 'seed config')
  ok(await commit([seed()], A), 'A sends')
  no(await commit([W.set(D('tree_p1'), plantedTree('p1')), W.set(D('tree_p2'), plantedTree('p2')), W.del(D(SEED))], B),
    'p1 and p2 from one seed')
  no(await commit([W.set(D('tree_p2'), plantedTree('p2')), W.set(D('tree_p1'), plantedTree('p1')), W.del(D(SEED))], B),
    'p2 and p1, the other way round')
  ok(await commit(plant('p1'), B), 'p1 alone')
  assert.equal((await getDoc(D('tree_p2'), A)).status, 404, 'no second tree')
})

test('54. planting: a place tree takes the lowest free slot, up to p7', async () => {
  ok(await anchor(), 'seed config')
  for (let n = 1; n <= 7; n++) {
    ok(await commit([seed()], A), `A sends seed ${n}`)
    if (n < 7) no(await commit(plant(`p${n + 1}`), B), `p${n + 1} while p${n} is free`)
    // p7 is the garden's costliest write: six trees below it, every optional
    // field, and B's own seed for the same place going too ("Plant Sam's").
    // It must stay inside a request's document-access and expression budgets.
    const duplicate = n === 7 ? [W.del(D(`seed_${B}_1`))] : []
    if (n === 7) ok(await commit([seed({}, `seed_${B}_1`, B)], B), 'B sends the same place')
    ok(await commit([...plant(`p${n}`), ...duplicate], B), `p${n} above ${n - 1} planted slots`)
  }
  const list = await listDocs(META, A)
  ok(list, 'list the garden')
  assert.equal(list.body.documents.filter((d) => /\/tree_p[1-7]$/.test(d.name)).length, 7)
  ok(await commit([seed()], A), 'A sends an eighth place seed')
  no(await commit(plant('p8'), B), 'a full garden has no eighth place slot')
})

test('55. planting: a slot left by a tree let go is the lowest free slot again', async () => {
  ok(await anchor(), 'seed config')
  ok(await treeP1(), 'seed tree_p1')
  ok(await asOwner(W.set(D('tree_p3'), plantedTree('p3', {
    plantedAt: at(-DAY), agreementAt: at(-DAY), updatedAt: at(-DAY),
  }))), 'seed tree_p3 (tree_p2 was let go)')
  ok(await commit([seed()], A), 'A sends')
  no(await commit(plant('p4'), B), 'p4 while p2 is free')
  ok(await commit(plant('p2'), B), 'p2')
})
