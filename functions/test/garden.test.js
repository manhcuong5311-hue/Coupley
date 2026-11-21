"use strict";

// Unit tests for functions/garden.js (the garden's pure push logic).
//
//   node --test functions/test/garden.test.js
//
// Node 20+ only: node:test, no new dependency. Timestamps are the Admin SDK's
// own class (already a dependency), so the tests exercise the same
// toMillis / toDate / isEqual the trigger sees.

const test = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp } = require("firebase-admin/firestore");
const garden = require("../garden");

const HOUR = 3600e3;
const MIN = 60e3;
const DAY = 24 * HOUR;
const T0 = Date.UTC(2026, 10, 14, 12);                   // 14 Nov 2026, 12:00 UTC
const ts = (ms) => Timestamp.fromMillis(ms);
const WATER_ID = "water_AbCdEfGhIjKlMnOpQrSt";

// MARK: - classify

const water = (o = {}) => ({ docType: "water", by: "alice", wateredAt: ts(T0), effect: "can", ...o });
const proposal = (o = {}) => ({ docType: "proposal", kind: "plant", slot: "new", key: "k-1", by: "alice",
                                at: ts(T0), rev: 1, title: "Our first trip", ...o });
const tree = (o = {}) => ({ docType: "tree", slot: "p2", key: "k-2", title: "Our first trip", scene: "meadow",
                            species: "oak", origin: "together", agreementKind: "plant",
                            agreementBy: ["alice", "bob"], agreementAt: ts(T0), ...o });

test("classify: a watering created is `watered`", () => {
  const ev = garden.classify(WATER_ID, null, water({ note: "Miss you" }));
  assert.equal(ev.kind, "watered");
  assert.equal(ev.wateringId, WATER_ID);
  assert.equal(ev.by, "alice");
  assert.equal(ev.at.toMillis(), T0);
  assert.equal(ev.note, "Miss you");
  assert.equal(garden.classify(WATER_ID, null, water()).note, null);
});

test("classify: a watering updated or deleted is silent", () => {
  assert.equal(garden.classify(WATER_ID, water(), water({ note: "x" })), null);
  assert.equal(garden.classify(WATER_ID, water(), null), null);
});

test("classify: a malformed watering is silent", () => {
  assert.equal(garden.classify(WATER_ID, null, water({ docType: "tree" })), null);
  assert.equal(garden.classify(WATER_ID, null, water({ by: "" })), null);
  assert.equal(garden.classify(WATER_ID, null, water({ wateredAt: null })), null);
  assert.equal(garden.classify("water_short", null, water()), null);
});

test("classify: every proposal id, created, is `proposal`", () => {
  const cases = [
    ["seed_alice_1", proposal()],
    ["seed_alice_3", proposal()],
    ["seed_our", proposal({ slot: "our", title: "Our tree", startDay: ts(Date.UTC(2023, 2, 12, 10)) })],
    ["startdate", proposal({ kind: "startDate", slot: "our", title: undefined,
                             startDay: ts(Date.UTC(2023, 2, 10, 10)), fromStartDay: ts(Date.UTC(2023, 2, 12, 10)) })],
    ["change_p2", proposal({ kind: "change", slot: "p2" })],
    ["change_our", proposal({ kind: "change", slot: "our" })],
    ["rest_p3", proposal({ kind: "rest", slot: "p3", title: undefined })],
  ];
  for (const [id, doc] of cases) {
    const ev = garden.classify(id, null, doc);
    assert.ok(ev, id);
    assert.equal(ev.kind, "proposal", id);
    assert.equal(ev.proposalId, id);
    assert.equal(ev.by, "alice");
    assert.equal(ev.atMs, T0);
    assert.equal(ev.isCounter, false);
  }
});

test("classify: the old seed_ + 20-character id and other ids are silent", () => {
  assert.equal(garden.classify("seed_AbCdEfGhIjKlMnOpQrSt", null, proposal()), null);
  assert.equal(garden.classify("seed_alice_4", null, proposal()), null);
  assert.equal(garden.classify("seed_alice_0", null, proposal()), null);
  assert.equal(garden.classify("rest_our", null, proposal({ kind: "rest", slot: "our" })), null);
  assert.equal(garden.classify("change_p8", null, proposal({ kind: "change" })), null);
});

