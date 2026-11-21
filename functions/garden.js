"use strict";

// =============================================================================
// Our Garden — pure push logic for `onTimeTreeMetaWritten` (index.js).
// =============================================================================
//
// No Firebase imports: everything here takes plain values (and Firestore
// `Timestamp`s, used only through toMillis / toDate / isEqual), so the unit
// suite (functions/test/garden.test.js) runs on Node alone.
//
// The constants mirror the app's contract (GardenContract.swift):
// TOGETHER_MS = GardenCadence.togetherWindow, REST_MS =
// GardenCadence.rainReturnsAfter, PUSH = GardenNotification's push types, and
// `wateringMoment` is GardenMoment.of over server times.
//
// Push copy is English: notifications are composed on the server, like every
// other Coupley push. It never names a place (lock screens are public), and
// nothing here is ever logged.

const HOUR = 3600e3;
const TOGETHER_MS = 24 * HOUR;                // = GardenCadence.togetherWindow
const REST_MS = 7 * 24 * HOUR;                // = GardenCadence.rainReturnsAfter
const DAILY_CAP = 6;                          // garden pushes per recipient per UTC day
const QUIET_FROM = 22, QUIET_UNTIL = 7;       // recipient's local hours 22:00–06:59
const PUSH = { watered: "garden_watered", proposal: "garden_proposal", agreed: "garden_agreed" };

const PROPOSAL_KINDS = ["plant", "change", "rest", "startDate"];
const AGREEMENT_KINDS = ["plant", "change", "startDate"];

/** `water_` + a 20-character Firestore auto id (GardenDocID.water). */
const isWaterId = (id) => /^water_[A-Za-z0-9]{20}$/.test(id);

/** seed_our, startdate, seed_<uid>_<1–3>, change_<slot>, rest_<place slot> (GardenDocID.isProposal). */
const isProposalId = (id) => id === "seed_our" || id === "startdate" || /^seed_[A-Za-z0-9]{1,128}_[1-3]$/.test(id)
  || /^change_(our|p[1-7])$/.test(id) || /^rest_p[1-7]$/.test(id);

/** A Firestore Timestamp (or anything that reads like one). */
const isTimestamp = (v) => !!v && typeof v.toMillis === "function" && typeof v.toDate === "function";

/**
 * What a timeTreeMeta write means for a push, or null. Silent: `config`,
 * waterers, look changes, edits by the proposer, deletions (a seed taken back
 * or let go, a request kept, a tree let rest, a purge) and recordings.
 *
 * - `watered`: a watering created (waterings are immutable).
 * - `proposal`: a proposal created, or answered with the other partner's own
 *   version (`isCounter`, the latest `by` changed).
 * - `agreed`: a tree carrying a new agreement (`agreementAt` changed) made by
 *   two different partners.
 */
function classify(docId, before, after) {
  if (isWaterId(docId)) {
    if (before || !after || after.docType !== "water" || typeof after.by !== "string" || !after.by
        || !isTimestamp(after.wateredAt)) return null;
    return { kind: "watered", wateringId: docId, by: after.by, at: after.wateredAt,
             note: typeof after.note === "string" ? after.note : null };
  }
  if (isProposalId(docId)) {
    if (!after || after.docType !== "proposal" || typeof after.by !== "string" || !after.by
        || !isTimestamp(after.at) || !PROPOSAL_KINDS.includes(after.kind)) return null;
    // The start-date copy names both days; a proposal without them is malformed.
    if (after.kind === "startDate" && !(isTimestamp(after.startDay) && isTimestamp(after.fromStartDay))) return null;
    const isCounter = !!before && before.by !== after.by;
    if (before && !isCounter) return null;
    return { kind: "proposal", proposalId: docId, by: after.by, atMs: after.at.toMillis(), isCounter, proposal: after };
  }
  const tree = /^tree_(our|p[1-7])$/.exec(docId);
  if (tree) {
    if (!after || !isTimestamp(after.agreementAt) || !AGREEMENT_KINDS.includes(after.agreementKind)) return null;
    if (before && isTimestamp(before.agreementAt) && before.agreementAt.isEqual(after.agreementAt)) return null;
    const [proposerId, accepterId] = Array.isArray(after.agreementBy) ? after.agreementBy : [];
    if (typeof proposerId !== "string" || typeof accepterId !== "string"
        || !proposerId || !accepterId || proposerId === accepterId) return null;
    // Our tree's planting and a start-date agreement name the agreed day.
    const namesDay = after.agreementKind === "startDate" || (after.agreementKind === "plant" && tree[1] === "our");
    if (namesDay && !isTimestamp(after.agreedStartDay)) return null;
    return { kind: "agreed", slot: tree[1], proposerId, accepterId,
             agreementAtMs: after.agreementAt.toMillis(), tree: after };
  }
  return null;
}