test("classify: an edit by the proposer is silent, a counter is `proposal` with isCounter", () => {
  const before = proposal();
  assert.equal(garden.classify("seed_alice_1", before, proposal({ rev: 2, at: ts(T0 + MIN), title: "Our trip" })), null);
  const ev = garden.classify("seed_alice_1", before, proposal({ by: "bob", rev: 2, at: ts(T0 + MIN) }));
  assert.equal(ev.kind, "proposal");
  assert.equal(ev.isCounter, true);
  assert.equal(ev.by, "bob");
  assert.equal(ev.atMs, T0 + MIN);
});

test("classify: a proposal deleted (taken back, let go, carried out) is silent", () => {
  assert.equal(garden.classify("seed_alice_1", proposal(), null), null);
  assert.equal(garden.classify("rest_p3", proposal({ kind: "rest", slot: "p3" }), null), null);
});

test("classify: a malformed proposal is silent", () => {
  assert.equal(garden.classify("seed_alice_1", null, proposal({ docType: "water" })), null);
  assert.equal(garden.classify("seed_alice_1", null, proposal({ at: null })), null);
  assert.equal(garden.classify("seed_alice_1", null, proposal({ kind: "grow" })), null);
  assert.equal(garden.classify("startdate", null, proposal({ kind: "startDate", slot: "our" })), null);
});

test("classify: a new tree agreement is `agreed`", () => {
  const ev = garden.classify("tree_p2", null, tree());
  assert.equal(ev.kind, "agreed");
  assert.equal(ev.slot, "p2");
  assert.equal(ev.proposerId, "alice");
  assert.equal(ev.accepterId, "bob");
  assert.equal(ev.agreementAtMs, T0);

  const changed = garden.classify("tree_p2", tree(), tree({ agreementKind: "change", agreementAt: ts(T0 + DAY) }));
  assert.equal(changed.kind, "agreed");
  assert.equal(changed.agreementAtMs, T0 + DAY);

  const ours = garden.classify("tree_our", tree({ slot: "our" }),
    tree({ slot: "our", agreementKind: "startDate", agreementAt: ts(T0 + DAY), agreedStartDay: ts(Date.UTC(2023, 2, 10, 10)) }));
  assert.equal(ours.kind, "agreed");
  assert.equal(ours.slot, "our");
});

test("classify: the same agreementAt (a look change, any other edit) is silent", () => {
  const before = tree();
  assert.equal(garden.classify("tree_p2", before, tree({ scene: "seaside", lookBy: "bob", lookAt: ts(T0 + HOUR) })), null);
  assert.equal(garden.classify("tree_p2", before, tree({ agreementAt: ts(T0) })), null);
});

test("classify: a recorded Our tree and malformed agreements are silent", () => {
  assert.equal(garden.classify("tree_our", null,
    tree({ slot: "our", origin: "legacy", agreementKind: "recorded", agreementBy: ["alice"],
           agreedStartDay: ts(Date.UTC(2023, 2, 12, 10)) })), null);
  assert.equal(garden.classify("tree_p2", null, tree({ agreementBy: ["alice", "alice"] })), null);
  assert.equal(garden.classify("tree_p2", null, tree({ agreementBy: ["alice"] })), null);
  assert.equal(garden.classify("tree_p2", null, tree({ agreementAt: undefined })), null);
  // Our tree's planting names its day; without it there is nothing to say.
  assert.equal(garden.classify("tree_our", null, tree({ slot: "our" })), null);
  assert.equal(garden.classify("tree_p8", null, tree()), null);
  assert.equal(garden.classify("tree_p2", tree(), null), null);
});

test("classify: config and waterers are silent", () => {
  assert.equal(garden.classify("config", null, { startDate: ts(T0), setBy: "alice" }), null);
  assert.equal(garden.classify("config", { startDate: ts(T0) }, { startDate: ts(T0 + DAY) }), null);
  assert.equal(garden.classify("waterer_alice", null,
    { docType: "waterer", lastWateredAt: ts(T0), lastWateringId: WATER_ID }), null);
});

// MARK: - wateringMoment

test("wateringMoment: the first watering ever", () => {
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: null, previousAnyMs: null }), "first");
});

test("wateringMoment: the partner 23 h 59 min before is together, 24 h 1 min is plain", () => {
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0 - (24 * HOUR - MIN),
                                       previousAnyMs: T0 - (24 * HOUR - MIN) }), "together");
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0 - 24 * HOUR,
                                       previousAnyMs: T0 - 24 * HOUR }), "together");
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0 - (24 * HOUR + MIN),
                                       previousAnyMs: T0 - (24 * HOUR + MIN) }), "plain");
});

test("wateringMoment: 7 days since the previous watering is returned", () => {
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: null, previousAnyMs: T0 - 7 * DAY }), "returned");
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: null, previousAnyMs: T0 - 7 * DAY + MIN }), "plain");
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0 - 8 * DAY, previousAnyMs: T0 - 8 * DAY }), "returned");
});

test("wateringMoment: together beats returned", () => {
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0 - HOUR, previousAnyMs: T0 - 8 * DAY }), "together");
});

test("wateringMoment: a partner watering after this one does not count", () => {
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0 + HOUR, previousAnyMs: T0 - 2 * DAY }), "plain");
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0 + HOUR, previousAnyMs: null }), "first");
  assert.equal(garden.wateringMoment({ atMs: T0, partnerLastBeforeMs: T0, previousAnyMs: T0 }), "first");
});

// MARK: - Copy

test("wateringCopy: plain, one tree and many, with and without a note", () => {
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: null, moment: "plain", treeCount: 1, msAfterPartner: 0 }),
    { title: "Sam watered your garden 💧", body: "Your tree had a drink. Peek when you have a moment." });
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: "", moment: "plain", treeCount: 3, msAfterPartner: 0 }),
    { title: "Sam watered your garden 💧", body: "Every tree had a drink. Peek when you have a moment." });
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: "Miss you too.", moment: "plain", treeCount: 3, msAfterPartner: 0 }),
    { title: "Sam watered your garden 💧", body: "“Miss you too.”" });
});

test("wateringCopy: first, with and without a note", () => {
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: null, moment: "first", treeCount: 1, msAfterPartner: 0 }),
    { title: "Sam gave your tree its first water 💧", body: "Your garden is growing on Journey." });
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: "Hi", moment: "first", treeCount: 1, msAfterPartner: 0 }),
    { title: "Sam gave your tree its first water 💧", body: "“Hi”" });
});

test("wateringCopy: together, with and without a note, and how long after", () => {
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: "Miss you too.", moment: "together", treeCount: 2, msAfterPartner: 3 * HOUR }),
    { title: "You watered together 💧", body: "Sam watered back: “Miss you too.”" });
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: null, moment: "together", treeCount: 2, msAfterPartner: 3 * HOUR + 59 * MIN }),
    { title: "You watered together 💧", body: "Sam watered back, 3 hours after you." });
  assert.equal(garden.wateringCopy({ name: "Sam", note: null, moment: "together", treeCount: 1, msAfterPartner: 20 * MIN }).body,
    "Sam watered back, a few minutes after you.");
  assert.equal(garden.wateringCopy({ name: "Sam", note: null, moment: "together", treeCount: 1, msAfterPartner: 90 * MIN }).body,
    "Sam watered back, an hour after you.");
});

test("wateringCopy: returned, with and without a note", () => {
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: null, moment: "returned", treeCount: 1, msAfterPartner: 0 }),
    { title: "Sam woke up the garden 🌧️", body: "It rested a while. It's green again." });
  assert.deepEqual(garden.wateringCopy({ name: "Sam", note: "Back!", moment: "returned", treeCount: 1, msAfterPartner: 0 }),
    { title: "Sam woke up the garden 🌧️", body: "“Back!”" });
});

test("copy: a 140-character note is cut to 100 with an ellipsis", () => {
  const body = garden.wateringCopy({ name: "Sam", note: "a".repeat(140), moment: "plain", treeCount: 1, msAfterPartner: 0 }).body;
  assert.equal(body, `“${"a".repeat(99)}…”`);
  assert.equal(garden.cleanText("a".repeat(100), 100), "a".repeat(100));
});