/**
 * The admin's remote switch, `appConfig/garden` (E8): the garden is off only
 * while `enabled` is exactly `false`, as the app reads it. A missing document
 * or field means on. `config` is the document's data, or null when missing.
 */
function isSwitchedOff(config) {
  return !!config && config.enabled === false;
}

/**
 * Garden pushes go only to a token device that runs a garden build
 * (`gardenPushToken == fcmToken`), with the Garden toggle on (absent = on).
 * A legacy partner never matches, so it never gets a garden push.
 */
function canReceiveGardenPush(user) {
  return !!user && typeof user.fcmToken === "string" && user.fcmToken.length > 0
    && user.gardenPushToken === user.fcmToken
    && !(user.notificationPreferences && user.notificationPreferences.garden === false);
}

/**
 * "first" | "together" | "returned" | "plain" from server times (ms), as
 * GardenMoment.of: only waterings strictly before this one count.
 * `partnerLastBeforeMs` is the recipient's latest watering before it,
 * `previousAnyMs` the latest watering by either partner before it.
 */
function wateringMoment({ atMs, partnerLastBeforeMs, previousAnyMs }) {
  const earlier = (ms) => (ms != null && ms < atMs ? ms : null);
  const partner = earlier(partnerLastBeforeMs);
  const previous = earlier(previousAnyMs);
  if (previous == null && partner == null) return "first";
  if (partner != null && atMs - partner <= TOGETHER_MS) return "together";
  const latest = Math.max(previous ?? partner, partner ?? previous);   // either one may be missing
  if (atMs - latest >= REST_MS) return "returned";
  return "plain";
}

const graphemeSegmenter = typeof Intl.Segmenter === "function"
  ? new Intl.Segmenter("en", { granularity: "grapheme" })
  : null;

/** User-perceived characters (an emoji with its modifiers is one), as the app counts them. */
function graphemes(text) {
  return graphemeSegmenter ? Array.from(graphemeSegmenter.segment(text), (s) => s.segment) : Array.from(text);
}

/**
 * Control characters become spaces, runs of white space collapse, and the
 * text is cut to `max` characters with "…" (never inside an emoji).
 * null for anything that is not a string with something in it.
 */
function cleanText(s, max) {
  if (typeof s !== "string") return null;
  const t = s.replace(/[\u0000-\u001F\u007F]/g, " ").replace(/\s+/g, " ").trim();
  if (!t) return null;
  const chars = graphemes(t);
  return chars.length > max ? chars.slice(0, max - 1).join("").trimEnd() + "…" : t;
}

const quote = (note) => { const t = cleanText(note, 100); return t ? `“${t}”` : null; };
const titled = (title) => `“${cleanText(title, 40) || "your tree"}”`;

/** How long after the partner's watering, in words ("3 hours"). */
function apart(ms) {
  const h = ms / HOUR;
  return h < 1 ? "a few minutes" : h < 2 ? "an hour" : `${Math.floor(h)} hours`;
}

/**
 * A stored calendar day (10:00 UTC) names its UTC date; any other instant
 * (1.1/1.2) names the day in the recipient's zone, like localDay(ofStored:).
 */
function isStoredDay(d) {
  return d.getUTCHours() === 10 && d.getUTCMinutes() === 0 && d.getUTCSeconds() === 0 && d.getUTCMilliseconds() === 0;
}

/** "12 March 2023". */
function dayText(date, timeZone) {
  const opts = { day: "numeric", month: "long", year: "numeric" };
  try {
    return date.toLocaleDateString("en-GB", { ...opts, timeZone: isStoredDay(date) ? "UTC" : (timeZone || "UTC") });
  } catch {
    return date.toLocaleDateString("en-GB", { ...opts, timeZone: "UTC" });
  }
}

/** The watering push (B8). `msAfterPartner` is used only for "together". */
function wateringCopy({ name, note, moment, treeCount, msAfterPartner }) {
  const q = quote(note);
  switch (moment) {
    case "first":    return { title: `${name} gave your tree its first water 💧`, body: q || "Your garden is growing on Journey." };
    case "together": return { title: "You watered together 💧",
                              body: q ? `${name} watered back: ${q}` : `${name} watered back, ${apart(msAfterPartner)} after you.` };
    case "returned": return { title: `${name} woke up the garden 🌧️`, body: q || "It rested a while. It's green again." };
    default:         return { title: `${name} watered your garden 💧`,
                              body: q || (treeCount > 1 ? "Every tree had a drink. Peek when you have a moment."
                                                        : "Your tree had a drink. Peek when you have a moment.") };
  }
}

/** A new proposal or a counter (B8). `treeTitle` is the target tree's title for rest/startDate. */
function proposalCopy({ name, proposal, isCounter, treeTitle, timeZone }) {
  const t = titled(proposal.title || treeTitle);
  switch (proposal.kind) {
    case "startDate":
      return { title: `${name} suggested a new start date`,
               body: `${dayText(proposal.startDay.toDate(), timeZone)} instead of ${dayText(proposal.fromStartDay.toDate(), timeZone)}. It changes only if you agree.` };
    case "rest":
      return { title: `${name} asked to let a tree rest`, body: `${t} stays in your garden until you agree.` };
    case "change":
      return { title: `${name} suggested a change 🌱`, body: `To ${t}. It changes only if you agree.` };
    default:   // plant
      if (isCounter) return { title: `${name} suggested a change 🌱`, body: `To your seed for ${t}. Take a look on Journey.` };
      if (proposal.slot === "our") return { title: `${name} wants to plant your tree 🌱`,
                                            body: "For the day your story began. It's planted when you say yes." };
      return { title: `${name} wants to plant a tree with you 🌱`, body: `For ${t}. It's planted when you say yes.` };
  }
}

/** An agreement, sent to the proposer (B8); null for a kind that never pushes. */
function agreementCopy({ name, kind, slot, title, agreedStartDay, timeZone }) {
  if (kind === "plant" && slot === "our")
    return { title: "Your tree is planted 🌳", body: `${name} said yes. It grows from ${dayText(agreedStartDay.toDate(), timeZone)}.` };
  if (kind === "plant") return { title: `${name} said yes 🌳`, body: `Your tree for ${titled(title)} is planted. Come see it grow.` };
  if (kind === "change") return { title: `${name} agreed 🌳`, body: `${titled(title)} has its new details.` };
  if (kind === "startDate")
    return { title: "Start date updated", body: `${name} agreed: your story begins on ${dayText(agreedStartDay.toDate(), timeZone)}.` };
  return null;
}

/** 22:00–06:59 in the recipient's zone: the push is passive (no sound, no badge). An unknown zone is never quiet. */
function isQuietHour(timeZone, now = new Date()) {
  try {
    const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone: timeZone || "UTC", hour: "numeric", hourCycle: "h23" }).format(now));
    return hour >= QUIET_FROM || hour < QUIET_UNTIL;
  } catch {
    return false;
  }
}

/** "20261114": the UTC day a daily cap counts in. */
const utcDayKey = (now = new Date()) => now.toISOString().slice(0, 10).replace(/-/g, "");

module.exports = { TOGETHER_MS, REST_MS, DAILY_CAP, PUSH, isWaterId, isProposalId, classify, isSwitchedOff,
                   canReceiveGardenPush, wateringMoment, cleanText, apart, isStoredDay, dayText, wateringCopy,
                   proposalCopy, agreementCopy, isQuietHour, utcDayKey };