test("copy: an emoji at the cut is never split", () => {
  for (const emoji of ["😀", "👍🏽", "👩‍❤️‍👨", "🇻🇳"]) {
    const cut = garden.cleanText("a".repeat(98) + emoji.repeat(5), 100);
    assert.equal(cut, "a".repeat(98) + emoji + "…", emoji);
  }
  // A whole emoji counts as one character, as the app counts graphemes.
  const hundred = "👩‍❤️‍👨".repeat(100);
  assert.equal(garden.cleanText(hundred, 100), hundred);
});

test("copy: control characters are stripped and white space collapses", () => {
  assert.equal(garden.cleanText("  Miss\u0000 you\n\n\ttoo\u007F ", 100), "Miss you too");
  assert.equal(garden.cleanText("\u0001\u0002 \n", 100), null);
  assert.equal(garden.cleanText(42, 100), null);
  assert.equal(garden.wateringCopy({ name: "Sam", note: "\n\t ", moment: "first", treeCount: 1, msAfterPartner: 0 }).body,
    "Your garden is growing on Journey.");
});

test("proposalCopy: a place seed, Our tree's seed, and a counter", () => {
  assert.deepEqual(garden.proposalCopy({ name: "Sam", proposal: proposal({ title: "Where we first met" }), isCounter: false }),
    { title: "Sam wants to plant a tree with you 🌱", body: "For “Where we first met”. It's planted when you say yes." });
  assert.deepEqual(garden.proposalCopy({ name: "Sam", proposal: proposal({ slot: "our", title: "Our tree" }), isCounter: false }),
    { title: "Sam wants to plant your tree 🌱", body: "For the day your story began. It's planted when you say yes." });
  assert.deepEqual(garden.proposalCopy({ name: "Sam", proposal: proposal(), isCounter: true }),
    { title: "Sam suggested a change 🌱", body: "To your seed for “Our first trip”. Take a look on Journey." });
});

test("proposalCopy: a change, a rest request and a new start date", () => {
  assert.deepEqual(garden.proposalCopy({ name: "Sam", proposal: proposal({ kind: "change", slot: "p2" }), isCounter: false }),
    { title: "Sam suggested a change 🌱", body: "To “Our first trip”. It changes only if you agree." });
  assert.deepEqual(garden.proposalCopy({ name: "Sam", proposal: proposal({ kind: "change", slot: "p2" }), isCounter: true }),
    { title: "Sam suggested a change 🌱", body: "To “Our first trip”. It changes only if you agree." });
  assert.deepEqual(garden.proposalCopy({ name: "Sam", proposal: proposal({ kind: "rest", slot: "p3", title: undefined }),
                                         isCounter: false, treeTitle: "Our first trip" }),
    { title: "Sam asked to let a tree rest", body: "“Our first trip” stays in your garden until you agree." });
  assert.deepEqual(garden.proposalCopy({ name: "Sam", proposal: proposal({ kind: "rest", slot: "p3", title: undefined }),
                                         isCounter: false, treeTitle: null }),
    { title: "Sam asked to let a tree rest", body: "“your tree” stays in your garden until you agree." });
  assert.deepEqual(garden.proposalCopy({ name: "Sam", isCounter: false, timeZone: "Asia/Ho_Chi_Minh",
    proposal: proposal({ kind: "startDate", slot: "our", title: undefined,
                         startDay: ts(Date.UTC(2023, 2, 10, 10)), fromStartDay: ts(Date.UTC(2023, 2, 12, 10)) }) }),
    { title: "Sam suggested a new start date", body: "10 March 2023 instead of 12 March 2023. It changes only if you agree." });
});

test("proposalCopy: a 60-character title is cut to 40", () => {
  const title = "b".repeat(60);
  assert.equal(garden.proposalCopy({ name: "Sam", proposal: proposal({ title }), isCounter: false }).body,
    `For “${"b".repeat(39)}…”. It's planted when you say yes.`);
});

test("agreementCopy: every kind", () => {
  const day = ts(Date.UTC(2023, 2, 12, 10));
  assert.deepEqual(garden.agreementCopy({ name: "Sam", kind: "plant", slot: "our", title: "Our tree", agreedStartDay: day }),
    { title: "Your tree is planted 🌳", body: "Sam said yes. It grows from 12 March 2023." });
  assert.deepEqual(garden.agreementCopy({ name: "Sam", kind: "plant", slot: "p1", title: "Where we first met" }),
    { title: "Sam said yes 🌳", body: "Your tree for “Where we first met” is planted. Come see it grow." });
  assert.deepEqual(garden.agreementCopy({ name: "Sam", kind: "change", slot: "p2", title: "Our first trip" }),
    { title: "Sam agreed 🌳", body: "“Our first trip” has its new details." });
  assert.deepEqual(garden.agreementCopy({ name: "Sam", kind: "startDate", slot: "our", title: "Our tree",
                                          agreedStartDay: ts(Date.UTC(2023, 2, 10, 10)) }),
    { title: "Start date updated", body: "Sam agreed: your story begins on 10 March 2023." });
  assert.equal(garden.agreementCopy({ name: "Sam", kind: "recorded", slot: "our", title: "Our tree" }), null);
});

// MARK: - dayText

test("dayText: a stored day names its UTC date whatever the zone", () => {
  const stored = new Date(Date.UTC(2023, 2, 12, 10));
  assert.equal(garden.isStoredDay(stored), true);
  for (const zone of [undefined, "UTC", "Asia/Ho_Chi_Minh", "America/Los_Angeles", "Pacific/Kiritimati", "Pacific/Pago_Pago"]) {
    assert.equal(garden.dayText(stored, zone), "12 March 2023", String(zone));
  }
});

test("dayText: a raw 1.2 instant names the day in the recipient's zone", () => {
  const raw = new Date(Date.UTC(2023, 2, 11, 18));
  assert.equal(garden.isStoredDay(raw), false);
  assert.equal(garden.dayText(raw, "Asia/Ho_Chi_Minh"), "12 March 2023");
  assert.equal(garden.dayText(raw, "America/Los_Angeles"), "11 March 2023");
  assert.equal(garden.dayText(raw, null), "11 March 2023");
  assert.equal(garden.dayText(raw, "Not/AZone"), "11 March 2023");
});

// MARK: - isQuietHour

/** The UTC instant at which `zone` reads `hour:minute` on `y-m-d` (zones with whole-hour offsets). */
function localTime(zone, y, m, d, hour, minute) {
  const guess = Date.UTC(y, m, d, hour, minute);
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", minute: "numeric", hourCycle: "h23",
                                                 year: "numeric", month: "numeric", day: "numeric" });
  for (let offset = -14; offset <= 14; offset++) {
    const at = new Date(guess - offset * HOUR);
    const parts = Object.fromEntries(fmt.formatToParts(at).map((p) => [p.type, p.value]));
    if (Number(parts.hour) === hour && Number(parts.minute) === minute && Number(parts.day) === d) return at;
  }
  throw new Error(`no ${hour}:${minute} in ${zone}`);
}

test("isQuietHour: 21:59 / 22:00 / 06:59 / 07:00 in Ho Chi Minh City and Los Angeles", () => {
  for (const zone of ["Asia/Ho_Chi_Minh", "America/Los_Angeles"]) {
    assert.equal(garden.isQuietHour(zone, localTime(zone, 2026, 10, 14, 21, 59)), false, `${zone} 21:59`);
    assert.equal(garden.isQuietHour(zone, localTime(zone, 2026, 10, 14, 22, 0)), true, `${zone} 22:00`);
    assert.equal(garden.isQuietHour(zone, localTime(zone, 2026, 10, 14, 6, 59)), true, `${zone} 06:59`);
    assert.equal(garden.isQuietHour(zone, localTime(zone, 2026, 10, 14, 7, 0)), false, `${zone} 07:00`);
  }
});

test("isQuietHour: across a DST change in Los Angeles", () => {
  // 8 March 2026: clocks go from 02:00 PST to 03:00 PDT.
  const zone = "America/Los_Angeles";
  assert.equal(garden.isQuietHour(zone, new Date(Date.UTC(2026, 2, 8, 9, 59))), true);    // 01:59 PST
  assert.equal(garden.isQuietHour(zone, new Date(Date.UTC(2026, 2, 8, 13, 59))), true);   // 06:59 PDT
  assert.equal(garden.isQuietHour(zone, new Date(Date.UTC(2026, 2, 8, 14, 0))), false);   // 07:00 PDT (would be 06:00 PST)
  assert.equal(garden.isQuietHour(zone, new Date(Date.UTC(2026, 2, 9, 4, 59))), false);   // 21:59 PDT
  assert.equal(garden.isQuietHour(zone, new Date(Date.UTC(2026, 2, 9, 5, 0))), true);     // 22:00 PDT
  // 1 November 2026: clocks go back from 02:00 PDT to 01:00 PST.
  assert.equal(garden.isQuietHour(zone, new Date(Date.UTC(2026, 10, 1, 14, 59))), true);  // 06:59 PST
  assert.equal(garden.isQuietHour(zone, new Date(Date.UTC(2026, 10, 1, 15, 0))), false);  // 07:00 PST
});

test("isQuietHour: an invalid zone is never quiet; a missing one is UTC", () => {
  assert.equal(garden.isQuietHour("Not/AZone", new Date(Date.UTC(2026, 10, 14, 23))), false);
  assert.equal(garden.isQuietHour(null, new Date(Date.UTC(2026, 10, 14, 23))), true);
  assert.equal(garden.isQuietHour(undefined, new Date(Date.UTC(2026, 10, 14, 12))), false);
});

test("utcDayKey: the UTC calendar day", () => {
  assert.equal(garden.utcDayKey(new Date(Date.UTC(2026, 10, 14, 23, 59))), "20261114");
  assert.equal(garden.utcDayKey(new Date(Date.UTC(2026, 0, 1, 0, 0))), "20260101");
});

// MARK: - canReceiveGardenPush

test("canReceiveGardenPush: only a garden token device with the toggle on", () => {
  assert.equal(garden.canReceiveGardenPush(null), false, "missing user");
  assert.equal(garden.canReceiveGardenPush({}), false, "no token");
  assert.equal(garden.canReceiveGardenPush({ fcmToken: "", gardenPushToken: "" }), false, "empty token");
  assert.equal(garden.canReceiveGardenPush({ fcmToken: "t1" }), false, "token without gardenPushToken (legacy)");
  assert.equal(garden.canReceiveGardenPush({ fcmToken: "t2", gardenPushToken: "t1" }), false, "mismatched tokens");
  assert.equal(garden.canReceiveGardenPush({ fcmToken: "t1", gardenPushToken: "t1" }), true, "matching tokens");
  assert.equal(garden.canReceiveGardenPush({ fcmToken: "t1", gardenPushToken: "t1",
                                             notificationPreferences: { garden: true } }), true, "toggle on");
  assert.equal(garden.canReceiveGardenPush({ fcmToken: "t1", gardenPushToken: "t1",
                                             notificationPreferences: { chat: false } }), true, "toggle absent");
  assert.equal(garden.canReceiveGardenPush({ fcmToken: "t1", gardenPushToken: "t1",
                                             notificationPreferences: { garden: false } }), false, "toggle off");
});

// MARK: - isSwitchedOff

test("isSwitchedOff: only `enabled: false` in appConfig/garden switches the garden off", () => {
  assert.equal(garden.isSwitchedOff(null), false, "no document");
  assert.equal(garden.isSwitchedOff({}), false, "no field");
  assert.equal(garden.isSwitchedOff({ enabled: true }), false, "on");
  assert.equal(garden.isSwitchedOff({ enabled: false }), true, "off");
  assert.equal(garden.isSwitchedOff({ enabled: "false" }), false, "a string is not the switch, as in the app");
  assert.equal(garden.isSwitchedOff({ enabled: null }), false, "null");
});

// MARK: - Contract parity

test("push types equal GardenNotification's", () => {
  assert.deepEqual(garden.PUSH, { watered: "garden_watered", proposal: "garden_proposal", agreed: "garden_agreed" });
  assert.equal(garden.TOGETHER_MS, 24 * HOUR);
  assert.equal(garden.REST_MS, 168 * HOUR);
  assert.equal(garden.DAILY_CAP, 6);
});
