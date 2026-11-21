# Our Garden — final build spec

*Journey's shared garden for Coupley. Final spec for parallel build. Grounded in the repository of 14 Nov 2026: HEAD `a33486e` is the 1.3 build (Future Letters, the Journey overhaul and its first review fixes; `MARKETING_VERSION` 1.3) and about 150 files of further uncommitted Journey edits sit in the working tree; `JourneyCalendarDay.storedMoment` writes 10:00 UTC. The shipped 1.2 is `155ed55`; 1.1 is `1825885`. No repository file was edited. Starts from the winning proposal (ritual), grafts the judges' picks from systems and visual, fixes every must-fix, and fixes every gap of the completeness review (0.3). The shared types are in `contract.swift` (repo path `Coupley/Features/Garden/Models/GardenContract.swift`); it typechecks under the project's flags (Swift 5, default MainActor isolation, approachable concurrency, MemberImportVisibility, warnings as errors) together with the repo's real `TreeGrowthStage.swift`, and its pure logic was run against the thresholds in this document.*

**What the user asked for, and where it is answered**

| # | Request (Vietnamese messages a and b) | Answer |
|---|---|---|
| 1 | A tree is planted by both; nothing is planted until both agree | A3, A4, F1 (`plantedFrom`) |
| 2 | Water every 2–3 days, both taking part; each watering pushes the partner and leaves a message with who and when | A6, A7, B3, B7, G, H |
| 3 | Varied watering animations that feel like caring for a real plant | C9 |
| 4 | Varied, beautiful places for the tree, and a nicer position | C1–C4 |
| 5 | A tree can stand at a real place ("where we first met", "our first date", "our first trip") | A3, D |
| 6 | More trees make a garden; one tap waters them all | A3, A6, C7, C9 |

Copy below uses "Sam" for the partner's display name and "Alex" for the user.

---

## 0. Decisions

### 0.0 The user's answers (14 Nov 2026) — these override anything below

1. **Watering**: either partner can water; two partners within 24 h is the celebrated "watered together" bonus (the default, unchanged).
2. **Start date**: always needs both partners' agreement, also when the partner is on an older app (the default, unchanged).
3. **Growth**: **every place tree grows from the day it is planted** (it starts as a seed), never from its moment's day. The moment's day stays as a remembered date on the postcard and in the title line ("Our first trip · 12 March 2023") and still prefills from the Timeline, but it never changes size or stage. Our tree still grows from the start date. **Watering is a reward only**: a watered tree is greener, fuller and glossier than its plain look for a day or two (`lushness`, with wet soil and dew, C6); a tree left unwatered converges back to its plain look and never droops, dries, dies or loses growth, and watering never changes the growth stage. So the look runs lush (just watered) → plain, and stays plain however long it waits. The water states (ready, thirsty, resting) stay as status text, copy and reminders only. One switch holds this: `GardenTreeLook.withersWhenThirsty = false` (contract); `true` brings back the thirsty → resting droop of C6 and the guide's and FAQ's copy for it, which stay in the code.
4. **Constants**: exactly as proposed (12 h per person; together within 24 h; ready 48 h, thirsty 72 h, resting 7 days; 8 trees; 3 open seeds per person; reminders at 19:00; ≤ 6 garden pushes a day; quiet 22:00–06:59).
5. **Version**: the garden ships in the release after 1.3. `GardenFeature.isEnabled` stays on in DEBUG and off in Release until that release (Gate 3); the work lives on its own branch.

### 0.1 The final decisions

| # | Decision | Source / why |
|---|---|---|
| D1 | **Storage: flat documents in `couples/{c}/timeTreeMeta`** next to `config`, ids by kind (`tree_our`, `tree_p1…p7`, `seed_our`, `seed_<uid>_<1–3>`, `change_<slot>`, `rest_<slot>`, `startdate`, `water_<20>`, `waterer_<uid>`). Never a subcollection. Place-seed ids are bounded per creator, so the rules cap open seeds at 3 per person by construction. | systems/visual. 1.2's purge (`155ed55` `ConnectionService.remainingSubcollections`, kept in 1.3) already deletes this collection, so places and notes leave with every 1.2+ deletion; the garden app makes that purge required. |
| D2 | **Server purge `onCouplePurged`** (`onDocumentDeleted("couples/{c}")` → `recursiveDelete`), deployed with the garden functions **before** the app. | must-fix. Covers 1.1 (whose purge never touched `timeTreeMeta`), 1.2's best-effort `try?`, and any partial purge. It also removes Future Letters bodies a 1.2 deletion orphans today. |
| D3 | **Rules probe `appConfig/garden`** (`allow get: if isSignedIn()`), shipped in the same rules file. Permission-denied ⇒ the garden rules are not deployed ⇒ the garden is unavailable and writes nothing. `{enabled:false}` (admin only) ⇒ the pre-garden Journey. | Closes the flat layout's only weakness: today's open `timeTreeMeta` rule would otherwise accept unvalidated garden writes if the app ever shipped first. |
| D4 | **`config` is unchanged** (fields, types, open rule). Day counts read it in every version. Garden apps write it only inside the two consent transactions (first planting, start-date agreement), copying the raw `Timestamp` from the proposal snapshot. | ritual/systems. 1.2 keeps working; no 1.2 write can corrupt garden state. |
| D5 | **Consent = propose + carry out.** A proposal document is carried out only by the partner who did not make its latest version, in ONE transaction that writes exactly the proposal's content with server times and both uids, and deletes the proposal. Edits and counters bump `rev`; carrying out checks the **version the user saw**: `GardenProposalVersion` = `rev` + the server time `at` of that version, so a proposal taken back and re-sent under the same fixed id (it restarts at `rev 1`) is never carried out unseen. Every proposal, place seeds included, is created in a transaction (it needs a connection); only waterings and look changes queue offline. | ritual (+ systems' `rev`, + review: ABA). |
| D6 | **Our tree** = `tree_our`, exists iff a start date exists. Existing couples: Our tree counts as planted by both; the first garden client online records it (`origin: legacy`, Meadow, oak). New couples plant it from `seed_our` (start day required). It never moves, never leaves; letters, stars and crowns stay on it only. | ritual |
| D7 | **Place trees**: up to 7 more (8 in all, enforced by the slot ids). Each stands for a preset or the couple's words, a moment's day (optional, remembered only), a place (optional) and a look. **They grow from the day they are planted** (0.0 #3). | user, 14 Nov |
| D8 | **Identity needs consent, looks don't.** Name, place and moment change by a `change_<slot>` proposal; scene and species change directly by either partner with "Change it back" for 24 h. Removing a place tree needs a `rest_<slot>` request the other confirms. Changing the start date needs a `startdate` proposal, void the moment `config.startDate` changes another way. | ritual, must-fix (stale consent) |
| D9 | **Watering**: garden-level, one tap waters every planted tree; either partner; once per person per 12 h (rules: 11 h 50 min); states fresh < 48 h ≤ ready < 72 h ≤ thirsty < 168 h ≤ resting, as words only (the tree never droops, 0.0 #3); never dies, never changes growth. The **garden's** state (status line, CTA, primary action, Home, reminders) comes from the latest watering alone; a tree planted since then only *looks* freshly planted (wet soil and dew, never the watering's lushness). "Watered together" = the two partners within 24 h. "Water back" loop. "The rain returns" after ≥ 7 days. | ritual; Q1, Q4 |
| D10 | **Watering note**: optional, 100 graphemes (≤ 400 UTF-8 bytes), written before watering in a small ✎ sheet, in the push and on Journey, kept in the journal. | ritual + visual graft |
| D11 | **The effect is stored on the watering** and replayed exactly by the partner. Six effects, deterministic choice. | visual graft, must-fix |
| D12 | **Pushes**: one trigger on `timeTreeMeta`, sent only when the recipient's token device runs a garden build (`users/{to}.gardenPushToken == fcmToken`), the couple is active and `notificationPreferences.garden != false`. Claim-once ledger, 6 garden pushes per recipient per UTC day, passive (no sound, no badge) 22:00–06:59 recipient time, `content-available` on waterings. No "update Coupley" pushes ever. | ritual + systems grafts + must-fix |
| D13 | **Local reminders**: two ids (`tt.garden.ready` first 19:00 ≥ last +48 h; `tt.garden.rest` first 19:00 ≥ last +7 d), floating calendar triggers, owned by `WidgetSyncService` on its serial chain, re-planned on every confirmed watering snapshot, on foreground and from the watering push; **monotonic** (a plan built from an older watering than the one already planned is ignored). | ritual + systems + must-fix + review |
| D14 | **Legacy = any build without the garden capability** (`users/{uid}.capabilities.garden`): 1.1 (`1825885`), the shipped 1.2 (`155ed55`), the garden-less 1.3 (`a33486e`) and any later cut without the garden; never a version string. | must-fix |
| D15 | **Hero**: a full-bleed scene band (208 / 176 / 168 pt) inside the hero card; the tree stands on a knoll at the right third, the landmark balances it on the left third, foreground grass overlaps the trunk base; words are SwiftUI overlays or sit under the band. One page per planted tree. | visual graft |
| D16 | **Rendering**: static layers rendered once to `CGImage` (ImageRenderer), keyed by **scene, not tree**, in a memory tier sized from the working set plus a disk tier, neighbouring pages pre-warmed; one `TimelineView` per page drives sky life, ambience, tree and effect; only the selected page animates; paused off screen / under a Journey sheet / tab hidden / inactive / Low Power / Reduce Motion. The tree painter keeps today's main-actor isolation; scene and effect painters are `nonisolated`. | systems + visual grafts, must-fix, review |
| D17 | **8 scenes** (Meadow, Seaside, City Lights, Mountain Lake, Lantern Town, Rice Terraces, Campus, Home), **5 species** (oak, cherry, banyan for any tree; pine, palm for place trees only). Sky at the place's local time; climate-aware seasons (tropical never snows; a tree without a place never snows). | visual + ritual, must-fix |
| D18 | **Places**: chosen by Apple Maps search or a centre pin; never the device location. Stored: name, locality, lat/lng rounded to 4 dp (exact) or 2 dp (area, the default for addresses and pins), precision, POI category, time zone. Rounding enforced by the rules. Never in pushes or logs. | visual graft, must-fix |
| D19 | **Home**: one quiet ambient row (a request waiting for me, or the partner's watering < 24 h unseen). No badge, no thirst on Home. **Chat**: nothing automatic. | ritual |
| D20 | **Deploy order**: rules (whole file, emulator suite + mutants green 3×) → functions → privacy page and App Store answers → app. Each deploy needs the user's explicit approval. Prerequisite for every emulator gate: a Java 21 runtime on this Mac (missing today; installing it needs the user's approval). | must-fix, review |
| D21 | **Testing against the emulators**: a DEBUG-only launch argument `-useFirestoreEmulator` (P4, `FirebaseEmulatorSwitch`) points Auth (9099) and Firestore (8080) at local emulators under the `demo-coupley-rules` project before anything touches Firebase; test accounts use the app's email/password sign-up. Release builds contain no emulator code. | review |
| D22 | **Copy is localizable from day one**: every garden string is `String(localized:comment:)`, a whole sentence or one format with placeholders, never concatenated (the working tree's convention). A preset's title is stored as base-language data and shown through `GardenPreset.displayTitle(stored:)`. A short word whose English key already means something else in the catalog gets its own key with a `defaultValue` (as `together.category.home` does): the Home scene's name `garden.scene.home` (not the Home tab), the look picker's current-scene tag `garden.look.current` "Now" (not a sealed letter's countdown) and the place picker's `garden.places.recent` "Recent" (not the notifications header). | review |

### 0.2 Must-fix checklist (judges' list → where it is fixed)

| Must-fix | Fixed in |
|---|---|
| Calendar days at 10:00 UTC; never pin the hour; push formats days like `localDay(ofStored:)` | contract header, E3/E4, F1 `isDay`, G2 `dayText` |
| No exact compare after a Date round trip | F1 `sameInstant` everywhere 1.2 instants meet garden values; I4 raw-snapshot copies |
| Purge coverage (1.1, 1.2 best-effort, garden app required) | D1, D2, G6, I2 (`ConnectionService`) |
| Deploy order, no unvalidated window, "unavailable" never hangs, no push claim | D3, D20, A11, B3.5, L3 |
| Place data minimisation, area default, no names in pushes/logs, privacy page/FAQ/App Store/manifest, attribution | D5–D6 of section D |
| Push volume (≥ 12 h cooldown, daily cap, passive nights, server toggle, no per-watering legacy pushes) | A6, G5 |
| Push routing by token device, own claims and cap, passive without badge/sound | D12, G1, G3 |
| Stale reminders (content-available, foreground re-plan, remove delivered), ≤ 3 of 64, `enqueueReminderWork` refactor | H |
| Stale start-date consent voided by a 1.2 edit | A4, F1 (`proposalFits`, `startDateFrom`) |
| "bởi cả 2", together window 12–24 h, "Where we first met" preset | Q1, D9, A3 presets |
| Legacy = capability flag | D14 |
| + is outlined (not hidden) without a start date; hero height at 375×667 and AX5; BrandCTA fixed height | B2, B3.1, C1, C10 |
| Static layers truly static; one clock; selected page only; sky-aware bark; measure on A12/A13 | C2, C11, contract `TreeBackdrop` |
| Consent transactions: offline check, bounded timeout, raw values, never "Planted" before commit | I4 |
| Product constants confirmed and server-enforced | Q4, F1, G2 |
| Re-ground before coding (Journey review still editing) | M0 |

### 0.3 Completeness review → where each gap is fixed

| Gap | Fix | Where |
|---|---|---|
| Test tooling missing: no emulator switch in the app, no reminder viewer, the "1.2" partner was a 1.3 build, no Java runtime | DEBUG `-useFirestoreEmulator` (P4: Auth + Firestore emulators, demo project, email/password test accounts); the lab's Reminders viewer (P10); the legacy partner is `155ed55` (1.2), with `a33486e` (garden-less 1.3) and `1825885` (1.1) as extra checks; Java 21 a listed prerequisite that needs the user's approval; a production fallback for K5.10 before Gate 1 | K0, K5, K6, L2 #0, P1, P2, P4, P10 |
| ABA on fixed-id proposals (re-created at `rev 1`) | `GardenProposalVersion` (`rev` + server `at` in ms) carried by every consent action and compared in the transaction; no rules change | A3, D5, I3, I4, J1, contract |
| Backdrop cache smaller than the working set; renders mid-swipe; first appearance; animating under sheets | static layers keyed by scene (no tree seed); memory tier sized from the working set (`GardenBackdropBudget`); disk tier; neighbour pre-warm; placeholder band on first appearance; `GardenMotionGate` includes `journeySheetPresented`; measured in K5.14 | C2, C4, C11, K5.14, P5, P10, contract |
| Garden-level water state undefined with trees planted after the last watering | status, water action, resolver, Home and reminders use `L` alone (`GardenWaterState.garden`); `max(L, plantedAt)` only for a tree's look | A6, B3, H, K3, contract |
| Reminder re-plan not monotonic | `GardenReminderPlan.isStale` guard in the scheduler; confirmed waterings only; the push path joins the serial chain when bound | H, P4, contract |
| Two accent fills in the unavailable no-start-date hero | unavailable and loading heroes show no CTA (`GardenPrimaryAction.emptyHeroShowsButton`) | A11, B2, B3.5, M3, contract |
| Nonisolated tree painter vs main-actor `TreeGrowthStage`/`TreeSeason` | the tree painter keeps today's main-actor isolation; only scene and effect painters are `nonisolated` and never call stage/season members (verified: a nonisolated access fails the warnings-as-errors typecheck) | C2, I6, P7, P8 |
| Previews on the DEBUG-only in-memory service break Release | `#if DEBUG` around those previews; a Release build in M3 | K7, M0, M3 |
| Coarse Location undeclared; FAQ sentences untrue for existing couples | Coarse Location (App Functionality) in App Store Connect and the manifest, both at Gate 3 (a pre-Gate 3 Release build collects no location); FAQ reworded | D6, L2 #4–5, L4 |
| Garden copy bypasses `String(localized:comment:)`; preset titles stored as display strings | localized copy everywhere, formats instead of concatenation; stored titles are base-language data shown through `displayTitle(stored:)` | D22, M0, P3, contract |
| Unbounded place seeds in the rules | ids `seed_<uid>_1…3`, created by their owner only (rules), picked in a transaction; tests 49–50, mutant 15 | A3, A8, E1, E4, F1, F3, F4, G2, contract |

---

## A. Product rules

### A1. Words

- **Garden**: all of a couple's planted trees. One water clock for the whole garden.
- **Our tree**: the first tree (`tree_our`). It exists exactly when the start date exists (`timeTreeMeta/config`). It is the tree Journey has today.
- **Place tree**: one of up to 7 more trees (`tree_p1`…`tree_p7`), each standing for a moment and, optionally, a real place.
- **Seed**: a proposal to plant a tree. **Request**: a proposal to change a tree, let one rest, or change the start date. Nothing happens until the *other* partner answers.
- **Look**: a tree's scene (the illustrated place) and species.

### A2. Our tree

1. Our tree is planted iff the start date exists. It grows from the start date exactly as today: same `TreeGrowthStage` thresholds, same leaves (seeded from the days together, so the silhouette does not change), same letters on its branches, same memory stars, crowns and countdowns.
2. Its title is always "Our tree" (`preset: ourTree`). It can get a place (by agreement) and a look (directly). Species for Our tree: oak, cherry (blossom) or banyan only, because letters hang from its limbs.
3. It can never be removed.
4. **New couples** (no start date): planting Our tree means agreeing on the start date. One partner sends `seed_our` (the start day, optionally a place, a look and a note); the other plants it. Planting writes `config` in the exact 1.2 format, so a partner on 1.2 sees the tree too.
5. **Existing couples**: Our tree already counts as planted by both. No consent step. The first garden client online records it (A9).

### A3. Planting a tree

**A seed contains**: what it stands for (a preset and a title of at most 40 graphemes), optionally a place, optionally the day of the moment (Our tree: the start date, required), a look (scene and species, suggested from the place), and an optional note of at most 140 graphemes.

| Preset | Default title | Look when no place category decides | Prefill the day from |
|---|---|---|---|
| `firstMet` | Where we first met | Meadow | — |
| `firstDate` | Our first date | City Lights | First Date memory |
| `firstTrip` | Our first trip | Mountain Lake | First Trip memory |
| `saidLove` | Where we said “I love you” | City Lights | — |
| `firstHome` | Our first home | Home | Moving Together memory |
| `engaged` | Where we got engaged | City Lights | Proposal memory |
| `wedding` | Where we got married | Lantern Town | Wedding memory |
| `ourPlace` | Our place | Meadow | — |
| `custom` | (typed, placeholder "Our rainy café") | Meadow | — |

Sending a seed is a transaction (it needs a connection, like every answer): offline the send button is disabled and the sheet says "You're offline. Planting needs a connection so you both see the same tree."

The **proposer** can, until the seed is planted:
- **Edit** it (a transaction; needs a connection). Silent: no push.
- **Take it back** (deletes it). If the partner planted it a moment earlier: "Too late, Sam planted it just now 🌳" and the ceremony plays.

The **partner** can:
- **Hold to plant together** (press and hold 0.6 s; one activation for VoiceOver, Switch Control, Voice Control). Plants exactly the version the partner saw (its `rev` and the server time `at` of that version, `GardenProposalVersion`); if the proposer edited it meanwhile, or took it back and sent it again: "Sam just changed this. Take another look."
- **Suggest a change** (counter): their version replaces the seed, they become its proposer (`by`), `rev + 1`, and the first partner must answer. Push to the first partner.
- **Not now**: collapses the card for 3 days on this device only. Nothing is sent.
- **Let this seed go** (sheet menu): deletes it. No push. The proposer later sees one quiet line: "Sam set aside your seed for “Our first trip”. You can plant another anytime."

**Both proposing at once**
- Our tree: one fixed id, `seed_our`, created in a transaction that reads it first. Whoever lands second sees the other's seed: "Sam sent one at the same moment. Here it is." Once the start date exists, `seed_our` is void (the rules refuse to plant it) and the first client that sees it deletes it.
- Place trees: two seeds coexist. When both seeds share a preset, the seed sheet says "You both suggested “Our first date”." and offers **Plant Sam's**, which plants theirs and deletes yours in the same transaction.
- Start date, change, rest: one fixed id each (`startdate`, `change_<slot>`, `rest_<slot>`); the second sender sees the first one and may counter it.

**Limits**
- 8 trees in all (Our tree + 7). A slot is assigned when a seed is **planted**, never when proposed (the planting transaction takes the first free `tree_pN`). Full: "Your garden has 8 trees. Let one rest to plant another."
- At most 3 open seeds per person, enforced by the rules by construction: a place seed's id is `seed_<creator uid>_<1|2|3>`, a member may create only their own three ids, and the sending transaction takes the first free number. With all three open: "You have 3 seeds waiting for Sam. Take one back to send another." (`GardenError.tooManySeeds`). A counter keeps the id.
- A place seed needs a start date (the garden starts with Our tree).
- A moment's day cannot be in the future (picker `...today`; the rules allow up to +2 days for time zones).

**How a place tree grows**: from the day it is planted, through the same stages as Our tree: every place tree starts as a seed, whatever its moment's day (0.0 #3). The moment's day is remembered, not grown from: it shows on the postcard and in the title line ("Our first trip · 12 March 2023"). The planting ceremony shows the seed sprouting, never a time-lapse through years.

**Who planted it**: the tree records both people and the server time: "Planted by Alex and Sam on 14 Nov 2026".

### A4. Changing a tree, and changing the start date

- **Identity** (title, preset, place, moment's day) changes only by agreement: one pending `change_<slot>` per tree, carrying the tree's full intended content (look included). Same edit / take back / counter / carry-out rules as seeds. Pushes on create, counter and agreement.
- **Look** (scene, species) changes directly by either partner, any time. The other sees one quiet line for 24 h: "Sam gave “Our tree” a new look." with **Change it back** (itself a direct change).
- **The start date** changes only by agreement: "Since 26 Jan 2026 · Edit" opens **Suggest a new start date**. While it waits the day count does not move. The partner answers **Agree** (with a confirmation naming the new day and day count) or **Keep 26 Jan**. A suggestion names the date it was made against (`fromStartDay`); it is void the moment `config.startDate` changes any other way (a legacy partner's direct edit). Agreeing to a void one is refused by the rules ("The start date changed since Sam suggested this."), and the first client that notices deletes it.

### A5. Letting a tree rest

- Place trees only. Either partner asks **Let this tree rest** (`rest_<slot>`). The other answers **Let it rest** (the tree and the request are deleted in one transaction; its place goes with it) or **Keep it** (the request is deleted). The asker can withdraw.
- Its waterings stay in the journal (they belong to the garden).
- Push only on the request ("Sam asked to let a tree rest"), never on the outcome.

### A6. Watering

**One shared clock.** `L` = server time of the latest watering by either partner (on screen my own pending watering counts as "now"; reminders use confirmed waterings only, H).
- **The garden's state** — the status line, the water action and its CTA, `GardenPrimaryAction.resolve` (and so the masthead +'s fill), the VoiceOver water value, Home's row and the local reminders — is `GardenWaterState.garden(lastWateredAt: L, now:)`: hours since `L` alone. Nothing in it depends on the selected page, so swiping between a just-planted tree and a thirsty Our tree changes no control and no fill.
- **A tree's look** (`GardenTreeVisual.forTree`) only ever adds to its plain look (0.0 #3): dew and wet soil use `t = now − max(L, plantedAt)`, so a tree planted after the last watering shows its planting's wet soil and dew while the garden can still read "A little thirsty"; **lushness**, the watering's reward, uses the same `t` but only for a watering at or after the tree's planting (a tree nobody has watered since it was planted has none). The tree never droops and its soil never pales or cracks (`GardenTreeLook.withersWhenThirsty = false`).

| State | hours since `L` (garden) / `t` (one tree's look) | Tree | Status line (B3) |
|---|---|---|---|
| Not watered yet | no watering ever | plain | "Not watered yet" |
| Fresh | 0 ≤ t < 48 | lush (greener, fuller, glossier) for 24 h, easing back to plain by 48 h; dew while t < 6; wet, darker soil while t < 12 | "Watered by Sam · …" (B3 table) |
| Ready for water | 48 ≤ t < 72 | plain | "Ready for water · last drink …" |
| A little thirsty | 72 ≤ t < 168 | plain | "A little thirsty · last drink …" |
| Resting | t ≥ 168 | plain | "Resting · a little water wakes it up" |

With `GardenTreeLook.withersWhenThirsty = true` the old look returns: ready pales the soil; thirsty droops to 0.5 with colours 25% softer, a few leaves down and hairline soil cracks; resting droops to 1.0, closes blossoms into buds and softens colours 40% (C6).

Watering never changes the day count, stage, crowns, anniversaries or letters. A tree never dies, droops or dries.

- **One tap waters every planted tree.** No per-tree watering.
- **Once per person per 12 hours**, enforced by the rules on server time (after 11 h 50 min, so a phone a few minutes off is never refused). While locked the hero shows no water control and the status says "You watered today at 9:14 PM".
- **Watered together**: two waterings by the two partners within 24 h of each other (server times). The second plays the `together` effect, its push to the first partner says "You watered together 💧", and a faint rainbow stays over the garden for 24 h on both phones. No counter of togetherness anywhere.
- **Water back**: the partner watered < 24 h ago and I have not since ⇒ the CTA says **Water back**.
- **The rain returns**: a watering ≥ 7 days after the previous one plays `rainReturns`; its push says "Sam woke up the garden 🌧️". Nothing says how long it was.
- **First water**: the garden's very first watering opens with a golden first drop.
- **Offline**: watering works; the effect plays at once; after 3 s pending the status says "Watering… it reaches Sam when you're back online"; the server stamps the time on arrival. A queued watering the server later refuses (another device watered within 12 h) disappears and leaves the notice "Your watering at 9:14 PM didn't go through." · **Water again**.

### A7. The note

- Optional, plain text, 100 graphemes and ≤ 400 UTF-8 bytes, one per watering, written before watering (it travels with the push, so it is never edited). Whitespace-only is no note.
- Suggestion chips by local time: always "Thinking of you", "Miss you", "Proud of us", plus "Good morning ☀️" (05:00–11:59) or "Good night 🌙" (21:00–04:59) or "See you soon" (otherwise).
- The partner finds it in: the push; a paper tag on the selected tree until they read it; the hero's status well for 48 h or until they water; Home's row for 24 h; the journal forever.
- Tapping the note: **Water back** (when allowed) and **Reply in Chat** (switches to Chat; sends nothing).

### A8. Who can do what

| Action | Who | When | Enforced by |
|---|---|---|---|
| Send a place seed | either, online | start date exists; < 8 trees; ≤ 3 open seeds of mine | rules (shape, author, server time, config exists, id `seed_<me>_1…3`); transaction (picks my first free number) |
| Send Our tree's seed | either | no start date; no `seed_our` yet | rules (fixed id, `!exists(config)`); transaction |
| Edit my seed / request | its current proposer | until carried out | rules (`by == me`, `rev+1`); transaction (still mine, rev unchanged) |
| Take my seed / request back | its proposer | until carried out | transaction (detects "already planted") |
| Suggest a change (counter) | the other partner | while it waits | rules (writer becomes `by`, `rev+1`); transaction |
| Plant / agree / let rest | the other partner, on a garden build | while it waits, exactly as seen | rules (`plantedFrom`, `changedFrom`, `startDateFrom`, rest delete); transaction (rev) |
| Let go / keep | the other partner | while it waits | rules (any member may delete a proposal) |
| Change a look | either | any time | rules (look-only diff) |
| Water | either | Our tree exists; ≥ 11 h 50 min since my last | rules (`waterer_<me>` turn) |
| Record Our tree / a legacy start date | either garden client | start date exists | rules (`recordedLegacy`, `reRecorded`, ±1 s) |
| Set the start date directly | a legacy client only | any time | the existing open rule on `config`, unchanged |
| Purge everything | either member | couple disconnected | rules (`isDisconnectedCouple`) |

### A9. What existing couples see on first launch of the garden build

For a couple whose start date is set:
1. **Nothing is lost or moved.** Same day count, stage, letters, stars and crowns. Our tree counts as planted by both.
2. **The hero changes shape.** The same tree (oak, same pixel size, same silhouette) now stands on a knoll in the **Meadow** at the current time of day, across the full width of the hero; the words sit under the picture. A one-time reveal: the scene fades in behind the tree and the sun or moon rises into place (0.8 s; a crossfade under Reduce Motion).
3. **The filled CTA is "Give it its first water"** (state "Not watered yet": no droop, no guilt). The masthead + turns outlined.
4. **One card, once: "Give your tree a home"**, with **Choose a place** and **Not now**. "Not now" hides it for good; the band then shows a quiet "Add a place" chip.
5. **No push because of the update.** The partner hears about the garden the first time it is watered, and only if their token device runs a garden build.
6. The garden client records Our tree (`tree_our`, `origin: legacy`, Meadow, oak) in a transaction the first time it is online; until then (offline first launch) the tree is drawn from the start date alone.

Couples without a start date see **Plant your first tree together** (B3.2).

### A10. A partner on a legacy build

The garden client knows from `users/{partner}.capabilities.garden` (written by every garden build at launch; legacy builds never write it and their `setData(merge:)` never removes it).

| A legacy partner… | Result |
|---|---|
| opens Journey | The pre-garden Journey: same tree and start date, memories (and letters on 1.3). No garden, places, waterings or pushes. |
| sets or edits the start date directly | Allowed, as today. Day counts follow `config` everywhere at once. The garden client shows "Your start date was changed to 10 March 2023 in an older version of Coupley." with **OK** (records it; A4). A pending `startdate` suggestion is void. If there was no start date, Our tree is simply planted; a pending `seed_our` is void, and its place and look are kept on the proposer's phone and offered again as a "Give your tree a home" request. |
| receives garden pushes | Never (the token gate). |
| can answer seeds | No. The garden client says "Sam needs the latest Coupley to plant together." with **Tell Sam**: a confirmation shows "🌱 I'd love to plant a tree with you on Journey. Update Coupley to see it." and sends it to Chat only after **Send**. Seeds wait and become answerable the day Sam updates. |
| is watered for | Watering works alone; it needs no answer. The post-watering line omits "Sam will see it". |
| runs "Delete shared data" or deletes the account | 1.2 deletes the whole `timeTreeMeta` collection (garden and places included); `onCouplePurged` deletes anything left when the couple document goes. |
| writes garden documents | Never; legacy code only touches `config`. |
| is affected by the new rules | No: `config` keeps its open rule and no other path a legacy app uses changes. |

Whether a garden user may set the **first** start date alone while the partner is on a legacy build is open question **Q2** (default: no; the legacy partner can still set it from their side, which plants Our tree).

### A11. Availability (what the garden does when something is missing)

| State | Trigger | What the user sees | Writes |
|---|---|---|---|
| `ready` | probe returned enabled (or verified earlier on this install) and listeners healthy | the garden | allowed |
| `loading` | first answers pending | the hero draws Our tree from the anchor; status "Checking the garden…"; no water control | none |
| `unavailable(.rulesMissing)` | `appConfig/garden` get → permission-denied | Our tree in its scene (cached look or Meadow), status "The garden isn't available right now. Your trees are fine.", no water control, requests hidden; without a start date: the title "Plant your first tree together" and the line "Planting together isn't available right now. Try again later." with **no button** (a disabled hero `BrandCTA` still paints a 35% accent fill, a second accent beside the filled masthead +). Retries on foreground. | none |
| `unavailable(.listenerFailed)` | a garden listener errors | same as above; retries on foreground and after 3, 6 and 9 s (the letters' pattern) | none |
| `unavailable(.neverOnline)` | first launch offline, probe never succeeded on this install | same as above, status "Connect once to start your garden." | none |
| `disabledRemotely` | `appConfig/garden {enabled: false}` | the pre-garden Journey exactly (old hero, direct start-date sheet) | none to garden docs |
| functions not deployed | — | everything works; no pushes; no copy claims a push was sent | allowed |

The garden never falls back to planting alone. Every write is a confirmed write (≤ 2.5 s) or a bounded transaction (≤ 10 s), so nothing hangs.

---

## B. UX

### B0. Where the garden lives

- **Journey** is its home: the hero becomes the garden; requests waiting for *me* sit right under it; every sheet opens from Journey's NavigationStack, one at a time (the file's existing rule).
- **Home**: one quiet ambient row (B7). No hero, no pin (the letters own T0b), no tab badge.
- **Chat**: nothing automatic. Two user-initiated bridges: **Reply in Chat** (switches tab) and **Tell Sam** (a message the user confirms and sends).
- **Pushes and reminders** open Journey at the right tree, note or request (`JourneyFocus.garden(GardenFocus)`).
- **No thirst anywhere outside Journey**, no badge, no streaks.

### B1. Journey, top to bottom

```
Masthead          "Journey" + tally ("4 trees · 12 memories · 2 letters") + the + button
Error strip       existing; garden action errors use it too
HERO              the garden band + caption (B3), or a planting hero (B3.2–B3.4)
Requests          cards for what waits for ME (B4), at most 2 + "1 more request"
Quiet zone        one ruled block: what waits for Sam, one-time notices, the "home" invite card
Countdown block   existing, unchanged (TimeTreeHeader with showsHero: false)
Letters           existing
Timeline          existing
```

Tally: trees appear only from 2 trees, first ("4 trees · …"). Without a start date the subtitle is "Plant your first tree together" (my seed waiting: "Waiting for Sam to plant your tree"; Sam's seed waiting: "Sam sent you a seed").

### B2. One filled CTA per screen (`GardenPrimaryAction.resolve`, in the contract)

The design system allows one filled accent per screen; today it is the masthead +. Without a start date the + is **outlined, not hidden** (current code: `addButton(filled: viewModel.anchor != nil)`).

| Condition (evaluated top to bottom) | Filled control | Masthead + |
|---|---|---|
| `disabledRemotely` | (pre-garden Journey) | as today |
| `unpaired`, `loading` or `unavailable(…)`, with or without a start date | none: the hero shows **no CTA at all** (text only), never a disabled one | filled |
| No start date, no seed (garden ready) | hero **Plant a seed** | outlined |
| No start date, Sam's `seed_our` waits for me | hero **See Sam's seed** | outlined |
| No start date, my seed waits | none (text buttons only, B3.3) | filled |
| Start date, garden water action ∈ {first water, water back, due} | hero water CTA | outlined |
| Otherwise | none (hero shows an outlined "Water now" when allowed) | filled |

The water action comes from the garden's state (A6), never the selected page, so paging never moves the fill. `GardenPrimaryAction.emptyHeroShowsButton(availability:)` (contract) is false in every non-ready state; M3 checks every row, including each unavailable reason with and without a start date.

- The outlined + keeps its 44 pt target (34 pt circle, `Brand.surfaceLight` fill, 1 pt accent stroke at 45%, accent glyph). Accessibility label: "Add a memory, a letter or a tree".
- Request cards and the invite use outlined `BrandCTA(tier: .card)` and text buttons; every sheet has exactly one filled CTA pinned in `safeAreaInset(edge: .bottom)` (like `AnchorSetupSheet`), except the seed sheet, whose one fill is the custom **Hold to plant together** control.
- `BrandCTA` uses the fixed `BrandType.cta` (17 pt) and a fixed 52/44 pt height: every CTA label here is ≤ 24 characters so it never truncates at 307 pt; `BrandCTA` is not changed.

### B3. The garden hero

```
╭ hero card (BrandCard .hero, insetsContent: false) ─────────────────────╮
│╭ band: full bleed, top corners = Brand.heroCornerRadius ─────────────╮│
││ (⌖ Café Giảng)                                         (🌳 4 •)    ││ chips: SwiftUI overlays
││   sky · celestial · far layer (parallax 0.35×) · near layer        ││
││   landmark (left third)                 tree on the knoll (x .62)  ││
││   front grass over the trunk base                                  ││
││                         ● ━ ● ●                                    ││ page dots (≥ 2 trees)
│╰───────────────────────────────────────────────────────────────────╯│
│  291                                              Blooming ⓘ          │ row 1
│  days together                                                        │
│  ╭───────────────────────────────────────────────────────────────╮    │
│  │ 💧 Sam watered today at 9:14 PM                                │    │ row 2: status well
│  │ “Thinking of our first coffee.”  Sam · today at 9:14 PM        │    │ (wellBackground .hero)
│  ╰───────────────────────────────────────────────────────────────╯    │
│  [ 💧  Water back                                    ] [ ✎ ]           │ row 3: CTA + note
│  Since 26 Jan 2026 · Edit                                             │ row 4: meta
╰──────────────────────────────────────────────────────────────────────╯
```

**Band**: 208 pt; 176 pt when the scroll viewport is under 700 pt (the existing `treeHeight` switch); 168 pt at accessibility text sizes. Pager: horizontal `ScrollView` + `LazyHStack(spacing: 0)` + `.containerRelativeFrame(.horizontal)` + `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`; Our tree first, then place trees by `plantedAt`. The selected page survives tab switches (stored per couple, `GardenDefaultsKey.selectedSlot`).

**Band overlays** (SwiftUI, never drawn in a canvas):
- **Place chip**, top-leading, 12 pt inset, max width 44% of the band, `JourneyFont.caption`, `.regularMaterial` capsule with a 1 pt white 25% stroke (`Brand.surfaceLight` solid under Increase Contrast), SF Symbol `mappin`:
  - Our tree with a place: "Café Giảng"; place tree with a place: "Where we first met · Café Giảng" (the title truncates first); place tree without a place, or Our tree without a place after the invite card is answered: "Add a place" (an action: opens the change flow); Our tree without a place before that: no chip.
  - Tap (with a place): the tree's postcard.
- **Garden chip**, top-trailing, 36 pt frosted circle with `tree.fill`; the tree count beside the glyph from 2 trees; a 7 pt amber dot when a request waits for me. Tap: the Garden sheet. Label: "Your garden, 4 trees, 1 request waiting".
- **Page dots**, bottom-centre on a frosted pill, 8 pt from the bottom edge, only with 2+ trees; selected dot is a 16×6 capsule; a dot gets a 5 pt amber ring when that tree has a request waiting for me.

**Row 1**: Our tree: the day count (`JourneyFont.number`) and "days together", exactly as `TimeTreeHeader` shows it today: the caption is the plural key `"\(days) days together"` (`TimeTreeHeader`'s own entry and comment, so its one/few/many forms are already translated) with the number taken out by `CountedCaption.removingCount`. A place tree: the days since it was planted (it grows from its planting day, 0.0 #3) and "days since you planted it", from its own plural key `"\(days) days since you planted it"` (comment: keep `%lld` in every plural form; the app removes the number), through `removingCount` the same way. VoiceOver reads the full counted string ("291 days together"), never a number glued to a caption. No caption is picked with `days == 1`: a key without the count cannot agree with it in Russian, Ukrainian, Polish, Czech, Arabic or Hebrew (review L10N-1), so the `isOne` helpers (`GardenPreset.sinceCaption(isOne:title:)`, `GardenPreset.plantedCaption(isOne:)`) are gone. Trailing: the stage button (`Blooming ⓘ`) opening the tree guide for that page's tree (B6): Our tree's guide counts from the start date; a place tree's says "This tree grows from the day you planted it. Today is day 12." ("…, starting today." on its planting day) and keeps only the colours row under **What grows on it**, since stars, letters, blossoms and crowns are Our tree's (C5). At accessibility sizes the number, label and stage stack.

**Row 2, the status well** (`wellBackground(in: .hero)`): drop glyph + status line; then, when the partner's latest note is < 48 h old and I have not watered since, the note in quotes and "Sam · today at 9:14 PM" (two lines max; one line in compact mode). Tap: the journal. When the partner's watering is first seen, the line is tinted with the accent for 2 s.

| Situation (first match wins) | Status line |
|---|---|
| garden loading | "Checking the garden…" |
| garden unavailable | "The garden isn't available right now. Your trees are fine." |
| never watered | "Not watered yet" |
| my watering pending > 3 s | "Watering… it reaches Sam when you're back online" |
| latest pair watered together and latest < 48 h | "Watered together · today at 11:02 PM" (the later time) |
| I watered < 12 h ago, Sam not since | "You watered today at 9:14 PM" |
| Sam watered < 24 h ago, I have not since | "Sam watered today at 9:14 PM" |
| fresh (< 48 h), otherwise | "Watered by Sam · Wed, Nov 12 at 9:14 PM" / "Watered by you · …" |
| ready | "Ready for water · last drink Tue at 9:14 PM" |
| thirsty | "A little thirsty · last drink Sun at 9:14 PM" |
| resting | "Resting · a little water wakes it up" |

Every row is garden-level (A6): it never changes while the user swipes between pages. All times are server timestamps formatted with `FutureLetterClock.moment(_:now:)` ("today at 9:14 PM", "yesterday at 8:02 AM", "Thu, Nov 13 at 9:14 PM").

**Row 3, CTA + note**:

| Water action | Control | Label |
|---|---|---|
| first water | filled `BrandCTA(tier: .hero)` | "Give it its first water" |
| water back | filled | "Water back" |
| due (ready/thirsty/resting) | filled | "Water your tree" (1 tree) / "Water all 4 trees" |
| optional (fresh, cooldown over) | outlined `BrandCTA(tier: .card)` | "Water now" |
| locked / none | no control | — |

- Icon `drop.fill`; busy: spinner.
- The ✎ button sits beside any water control: 52×52 outlined beside a filled CTA, 44×44 beside an outlined one; label "Add a note"; a filled dot on it when a note is drafted. It opens the water-note sheet (B5.6). At accessibility sizes the water control and "Add a note" become two full-width rows.
- After the tap, row 3 is replaced for 4 s by: "Watered all 4 trees. Sam will see it on Journey." (1 tree: "Watered. Sam will see it on Journey."; partner on a legacy build: "Watered all 4 trees." / "Watered."). VoiceOver announces the same. No copy anywhere says a push was sent.

**Row 4, meta** (`JourneyFont.meta`): Our tree "Since 26 Jan 2026 · Edit" (Edit opens the start-date sheet in suggest mode); with my suggestion waiting: "Since 26 Jan 2026 · New date suggested". A place tree: "Planted together 14 Nov 2026 · Details" (Details: the postcard).

**Compact mode** (viewport < 700 pt): band 176 pt, the note one line. Height budget at 375×667 (viewport ≈ 598 pt): masthead ≈ 71 + 14 + hero ≈ 176 + 247 = 423 ⇒ the countdown block's first row starts at ≈ 522 pt, on the first screen when no request card is showing. Measured on device in K3.

#### B3.1 Loading and unknown start date

While Journey's first load runs: the existing "Loading your Journey…". While the start date is unknown (`isStartDateKnown == false`): the existing "Loading your tree…" hero. Neither offers anything it can't save.

#### B3.2 No start date, no seed: "Plant your first tree together"

- Band: Meadow at the current time of day, a bare soil mound on the knoll, no tree.
- Title (`JourneyFont.title`, header trait): "Plant your first tree together"
- Body: "Choose the day your story began, and if you like, the place. Sam plants it with you."
- Filled CTA: **Plant a seed** (`leaf.fill`) → plant sheet, Our tree mode.
- Partner without the capability: an extra line "Sam needs the latest Coupley to plant together." and a text button **Tell Sam**. The seed can still be sent; it waits.

#### B3.3 My first seed waits

- Band: the mound with a small wooden stake and a paper tag.
- Title: "Waiting for Sam"
- Body: "Your seed for 12 March 2023 is with Sam. It's planted when Sam says yes."
- Text buttons **Edit seed** · **Take it back** (confirmation "Take this seed back?" / **Take it back** / **Cancel**). No filled CTA. Legacy partner: the Tell Sam line.

#### B3.4 Sam's first seed waits for me

- Band: the seed packet resting on the mound, a 2 s breathing glow while live.
- Title: "Sam sent you a seed"
- Body: "For the day your story began: 12 March 2023." then Sam's note in quotes, if any.
- Filled CTA: **See Sam's seed** → seed sheet (B5.2), where planting happens.

#### B3.5 Unavailable

See A11. The band still draws Our tree (scenes are client-side). No water control and no CTA of any kind (without a start date the planting hero shows only its title and the unavailable line), requests hidden, meta's Edit shows "Changing the start date isn't available right now." on tap. Retries are automatic; no "Try again" button competes with Journey's own error strip.

### B4. Requests under the hero, and the quiet zone

Each request for me is a `BrandCard(tier: .card)`; order: start date, rest, seeds, changes; at most 2 shown, then a text button "1 more request" / "2 more requests" opening the Garden sheet. Snoozed ("Not now") seeds collapse into the quiet row "1 seed from Sam · See".

**Seed from Sam** (place tree)
- Left: a 56×72 pt seed packet (kraft `#D9B98C`, flap `#C9A574`, stamp = the scene's SF Symbol).
- Title: "A seed from Sam"
- Line 1: "“Our first trip” · Đà Lạt" (place part omitted when none; the place's locality or name).
- Line 2: Sam's note, one line, in quotes.
- Outlined **See the seed** · text **Not now**.

**Change from Sam**: title "Sam suggested a change"; line "To “Our first trip”: the place and the day." (lists what differs: "the name", "the place", "the day", "the look"); outlined **Take a look** (seed sheet, change mode).

**New start date from Sam**: title "Sam suggested a new start date"; line "10 March 2023 instead of 12 March 2023."; line "Your day count would be 1,344."; outlined **Agree** → confirmation "Change your start date to 10 March 2023?" / "Your tree, anniversaries and crowns will count from that day, for both of you." / **Change it** / **Cancel**; text **Keep 12 March**.

**Rest request from Sam**: title "Sam would like to let a tree rest"; line "“Our first trip” leaves your garden if you agree. Its waterings stay in the journal."; outlined **Let it rest** (leaf-fall as the tree fades; Reduce Motion: fade); text **Keep it**.

**Quiet zone** (one ruled `.quiet` block; inner rows `showsRule: false`):
- What waits for Sam: "Waiting for Sam · your seed for “Our first trip”" (chevron → my seed sheet); several: "Waiting for Sam · 2 seeds"; a start date: "Waiting for Sam · new start date 10 March 2023".
- Partner without the capability: "Sam needs the latest Coupley to answer · Tell Sam".
- Notices (one at a time, **OK** dismisses, seen-state per device):
  - "Sam set aside your seed for “Our first trip”. You can plant another anytime."
  - "Your start date was changed to 10 March 2023 in an older version of Coupley." (OK records it)
  - "Sam gave “Our tree” a new look." · **Change it back** (24 h)
  - "Your watering at 9:14 PM didn't go through." · **Water again**
- The invite, once (a `.card`, not quiet): title "Give your tree a home"; body "Your tree can stand somewhere that matters to you both, like the place you first met. You choose it together."; outlined **Choose a place**; text **Not now**. For a couple whose `seed_our` was voided by a legacy planting, the invite opens prefilled with that seed's place and look.

### B5. Sheets (one at a time, from Journey's NavigationStack)

All Journey garden sheets go through one `.sheet(item: $gardenSheet)` route in `TimeTreeView` and are included in `isJourneySheetPresented` / `closeJourneySheets`; hand-overs happen in `onDismiss`, never while a sheet is up. The place picker, the look picker, the journal and the live map are **pushed** inside a sheet's own NavigationStack.

#### B5.1 Plant sheet (`GardenPlantSheet`, P9)

Modes: new place tree · Our tree's first planting · edit my seed · counter Sam's seed · change a planted tree · edit my change.

| Part | Copy |
|---|---|
| Nav title | "Plant a tree" · "Plant your tree" · "Edit seed" · "Your version" · "Suggest a change" · "Edit your suggestion" |
| Cancel | "Cancel" (top leading) |
| Live preview | the chosen look with a sapling (or the tree for a change), the place chip, a still frame |
| Stands for (place trees) | header "What does it stand for?"; preset chips (A3); field "Name", placeholder "Our rainy café" (custom), 40 graphemes |
| Start date (Our tree) | header "When did your story begin?"; graphical `DatePicker` `...today`, default 3 months ago (as today's sheet) |
| Place | header "Where is it?"; row **Add a place** "Search or drop a pin. Optional." → place picker (D1); chosen: 96×64 snapshot, name, locality, "Exact spot"/"The area", **Change** · **Remove** |
| Day (place trees) | header "When was it?"; date row `...today`; toggle "We're not sure of the day" (no footnote: every tree grows from its planting); prefill hint "From your Timeline: 14 Feb 2024" (tap to use) |
| Look | header "How should it look?"; carousel of the 8 scenes (swatches 96×64 + name), the suggested one first with "Suggested for a café" (or "for this place"); species chips (Our tree: Oak · Blossom · Banyan; place trees: + Pine · Palm) |
| Note | header "A note for Sam"; placeholder "Why this place?"; 140 graphemes; optional |
| Filled CTA | **Send the seed to Sam** · **Save seed** · **Send your version** · **Suggest this to Sam** · **Save suggestion** |
| Footer | "Nothing is planted until you both say yes." · counter: "Sam sees your version and plants it, or answers with theirs." · change: "It changes when Sam agrees." |
| Disabled hint | "Choose the day your story began." (Our tree) · "Give it a name." (custom without a title) · "You have 3 seeds waiting for Sam. Take one back to send another." (new place tree with 3 of mine open) |
| Inline errors | from `GardenError.message` (offline, full, tooManySeeds, partnerProposedFirst, …) |

Every mode needs a connection (each is a transaction); offline the filled CTA is disabled and the offline line shows under it. The Name field starts with the preset's localized title; left unchanged it stores the preset's base-language default (`GardenDraft.storedTitle`), so each partner reads the title in their own language.

#### B5.2 Seed sheet (`GardenSeedSheet`, P9)

**Sam's seed**
- Nav title "A seed from Sam"; **Close**; menu (…) **Let this seed go** → "Let this seed go?" / "Sam won't be told, and can send it again." / **Let it go** / **Cancel**.
- The seed packet (180 pt): kraft paper, a cream label with the title (`JourneyFont.title`), a stamp with the scene symbol, a postmark with the day ("12 MAR 2023").
- Rows: **Stands for** "Our first trip" · **Place** name, locality, 120 pt snapshot (tap: postcard) · **Day** "12 March 2023" or "From the day you plant it" · **Look** "Seaside · Palm" with a swatch · **From Sam** the note.
- Growth line: "It will be a Fruiting tree the day you plant it: it has been growing since 12 March 2023." (no day: "It starts as a seed the day you plant it.")
- Duplicate: when I have an open seed with the same preset, a line "You both suggested “Our first date”." and the plant control reads **Hold to plant Sam's** (plants theirs and deletes mine).
- Bottom: the custom **Hold to plant together** (a ring fills around a seed glyph in 0.6 s; soft haptic on touch-down, rigid on completion; releasing early rewinds in 0.2 s; VoiceOver label "Plant it together", one activation plants); outlined **Suggest a change**; text **Not now**.
- Errors under the control: `GardenError.message` ("Sam just changed this. Take another look." · "Sam took this back." · "Your garden has 8 trees…" · offline · timed out).
- Success: the sheet closes; the planting ceremony plays (C8).

**My seed**: title "Your seed"; "Waiting for Sam since today at 9:14 PM"; outlined **Edit seed**; text **Take it back** (confirmation as B3.3). Legacy partner: the Tell Sam line.

**Change / start date / rest** reuse it: titles "Sam suggested a change" (rows show "was → now" per changed part), "Sam suggested a new start date", "Let “Our first trip” rest?". The sheet's one filled control is **Agree** (`BrandCTA(tier: .hero)`; the start date asks the B4 confirmation first; rest reads **Let it rest**); text **Keep it as it is**. For my own request: outlined **Edit**, text **Take it back**.

#### B5.3 Place picker

See D1 (pushed inside the plant form).

#### B5.4 Postcard (`TreePostcardView`, P9; a sheet from the place chip, or pushed from the Garden sheet)

- Title: the tree's title. A 3:2 map snapshot framed as a postcard: a perforated stamp (the scene swatch) at top right, a round postmark rotated −12° with the moment's day ("LISBON · 12 MAR 2024" for an exact place, "12 MAR 2024" for an area), Apple Maps attribution (D5).
- Rows: place name (`JourneyFont.title`), locality, "The moment: 12 March 2024 · 2 years ago", "Planted: Together · Sat 14 Nov 2026" (recorded Our tree: "Growing since 26 Jan 2026"), "Growth: Fruiting", "Look: Seaside · Palm · **Change**".
- Buttons: outlined **Open in Maps** (only with a place); text **Suggest a change** (pushes the plant form in change mode), **Let this tree rest…** (place trees: confirmation "Ask to let “Our first trip” rest?" / "It stays in your garden until Sam agrees. Once it rests, it's gone for both of you, with its place." / **Ask Sam** / **Cancel**).
- Pending: mine "You suggested a change. Waiting for Sam. · Take it back"; theirs "Sam suggested a change · Take a look".
- No place: "No place yet" and outlined **Add a place**.
- **Change the look** pushes the look picker: a 2-column grid of the 8 scenes (swatches, the current one ringed), species chips, filled **Save look**, footer "Sam sees the new look right away."

#### B5.5 Garden sheet (`GardenSheet`, P10)

Opened from the garden chip, the masthead tally or a push about the garden in general. Title "Your garden"; **Done**.
- **Trees**: a horizontal shelf of 96×120 "terrariums" (scene swatch + a still tree canvas at its stage and look, lush after a watering and plain otherwise, name under it, a drop badge when fresh), tap → postcard (pushed); last cell a dashed **Plant a tree** (hidden at 8 trees).
- **Waiting**: request rows (same copy as B4), tap → the request (pushed seed view).
- **Places**: a row of 56×56 snapshots, then **Open the map** → `GardenMapView` (pushed, D5). No place yet: "None of your trees has a place yet. Add one from a tree's card."
- **Watering**: the latest 5 journal entries, then **See every watering** → journal (pushed).
- Filled CTA: **Plant a tree** (hidden at 8 trees with the footer "Your garden has 8 trees. Let one rest to plant another.").
- Loading: 3 skeleton terrariums. Listener failure: "Couldn't load your garden. Check your connection and try again."

**Journal** (pushed): title "Garden journal"; subtitle "Every watering, and the notes you left."; grouped by month ("November 2026"); rows "Sam · Thu, Nov 13 at 9:14 PM" + the note in quotes; two waterings that were together share a group with a twin-drop glyph and "Together"; when the partner's time zone differs, a second meta line "11:14 PM for Sam"; pages of 50 by `wateredAt`; footer "That's every watering since your first."; empty "No waterings yet. The first drop starts the journal."

#### B5.6 Water-note sheet (`WaterNoteSheet`, P10)

Opened by ✎ (or a long-press on the water control → "Water with a note"). Detents `.height(320)` and `.large`.
- Nav title "Water with a note"; **Cancel**.
- Chips (A7), tap to fill; field placeholder "A few words for Sam (optional)"; counter "86/100" from 80 graphemes.
- Filled CTA **Water with this note** (disabled while the water action is `locked`/`none`).
- Footnote "Sam sees your note on Journey." (legacy partner: "Sam will see it after updating Coupley.").
- The sheet closes first; the watering and its effect start in `onDismiss`.

#### B5.7 Start-date sheet, suggest mode (`AnchorSetupSheet`, P9)

- Nav title "Start date"; heading "When did it begin?"; body "Pick the day your story began. It changes when Sam agrees too."
- Graphical picker (existing), note field "A note for Sam (optional)" (140 graphemes).
- Filled **Suggest this date**, disabled while the day equals the current one.
- Footer "Your tree keeps growing from 26 Jan 2026 until Sam says yes."
- Legacy partner: footer "Sam's Coupley is out of date, so Sam can't agree yet." + text **Tell Sam**; the button stays enabled.
- Attribution footnote: "Agreed together on 14 Nov 2026" when `tree_our.agreementKind == startDate` or `plant`, else today's "Set by … on …".
- With `GardenFeature.isEnabled == false` or `disabledRemotely`: today's direct-save sheet, unchanged.

#### B5.8 Planting ceremony (`PlantingCeremonyOverlay`, P8)

Full screen over Journey (zIndex 900, after any crown overlay), conventions of `CrownCelebrationOverlay` (0.75 black dim, `.isModal`, escape action, `.screenChanged` on appear, room for the ad banner):
- Title: "Planted together" (Our tree's first planting: "Your tree is planted").
- Subtitle: title and place ("Where we first met · Café Giảng").
- Line: place tree "Planted 14 Nov 2026 · for 12 March 2023" (the moment part only when a day was given) / "It starts growing today." / Our tree: "It grows from 12 March 2023."
- Meta: "Planted by Alex and Sam · 14 Nov 2026" (server time; "just now" while pending).
- Button: **See it in your garden**. Tapping outside the words skips to the end.
- Plays once per device per tree (`ceremonySeen`): the planter right after the commit; the proposer the next time Journey is visible (within 7 days of `plantedAt`).

### B6. Tree guide and the + picker

- `JourneyTreeGuideSheet` gains two sections after the stages: **Watering** "Water your garden every couple of days. One tap waters every tree, and a note can go with it. A tree never dies, never wilts and never loses its growth: water makes it greener and fuller for a day or two." and **Your places** "Each tree can stand for a place and a moment. You plant it together: one of you sends a seed, the other plants it." The Watering text follows `GardenTreeLook.withersWhenThirsty` like the FAQ answer (D6); with the switch on it reads, as before, "… A tree never dies and never loses its growth: when it's thirsty it droops a little, and after a week it rests until the next drop." Both sentences stay in the code.
- Opened from a place tree's stage button (`JourneyTreeGuideSheet(…, growsFromPlanting: true)`, B3 row 1), the guide's first line is "This tree grows from the day you planted it. Today is day 12." ("This tree grows from the day you planted it, starting today." on the planting day), the stage list counts from the planting, and **What grows on it** keeps only "Its colours change through the year." (no stars, letters, blossoms or crowns: C5). Our tree's guide is unchanged.
- `MilestonePickerSheet` gains a first row (while the garden is ready, a start date exists and fewer than 8 trees): **Plant a tree** / "For a place that matters to you two" (`leaf.fill`), handed over on dismiss like the letter row.

### B7. Home: one quiet row

In Home's ambient zone (T4), `BrandCard(tier: .quiet, showsRule: false)`, at most one, priority order:
1. A seed or request waits for me (not snoozed): "🌱 Sam sent you a seed · See it on Journey" (requests: "🌱 Sam suggested a change · See it on Journey").
2. Sam watered < 24 h ago and this device has not seen it on Journey: "💧 Sam watered your garden · today at 9:14 PM", second line the note in quotes (one line, truncated).
- Tap: selects Journey with the matching `GardenFocus`.
- VoiceOver: "Sam watered your garden today at 9:14 PM. Note: Thinking of our first coffee. Opens Journey."
- Never thirst, never a badge.

### B8. Pushes, reminders, notices and errors

**Pushes** (G2 builds them; only to the other partner, only on a garden token device):

| Event | Title | Body |
|---|---|---|
| Watered | "Sam watered your garden 💧" | the note in quotes, else "Every tree had a drink. Peek when you have a moment." (1 tree: "Your tree had a drink. Peek when you have a moment.") |
| First water ever | "Sam gave your tree its first water 💧" | the note, else "Your garden is growing on Journey." |
| Watered together (to the earlier waterer) | "You watered together 💧" | "Sam watered back: “Miss you too.”" / "Sam watered back, 3 hours after you." |
| After ≥ 7 days | "Sam woke up the garden 🌧️" | the note, else "It rested a while. It's green again." |
| Place seed | "Sam wants to plant a tree with you 🌱" | "For “Where we first met”. It's planted when you say yes." |
| Our tree seed | "Sam wants to plant your tree 🌱" | "For the day your story began. It's planted when you say yes." |
| Seed countered | "Sam suggested a change 🌱" | "To your seed for “Our first trip”. Take a look on Journey." |
| Change to a planted tree (created or countered) | "Sam suggested a change 🌱" | "To “Our first trip”. It changes only if you agree." |
| Rest request | "Sam asked to let a tree rest" | "“Our first trip” stays in your garden until you agree." |
| New start date | "Sam suggested a new start date" | "10 March 2023 instead of 12 March 2023. It changes only if you agree." |
| Seed planted (to the proposer) | "Sam said yes 🌳" | "Your tree for “Where we first met” is planted. Come see it grow." |
| Our tree planted (to the proposer) | "Your tree is planted 🌳" | "Sam said yes. It grows from 12 March 2023." |
| Change agreed (to the proposer) | "Sam agreed 🌳" | "“Our first trip” has its new details." |
| Start date agreed (to the proposer) | "Start date updated" | "Sam agreed: your story begins on 10 March 2023." |

No push for: the proposer's own edits, a seed let go or taken back, a request kept, a tree let rest, a look change, a recorded start date. Pushes never contain a place name. 22:00–06:59 in the recipient's time zone they are passive (no sound, no badge).

**Local reminders** (H): "The garden is ready for water 💧" with one of "Water it together tonight?" · "A little water, a little note: the garden is ready." · "Time for a drink? The garden is ready when you are." (picked by the watering id, so both phones agree); and "Your garden is resting 🌙" / "No rush. Whenever you're ready, a little water wakes it up."

**Notification settings**: a new toggle **Garden**, subtitle "Waterings, seeds and two gentle reminders", default on, stored as `notificationPreferences.garden` (the function checks it; the reminders read its UserDefaults mirror).

**Errors**: exactly `GardenError.message(partnerName:now:)` (contract). Additional strip copy: "Couldn't water the garden. Your trees are fine. Try again in a moment." (a watering refused within 2.5 s), "Couldn't change the look. Try again in a moment.", "Couldn't save your answer. Try again in a moment.".

### B9. Loading, empty, error and offline (summary)

| Surface | Loading | Error | Offline |
|---|---|---|---|
| Hero | Journey's existing loading, then "Checking the garden…" | unavailable state (A11), Journey's strip for actions | cached garden; watering queues; consent actions say they need a connection |
| Requests | hidden until the garden snapshot | hidden | cached cards; actions fail fast offline |
| Plant sheet | busy CTA | inline `GardenError` | every mode disabled with the offline line |
| Seed sheet | busy control | inline | offline line, control disabled |
| Place picker | "Searching…" | "Couldn't search right now. Try again, or drop a pin." | "Place search needs a connection. Drop a pin or skip for now." |
| Postcard / lists | snapshot placeholder (scene colours) | snapshot omitted, scene swatch shown | swatch |
| Garden sheet | skeleton shelf | "Couldn't load your garden. Check your connection and try again." | cached |
| Home row | hidden | hidden | from cache |

---

## C. Visuals

### C1. The new hero composition and where the tree stands

Today the tree is a canvas 55% of the hero's inner width on the right (169–184 pt × 160/196 pt), floating beside a column of text. The garden turns the top of the hero into a **window onto the place where the tree lives**.

- **Frame**: `BrandCard(tier: .hero, insetsContent: false)`: hero fill, accent wash, border and shadow unchanged; the band ignores the hero's 22 pt padding and is clipped with `UnevenRoundedRectangle(topLeadingRadius: Brand.heroCornerRadius, topTrailingRadius: Brand.heroCornerRadius, style: Brand.cornerStyle)`; the caption below pads itself (22 pt sides, 16 pt top, 22 pt bottom). `TierContainer` and `BrandCard` gain `insetsContent: Bool = true` (every existing call site unchanged).
- **Band height**: 208 pt; 176 pt when the scroll viewport is under 700 pt; 168 pt at accessibility text sizes. It never scales with Dynamic Type: it is an illustration.
- **Grid** (fractions of the band: x of W, y of H), from `GardenSceneID.info.layout`:

| Element | Position | Why |
|---|---|---|
| Horizon | y 0.54–0.66 per scene | the sky gets the top half: room for chips, sun or moon, the crown ring |
| Landmark mass | left third, x 0.04–0.45 | balances the tree; the eye travels landmark → tree |
| Trunk base | the knoll apex, x 0.60–0.66, y 0.80–0.86 per scene | on the right-third line; the apex sits exactly under the trunk |
| Tree canvas | square of side 0.86 H (City Lights 0.80 H), placed so its ground (top + 0.93 × side) lands on the apex (`GardenSceneLayout.treeFrame(in:)`) | the same pixel size as today (≈ 179 pt at 208), so stars, envelopes and blossoms keep their tuned sizes and tap targets |
| Front layer | bottom 32% of the band, drawn over the tree | grass blades and planter faces overlap the trunk base: the tree stands *in* the place |
| Place chip | top-leading, 12 pt inset, ≤ 0.44 W | clears the canopy and the crown ring |
| Garden chip | top-trailing, 12 pt inset, 36 pt | clears the canopy's right edge (≈ 0.81 W) |
| Page dots | bottom-centre, 8 pt up | over the front grass, drawn darker there for contrast |
| Resting cans | `TreeCanvasAnchors.leftCanPoint` / `rightCanPoint` (0.09 × side left/right of the trunk base) | the partner's on the left, yours on the right, the letters' sides |

At 375 pt (band 351 × 208): tree frame x 128–307, y 12.5–191; at 393 pt the canopy spans ≈ 175–297 pt; chips stay clear.

- **Why this is nicer**: the tree stands *somewhere*, grounded on a knoll rising out of a landscape at the thirds point, with depth in front (grass over the knoll), behind (water, fields or a skyline) and above (a real sky with a sun or moon). The letters still hang where they did, the stars still orbit, the crown ring still crowns it, now against a sky.
- **Tree palette follows the sky**: inside a scene `RelationshipTreeCanvas` gets `TreeCanvasStyle.scene(species:sky:topologySeed:)`, whose `backdrop` is `.dark` when the sky's darkness > 0.5 (lit bark, cream stars even in Light mode) and `.light` otherwise; its warm glow only appears as light falls; its own ground patch is off (the knoll is the ground).
- **Dark appearance**: a daytime band gets a black veil of `0.18 × (1 − darkness)` so a noon sky is not a bright slab in a dark UI; night is untouched.

### C2. How a page is rendered (cheap by construction)

One page = one `GardenScenePage` (P10). Back to front:

| # | Layer | Drawn by | Changes when |
|---|---|---|---|
| 0 | Sky gradient | SwiftUI `LinearGradient(top, horizon)` from `GardenSkyState` | the minute tick |
| 1 | Sky life: sun or moon, stars, 2–3 clouds | `painter.drawAmbient(.sky)` in the page canvas | every live frame (≤ 6 primitives) |
| 2 | Far landscape, day + night images, night at opacity = darkness; parallax 0.35× while paging | `GardenBackdropCache` (`CGImage`, rendered 1.35 W wide) | never per frame; rendered once per key |
| 3 | Scene life behind (windmill blades, beam, gulls, boats, lanterns, string lights) | `drawAmbient(.behind)` | every live frame |
| 4 | Near landscape (ground, knoll, landmark, props), day + night images | cache | never per frame |
| 5 | Tree, external clock | `RelationshipTreeCanvas(clock: .external(time, pose))` | every live frame |
| 6 | Resting cans, rainbow, after-glow | P8 overlays (static shapes) | on state change |
| 7 | Front landscape (grass, planter faces), day + night images | cache | never per frame |
| 8 | Front life: petals, leaves, snow, fireflies | `drawAmbient(.front)` | every live frame |
| 9 | Watering effect / scene accent | `WateringEffectPainter.draw` + `painter.drawWateringAccent` | only while playing (≤ 3.8 s), then removed |
| 10 | Warm tint (soft light, `warmTintAlpha`), dark-appearance veil, chips, dots | SwiftUI | state changes |

- **One clock per page**: layers 1, 3, 5, 8, 9 are drawn inside ONE `TimelineView(.animation(minimumInterval: playing ? 1/60 : 1/30, paused: !live && !playing))` per page; the tree canvas runs no clock of its own (`.external`).
- **The motion gate** (contract `GardenMotionGate`, evaluated by P10): `isLive = isSelectedPage && heroVisible && tabShown && !journeySheetPresented && sceneActive && !lowPower && !reduceMotion`; `allowsEffect` is the same without `!lowPower`. `heroVisible` comes from `.onScrollVisibilityChange(threshold: 0.1)` on the hero container (outside the horizontal pager, so it observes Journey's vertical ScrollView); `tabShown` from the hero's `onAppear`/`onDisappear`; `journeySheetPresented` is `GardenHero.isCovered`: Journey's own sheets (`TimeTreeView.isJourneySheetPresented`), ContentView's letters sheet, and the crown and planting-ceremony overlays (presenting any of them fires no `onDisappear`, so without it the hero would keep animating under them). Selection, not scroll visibility, decides which page animates: a peeking neighbour mid-swipe draws one frozen frame. Effects play in Low Power Mode (short and user-started) but not under Reduce Motion.
- **Static layers are truly static, and shared by scene**: `CGImage`s from `GardenBackdropCache` (P5) keyed by `GardenBackdropKey` = scene, layer, variant, season, band size and scale (≤ 2) — **never the tree**. Static art is seeded by the scene (`GardenSceneStyle.staticSeed(for:)`), so every tree in the same scene shares its images; per-tree variety lives in the tree itself (species, stage, topology), in the ambient passes (seeded per tree) and in the chip. Static art never depends on the time of day (the sky, tint and celestial layers carry time). The night variant is needed only while `darkness > 0` and the day variant only while `darkness < 1`, each tree by its own place's clock. Three tiers:
  1. **Memory**: an `NSCache` whose cost limit comes from the working set, `GardenBackdropBudget.memoryCostLimit` = 3 pages (the selected one and its two neighbours) × 2 variants × one page variant (far 1.35 W + near W + front 0.32 H, × H × 4 bytes × scale²: 3.12 MB at 351 pt, 3.70 MB at 416 pt) ≈ 19–22 MB; set with `configure(band:scale:)` when the band's size is known.
  2. **Disk**: `Library/Caches/GardenBackdrops/v<artVersion>/<fileName>` PNGs, written in the background after each render and decoded off the main actor on a hit (≈ 2–5 ms on an A12, nothing on the main actor); capped at 48 MB, oldest first; older `v<n>` folders deleted. It holds only our own art (no user data), so it survives sign-out.
  3. **Render**: `ImageRenderer` on the main actor (≤ 8 ms on an A12), at most **one per frame** across all callers, only on a memory and disk miss.
- **Pre-warm and first appearance**: when the pager settles (its `scrollPosition` unchanged for 0.3 s), P10 calls `prewarm` with the keys of the two neighbouring pages (the variants their skies need now); they load from disk or render one per run-loop turn at low priority, so a swipe finds them in memory. While a swipe is in flight P10 asks only `cachedImage(for:)`; a page whose images are not in memory shows the **placeholder** — its sky gradient plus a flat ground band from the horizon down in `GardenSceneInfo.groundDay`/`groundNight` (pure SwiftUI shapes) — and once the pager rests, `image(for:)` brings its far, near and front images in (0.2 s fade). Journey's first appearance works the same way: the 0.8 s reveal plays over the placeholder while the selected page's layers arrive. K5.14 measures both.
- **Scene and effect painters are pure** `nonisolated` value types (`GardenScenePainting`, `WateringEffectDrawing`), safe in `Canvas(rendersAsynchronously: true)` and in `ImageRenderer`. They never call `TreeGrowthStage` or `TreeSeason` members (main-actor isolated in the project; they use the contract's `GardenSceneSeason`). The tree painter keeps today's main-actor isolation (I6). No text is ever drawn in a canvas.
- **Thumbnails** (look carousel, shelf, map annotations) are swatches from the same cache (day variant, small size); the shelf's tree is a still `RelationshipTreeCanvas` (pose `.still`, no clock).

### C3. Sky, time of day and seasons (shared by every scene; logic in the contract)

- **Whose clock**: the place's (`place.tz`) when the tree has a place, else the phone's. A long-distance couple sees night over the café in Lisbon while it is morning in Saigon. The postcard says it: "1:14 PM in Lisbon" (only for exact places).
- **Sky keyframes** (`GardenSky.state(at:in:)`, interpolated per minute):

| Local time | Top | Horizon | Darkness | Warm tint |
|---|---|---|---|---|
| 00:00–05:00 | `#0B1430` | `#1F3157` | 1.0 | — |
| 06:00 dawn | `#3B4E86` | `#F6B38A` | 0.5 | `#FF9E6B` 20% |
| 07:30–16:30 day | `#6FB7EA` | `#D8EEF8` | 0 | — |
| 17:30 golden | `#7AA6D6` | `#FFD08A` | 0.15 | `#FF9E5E` 25% |
| 19:00 dusk | `#2E3A6E` | `#F08A6B` | 0.6 | `#E86F7D` 30% |
| 20:30 night | `#0B1430` | `#1F3157` | 1.0 | — |

  Sun on an arc 06:00–19:00 from (0.12, 0.55) through (0.50, 0.12) to (0.88, 0.55), r 12 pt `#FFF4CF`, glow `#FFE7A3` 35%; moon on the same arc 19:00–06:00, crescent r 11 pt `#F4F1DE` with a glow; 40 seeded stars (r 0.6–1.4 pt, 40–90%) at `starsAlpha`, 6 of them twinkling while live; clouds = four overlapping circles on a flat base, white 85% by day, `#9AA5C7` 35% at night, drifting 3–6 pt/s.
- **Seasons** (`GardenSeasons.season(at:latitude:timeZone:)`): temperate north (lat ≥ 23.5°) Mar–May spring, Jun–Aug summer, Sep–Nov autumn, Dec–Feb **winter (snow)**; temperate south (≤ −23.5°) six months on; tropical (|lat| < 23.5°, all of Vietnam) Dec–Feb **dry season** (green canopy, straw-tinted ground, never snow); **no place** = the phone's month as today, but Dec–Feb is **mild winter** (today's frosty canopy, no snow anywhere in the scene). The canopy uses `GardenSceneSeason.treeSeason`, so Our tree without a place looks exactly as today.
- **Season details common to every scene** (front pass and static ground): spring adds up to 8 falling petals (`#F7C6D9`, 14 pt/s, sway ±6 pt) and 14 flower dots on the ground; summer: ground 8% more saturated, up to 8 fireflies at night (scenes with grass); autumn: ground blended 30% toward `#C9A04A`, 12 leaf dots, up to 8 falling leaves (`#E08A3C`, `#C9653A`); winter: white `#EEF3F8 → #DCE6EF` on the top 40% of ground bands, 1.5–3 pt caps on roofs, posts and peaks, up to 24 snowflakes (r 1–2 pt, 18 pt/s); mild winter: ground 10% paler, no particles; dry season: ground mixed 25% toward `#C8B27A`, no particles.

### C4. Scene catalog

Shared primitives (P5, `GardenSceneKit`, all deterministic: static layers from `GardenSceneStyle.staticSeed(for: scene)`, one seed per scene so every tree in a scene shares the cached images; ambient passes from the tree's `GardenAmbientState.seed`): `hills(base:amplitude:frequency:phase:)` (closed path sampling `y = base − a·(0.5 + 0.5·sin(2πfx + φ))` every 8 pt), `knoll(apex:halfWidth:)` (quad curve from (apexX − hw, 1.0) to (apexX + hw, 1.0) with control (apexX, 2·apexY − 1.0)), `catenary(from:to:sag:count:)` (points for bulbs, lanterns, flags), `scatter(count:in:seed:)`, `glints(count:band:)`, `frontGrass(blades:height:)` (30–40 quadratic blades, 6–14 pt), `snowCap(on:)`, `drawCelestial`, `drawClouds`, `drawSeasonParticles`. Coordinates below are band fractions; each scene names its day and night colours for the same geometry.

**1. Meadow** (`meadow`, default; parks, sports, amusement) · apex (0.62, 0.86) · horizon 0.58 · default oak · stamp `leaf`
- *Far*: hill A base 0.58, a 0.06, f 0.9, φ 0.3, day `#A8C8B4` / night `#1F3446`; hill B base 0.64, a 0.05, f 1.4, φ 2.1, `#94BFA0` / `#1B3040`; a tree line of 9 round silhouettes on hill A `#7FAF78` 60% / `#162A24`.
- *Near*: field `#86C27A → #6EAE63` / `#1E3A2E → #183026`; a winding path (0.05, 0.98) → (0.55, 0.72), 18 → 4 pt, `#E8D6A8` / `#4C4636`; a split-rail fence x 0.04–0.34 at y 0.76 (6 posts, 2 rails) `#8C6B4A` / `#3B2E24`; a windmill on hill A at x 0.20: tapered tower 0.018 → 0.010 W, 0.11 H, `#EDE6DA` / `#3A4256`, its window `#FFD27A` at night; the knoll half-width 0.30 `#6FAF5F` / `#1C3527`; 36 wildflower dots (r 1.2–2 pt, `#FFFFFF #FFE27A #F7A8C4`).
- *Front*: blades `#4E8A47` / `#1A2E22`.
- *Ambient*: windmill blades (0.06 H) turning 0.25 rad/s (behind); 2 butterflies by day in spring and summer (two ellipse wings at 6 Hz on lissajous paths); fireflies at night in summer.
- *Seasons*: autumn field `#C9A35A → #B5873F`, hills `#C9B48A`; winter snow with blue shadows `#C9D6E2`, caps on the fence posts.
- *Watering accent*: two butterflies lift off (day) / the fireflies brighten (night).

**2. Seaside** (`seaside`; beach, marina, surfing, kayaking, fishing, aquarium) · apex (0.64, 0.84) · horizon 0.54 · default palm · `water.waves`
- *Far*: a headland (0, 0.40) → (0.30, 0.54) with two bumps `#6F8F7A` / `#1B2B33`; the sea 0.54–0.80 `#2F8FBF → #6CC7DD` / `#0E2A45 → #173C5A`; a 1 pt horizon line, white 40%.
- *Near*: a lighthouse at (0.13, 0.40): tapered tower 0.028 → 0.018 W, 0.16 H, `#F7F4EE` with three red bands `#D9534F`, lantern room and cap `#3C3C3C` (night: lantern `#FFE8A0`); a dune knoll at the apex, sand `#F2DDB0 → #E2C08A` / `#5B5240 → #463F31`; a driftwood log at (0.30, 0.92); two shells `#F7E6DA`.
- *Front*: beach-grass tufts `#9BB86B` / `#3C4A2E`.
- *Ambient*: 8 glints on the sea (6–14 pt, 50%), gathered under the moon at night; two foam lines at 0.78 and 0.80 sliding ±6 pt over 4 s; two gulls (stroked "M"s) by day; at dusk and night a beam (wedge 0.5 W long, 35% → 0) sweeping ±40° at 0.6 rad/s.
- *Seasons*: summer sea `#36A3C9`; temperate winter `#6E8FA3 → #9DB7C4`, no gulls, snow only above 45° latitude.
- *Watering accent*: a wave crest throws spray over the dune edge.

**3. City Lights** (`cityLights`; cafés, restaurants, bars, theatres, hotels, first dates) · apex (0.60, 0.80) · horizon 0.66 · tree side 0.80 · default cherry · `building.2`
- *Far*: a skyline on base 0.66: 14 seeded buildings (0.05–0.10 W wide, 0.12–0.38 H tall), two antennas, one stepped top; day haze `#A6B6C9`, night `#1A2236` with a window grid (2.5 × 3.5 pt cells, 35% lit `#FFD27A`).
- *Near*: six closer buildings `#8797AD` / `#141B2C`, a water tower on one roof; a rooftop terrace: parapet 0.88–1.0 `#C9B8A6` / `#2D2A35` with a coping line; a bench silhouette at (0.25, 0.86); the planter box behind the trunk (x 0.60 ± 0.11, top 0.80) `#9C6B43` with plank lines.
- *Front*: the planter's front face 0.80–0.90 (so the trunk stands *in* it).
- *Ambient*: string lights on a catenary (0, 0.30) → (1, 0.26), sag 0.10, 11 bulbs r 2.4 pt: unlit `#FFF3D6` 60% by day, lit `#FFD27A` with an 8 pt radial glow from golden hour, twinkling (opacity 0.75–1.0, 0.8 Hz, own phase); one skyline window toggles every ~4 s at night.
- *Seasons*: snow on the parapet; blowing leaves in autumn; petals in spring.
- *Watering accent*: the string lights flicker on bulb by bulb.

**4. Mountain Lake** (`mountainLake`; national parks, hiking, skiing, climbing, campgrounds) · apex (0.66, 0.86) · horizon 0.56 · default pine · `mountain.2`
- *Far*: three peaks with curved flanks, tops (0.18, 0.20), (0.46, 0.14), (0.80, 0.24), base 0.56, rock `#8A9BB0` / `#222B40`, snow caps on the top 35% with a jagged edge `#F4F7FA` / `#9AA7C0`; alpenglow `#F7B6A8` at 50% on the snow is part of the warm tint.
- *Near*: two rows of pines (24 + 18 triangles, 0.05–0.10 H) `#2F5D4A`, `#3C6E57` / `#10231C`; the lake 0.60–0.80 `#5E9CB8 → #8CC2D4` / `#0F2638 → #17344A` holding a mirror of the peaks (flipped, 30%); a dock of 5 planks (0.08, 0.86) → (0.30, 0.80) with 3 posts; three grey rocks; the shore knoll `#5F8F57` / `#18301F`.
- *Front*: alpine grass and a rock edge.
- *Ambient*: 6 shimmer lines on the lake; a cloud drifting across the peaks.
- *Seasons*: winter freezes the lake `#DDE8EF` (cracks instead of shimmer); autumn turns 30% of the pines into gold larches `#D8A23C`; spring wildflowers on the shore.
- *Watering accent*: a fish jumps (an arc and two ripple rings).

**5. Lantern Town** (`lanternTown`; old towns, landmarks, museums in East and Southeast Asia; weddings) · apex (0.66, 0.86) · horizon 0.62 · default cherry (peach blossom) · `lamp.table`
- *Far*: seven townhouses on base 0.62 (0.11–0.16 W, walls 0.10–0.16 H) `#E9C46A #E8B04F #D99B4A` / `#3A3346` with windows `#FFC46B` at night; tiled roofs as trapezoids with upturned eaves (quad curves) `#7A4E3A` / `#241A22`; one two-tier temple roof at x 0.78.
- *Near*: the river 0.64–0.80 `#3E7C7F → #5E9E99` / `#10263A → #173246`; an arched bridge (0.10, 0.70) → (0.42, 0.70), apex 0.58, lacquered `#A0522D` / `#3B2420`, railing posts; the cobbled embankment knoll `#B8A58A` / `#3E3830`.
- *Front*: cobble edge and a few tufts.
- *Ambient*: a lantern line on a catenary (0.02, 0.22) → (0.98, 0.30) with seven silk lanterns (9 × 12 pt ellipses with caps) `#E63946 #F4A261 #E9C46A #E76F51` swaying ±4°, glowing `#FFB55A` (r 16, 45%) from golden hour; a crescent boat at (0.55, 0.74) bobbing ±1.5 pt; six lantern reflections shimmering (35%).
- *Seasons*: spring drifts peach-blossom petals `#F7A8C4`; a temperate old town gets snow on the roofs in winter.
- *Watering accent*: the lanterns brighten in a wave from left to right.

**6. Rice Terraces** (`riceTerraces`; countryside and nature places in rice-growing countries) · apex (0.62, 0.84) · horizon 0.56 · default banyan · `leaf.circle`
- *Far*: three misty ridgelines (bases 0.40, 0.48, 0.56; a 0.05–0.08) `#7E9AA6 #92AEB4 #A9C3C3` / `#1B2733 #22303D #2A3A46`, white mist strips (25%) between them.
- *Near*: six terraces stepping 0.56 → 0.86, each bounded by two concave curves with a darker bund `#6C8A3F`; the fill **is the season**: spring flooded (a mirror of the sky plus glints), summer `#7DBF4E → #5FA23A`, autumn harvest gold `#E5C15A → #D4A83A`, dry season stubble `#B8A27A`, night `#1E3324`; a stilt house at (0.20, 0.60) (body `#8C6A4A`, roof `#6B4F35`); the terrace-edge knoll with a short bamboo fence.
- *Front*: rice tufts.
- *Ambient*: three smoke puffs rising from the stilt house; a mist band drifting at 6 pt/s (15%); glints on flooded terraces.
- *Watering accent*: glints run down the bunds, terrace to terrace.

**7. Campus** (`campus`; universities, schools, libraries; heritage outside Asia) · apex (0.64, 0.86) · horizon 0.62 · default oak · `graduationcap`
- *Far*: a brick hall x 0.05–0.62 (top 0.42, base 0.62) `#B5654B` / `#3A2328` with six arched windows (lit `#FFD58A` at night); a clock tower at x 0.30 (0.07 W, top 0.18), pyramid roof `#5B4A55`, clock face r 7 pt `#F6F1E1`.
- *Near*: two round trees at x 0.75 and 0.90 `#6DA36A` / `#1D3326` (autumn `#D9893B`, winter bare branches with snow); two lamp posts (glowing at dusk and night); the lawn knoll `#79B566` / `#1C3424` with a bench and two tiny books; stepping stones.
- *Front*: lawn edge.
- *Ambient*: the clock's two hands show the place's local time (drawn in the behind pass from `GardenSkyState.localHour` and the minute); lamp glow.
- *Watering accent*: the tower bell rings (two expanding arcs).

**8. Home** (`homePorch`; first home, addresses, dropped pins with the First home preset) · apex (0.64, 0.86) · horizon 0.60 · default oak · `house`
- *Far*: neighbourhood roofs (triangles) `#C7B9A8` 70% / `#232838`.
- *Near*: a house at the left (x 0–0.34, y 0.40–0.86): wall `#EBD9C2`, roof `#A3574A`, door `#6E4B3A` with a knob, a window with a curtain (`#F6E7C8`; `#FFC873` from golden hour), two porch steps `#C9B7A2`, a mailbox at x 0.36 with its flag up; a picket fence on the right `#F5F1EA` / `#3A3F52`; a garden bed `#8B6A4E` with flower dots; the lawn knoll.
- *Front*: flower-bed edge.
- *Ambient*: chimney smoke in winter and at night (three soft rising circles); a gentle window flicker at night (opacity 0.9–1.0 at 0.3 Hz).
- *Watering accent*: the porch light blinks on and off once.

Unknown scene ids (a newer app) draw as Meadow and are never rewritten.

### C5. Five species, one painter (P7)

Every species keeps `TreeCanvasLayout`'s geometry (trunk, limbs, canopy centre and radius), so letters, blossoms and their tap targets work on any species Our tree can have. Only the drawing changes.

| Species | Drawing | Our tree? |
|---|---|---|
| `oak` | today's painter, unchanged; the default (existing couples see the same tree) | yes |
| `cherry` ("Blossom") | canopy ellipse 1.10× wider, 0.90× taller; leaves mix 50% toward blossom pinks `#F9C5D5` / `#F4A6BD` in spring and summer; 1.6× the stage's blossoms; autumn `#E79A5C`/`#C9653A`; winter canopy fullness × 0.4 with twigs visible | yes |
| `banyan` | canopy ellipse 1.25× wider, 0.75× taller (a broad dome); 8–14 aerial roots hanging from the outer half of each limb to 70–90% of the way to the ground (1 pt strokes `palette.twig` at 70%, live sway ±1.5 pt at 0.3 Hz); always green (dry season and winter keep the summer palette, mild winter darkens it 10%) | yes |
| `pine` | no ellipse canopy: `max(1, branchCount/2)` stacked triangle tiers from the trunk top, `#3E7B5A → #2F6249` every season, a 1.5 pt snow edge per tier when the scene has snow; fruits become pinecones `#7A5233`; limbs drawn under the tiers | place trees only |
| `palm` | a slim trunk with ring marks every 0.06 unit `#8A6A4E` and a gentle S-curve that returns to the layout's midX at the top; `max(3, branchCount)` fronds from the top as arcs with 10 leaflet strokes `#4E9A5A → #3C7F47`; coconuts `#6B4A2F` as fruits; always green | place trees only |

Place trees never show memory stars, letters or the crown ring (those belong to the relationship); they show stage, leaves, blossoms and fruit. Their topology is seeded from FNV-1a(tree key), Our tree's from the days together (today's silhouette).

### C6. Lush, plain and revived; the thirsty look kept behind a switch (P7, from `GardenTreeVisual` / `TreeVitality`)

**What the app draws** (0.0 #3, `GardenTreeLook.withersWhenThirsty = false`): `GardenTreeVisual.at(hoursSinceWater:)` returns `thirst` 0 and `soilDryness` 0 at every age, so a tree has its plain look (`.healthy`) plus only what a watering adds: lushness, wet soil and dew, each fading back to plain on its own. Every path below that follows thirst (droop, dry olive leaves, fallen leaves, buds, pale and cracked soil) draws nothing, in the hero, the Garden sheet's terrariums and the ceremony alike; a tree waiting a month looks exactly like one never watered. The painter keeps that code for the switch: the lab's species gallery (K6) passes thirst to the painter directly, and the canvas previews ask for it with `at(hoursSinceWater:withers: true)`, so artists can still review it. The water states stay in words only: the status line, the VoiceOver value, the CTA and the reminders.

The thirsty and resting look (only with `withersWhenThirsty = true`):

- **`thirst`** 0…1 (contract curve: 0 until 72 h; 0 → 0.5 over 72–96 h; 0.5 until 168 h; 0.5 → 1 over 168–192 h). With `d = vitality.droop(at: time)`:
  - leaf colour mixes toward a dry olive (`#9C9A5A` top, `#7D6B3F` bottom) by `m = d ≤ 0.5 ? 0.5·d : 0.25 + 0.3·(d − 0.5)` (25% when thirsty, 40% when resting);
  - each leaf moves down by `d · unit · 0.012 · (0.4 + 0.6 · r/R)` (outer leaves sag most) and stretches `height × (1 + 0.25d)`; flutter amplitude × (1 − 0.6d);
  - limb tips droop `+0.12 · reach · d` through the existing `tipOffset` path, so hanging envelopes dip with their limbs; ornament tap targets use the same drooped geometry;
  - blossoms shrink × (1 − 0.25d) and close into buds at d ≥ 0.95;
  - `round(6 · d)` seeded leaves lie on the ground around the trunk (3 when thirsty, 6 when resting).
- **Soil bed** paling: by `soilDryness` (0 before 48 h, 1 at 72 h); three hairline cracks (`#7A6248` 40%) when thirst ≥ 0.5.

Always drawn:

- **Soil bed** at the trunk base (rx 0.16 S, ry 0.035 S): colour mixes dry `#C2A27C` → wet `#5A3E2B` by `wetness` (55% opacity); a 35% white puddle glint while wetness > 0.85.
- **Dew**: `round(12 · dew)` white beads (r 1.2 pt with a 0.6 pt highlight) on seeded leaves, twinkling while live.
- **Revival** (every watering): `reviveStart = playback.startTime + effect.reviveOffset`, `reviveFrom = thirst before` (0 in the app, so the revival only eases lushness in over 1.2 s; with the switch on, droop eases to 0 over 1.2 s with an easeOutBack overshoot of 1.4, the leaves spring up past level and settle, fallen leaves fade and colours re-saturate on the same curve).
- **Lush** (0.0 #3; `lushness` 0…1, contract curve: 1 for 24 h after a watering, easing to 0 by 48 h): the reward for watering and, with wet soil and dew, the only time-driven change to how the tree looks. It comes only from a watering at or after the tree's planting: a tree planted after the garden's latest watering shows its planting's wet soil and dew (A6) but no lushness until someone waters it (`GardenTreeVisual.forTree`). Leaf colour mixes toward a vivid spring green (`#5FBF4A` top, `#3E8E3A` bottom) by `0.30 · lushness`, saturation +12%, `round(8 · lushness)` extra seeded leaves fill the canopy edge, a soft specular sheen on the upper leaves (white, 18% × lushness), blossoms (where the stage has them) open 10% wider. Lushness and thirst never overlap (thirst is 0 until 72 h, and always 0 in the app).
- Nothing wilts: neither the scene nor the tree ever looks worse for waiting, so the place stays beautiful and watering is a gift, never a chore.

### C7. How a tree shows its place, and several trees at once

- **In the band**: the place chip (readable, tappable, Dynamic Type) plus the look itself. No sign text in the canvas.
- **Postcard** (B5.4): a muted Apple Maps snapshot, perforated stamp, postmark, Apple attribution.
- **Lists**: 56×56 snapshots (or the scene swatch without a place).
- **The pager** is the garden: swipe between windows; the far layer moves at 0.35× (transforms only, off under Reduce Motion); the caption crossfades (0.2 s).
- **Page dots**: every tree is a dot; one tap of water ripples across them (C9).
- **The Garden sheet's shelf**: every tree as a 96×120 terrarium (static).
- **The map**: every placed tree at its real place; area places as a soft circle, never a pin.

### C8. The planting ceremony (P8, `PlantingCeremonyOverlay`)

The band (full width − 32 pt × 300 pt) over a 0.75 black dim:

| t (s) | What happens | Easing | Haptic |
|---|---|---|---|
| 0.0–0.5 | The place with an empty mound; **two seeds** arc in, one from the left edge (the partner) and one from the right (you), peaking 0.25 H above the mound | ease-in on the fall | light at 0.45 and 0.55 |
| 0.5–0.9 | The mound puffs (scale 1 → 1.12 → 1) and throws 8 soil crumbs | spring 0.3 / 0.55 | — |
| 0.9–1.4 | A two-leaf sprout pops (0 → 1.1 → 1) | spring 0.35 / 0.6 | soft |
| 1.4 → 2.2 | The new tree sprouts (0.0 #3: place trees always start as a seed; Our tree for an existing start date shows its own stage): one 0.6 s grow-in with a 4% overshoot, then the first watering sparkle (`lushness` 1) | easeOutBack | rigid 0.4 |
| +0.6 | A short can pour (the `can` effect's pour, 0.6 s) and 8 glints | — | drizzle |
| +0.5 | The place chip slides down; the words fade in over a 40% scrim on the band's lower third, then **See it in your garden** | spring | success |

Total ≤ 5.6 s; a tap skips to the end. Reduce Motion: the final pose crossfades in over 0.4 s, the year line reads "Growing since 2023", one success haptic. VoiceOver: modal; on appear it announces "Planted together. Where we first met, Café Giảng. A Fruiting tree, growing since 12 March 2023." and focuses the title.

### C9. Watering animations (P8)

**How they are built**: one effect painter (`WateringEffectPainter`, `nonisolated enum`) called inside the page's TimelineView (60 fps while playing). Every particle is analytic: generated from the watering's seed at t = 0 with a position, velocity and spawn time, drawn at `p(t) = p₀ + v·(t − t_spawn) + ½·g·(t − t_spawn)²`; no stored particle state, no per-frame allocation, correct after any pause. Glows are radial gradients, never blur filters. Shapes are a handful of unit `Path`s reused with transforms. Anchors come from `RelationshipTreeCanvas.anchors(in:stage:)` (offset into the page). Water colour: `#8FD3FF` 90% by day, `#CFE3FF` at night.

1. **Watering can** (`can`, 2.6 s)
   - 0–0.45: a teal-zinc can (`#5E8C8A` rounded-trapezoid body, tapered spout, arc handle, rose with 5 holes) slides in from the top-right to just above the canopy's right shoulder (ease-out cubic).
   - 0.30–0.65: tilts to −38° (spring 0.3 / 0.6).
   - 0.55–2.0: pours 26 drops/s from the rose, v₀ = (−150 ± 30, 30 ± 20) pt/s, g = 900 pt/s², each a 2 × 6 pt capsule along its velocity; on the soil line a splash (ellipse 0 → 14 × 4 pt, 60% → 0 in 0.35 s) and two bouncing micro-droplets.
   - 0.8–2.0: soil moisture 0 → 1; revival (C6).
   - 2.0–2.45: tilts back and leaves (ease-in). 2.0–2.6: 8 four-point glints pop on the canopy, 50 ms apart.
   - Peak ≈ 32 drops + 12 splashes. Haptics: medium at the tilt; *drizzle* (transients every 90–140 ms, intensity 0.25–0.45, sharpness 0.5) during the pour; success at 2.4 s.
2. **Rain cloud** (`rainCloud`, 3.2 s)
   - 0–0.6: a cloud (5 circles r 14–22 pt on a flat base; white 92%, night `#AEB8D6` 75%) drifts in from the left over the canopy.
   - 0.6–2.2: 40 streaks (1.1 × 11 pt, 8° off vertical, 560 pt/s, 55%) to the ground line; ground ripples (6 × 2 pt, 0.25 s).
   - 1.0–2.2: revival. 2.0–2.6: the cloud brightens and drifts away right.
   - 2.0–3.2: a rainbow behind the tree, six 2.2 pt arcs (`#FF6B6B #FFB86B #FFE66B #7EDC8B #6BB8FF #B48BFF`), 200°–340°, centred on the trunk base, opacity 0 → 55% → 0; at night a single silver moonbow at 35%.
   - Haptics: *rain* (16 transients over 1.6 s, intensity 0.2–0.4, sharpness 0.3); success at 2.6 s.
3. **Morning dew** (`morningDew`, 2.4 s; offered 05:00–09:59 at the place)
   - 0–0.6: a low mist (three white ellipses, 25%) rolls in along the ground.
   - 0.4–1.6: 18 dew beads (r 1.8 pt, 85%, highlight) bead up on the leaves, 50 ms apart; three soft god rays from the sun's side (12%).
   - 0.6–1.8: revival. 1.8–2.4: every bead glints once; the mist fades.
   - Haptics: 6 light ticks with the beads; success.
4. **Moonlit drizzle** (`moonlitDrizzle`, 2.8 s; offered 20:00–04:59 at the place)
   - 0–2.0: 26 fine silver streaks (0.8 × 8 pt, 380 pt/s, 45%).
   - 0.8–2.0: revival. 1.6–2.8: 10 fireflies wake in the grass and float up (12 pt/s, sine wobble), blinking.
   - Haptics: 10 soft transients (0.18); success.
5. **Watered together** (`together`, 3.4 s; the watering that completes "watered together")
   - 0–0.5: two cans enter at once, the partner's from the left (mirrored), yours from the right. 0.4–0.7: both tilt (±38°).
   - 0.6–1.8: two streams arc toward the canopy's crown and meet at ≈ 1.0 s in a heart-shaped splash: 20 droplets launched along `(16 sin³θ, −(13 cos θ − 5 cos 2θ − 2 cos 3θ − cos 4θ))`, speed ∝ radius (max 150 pt/s), g = 500.
   - 1.0–2.2: revival. 1.8–2.4: the cans leave. 2.0–3.4: 6 small hearts (`heart.fill` resolved once as a canvas symbol, `#FF6B8A`) float up and fade; a soft rainbow fades in to 40%, then settles at 25% and **stays** (the rainbow overlay) for 24 h on both phones.
   - Haptics: medium at 0.45 s (left) and 0.57 s (right); a heartbeat (two transients 0.12 s apart, 0.7 / 0.5) at the splash; success at 2.4 s.
6. **The rain returns** (`rainReturns`, 3.2 s; ≥ 7 days since the previous watering)
   - 0–0.6: the sky dims (`#3A4A5E` 0 → 25%), the grass sways.
   - 0.6–2.0: a warm rain over the whole band (60 streaks, 260 pt/s).
   - 1.0–2.2: the tree lifts, colour returning in a wave from the bottom of the canopy to the top.
   - 2.0–3.2: the sky clears and a rainbow fades in to 40%, then out. The status line reads "Welcome back. The garden woke up." for 4 s.
   - Haptics: four soft impacts, then success.

**First water**: the garden's first watering ever opens with one big golden drop (0.4 s) before the `can`.

**Every effect ends with the scene's own accent** (C4) in its last 0.6 s.

**Which one plays** (`GardenEffect.choose`, contract): `together` if this completes watered-together; `rainReturns` after ≥ 7 days; `can` for the very first; otherwise a pool by the hour at the selected tree's place: 05–09 `[can, rainCloud, morningDew]`, 10–19 `[can, rainCloud]`, 20–04 `[can, moonlitDrizzle]`; index = FNV-1a(wateringId) mod pool size; never the same as the previous watering's stored effect. The waterer's phone generates the watering id before the write (`newWateringId`), chooses, **stores** the effect on the watering and starts playing at the tap.

**One tap, many trees**: the selected page plays the full effect; the page dots ripple left to right (dot *i* at `0.25 + 0.12·i` s gets a ring r 4 → 11 pt, 1.5 pt water blue, 80% → 0 over 0.45 s); other pages switch to their watered state at once; swiping to another page within 10 s shows its after-glow (8 glints and wet soil fading in over 0.6 s), not a second show; an open Garden sheet revives its terrariums one after another with the same stagger.

**The partner's watering, replayed**: when the latest watering is the partner's and this device has not shown it (`seenWatering`), the selected page replays its **stored** effect once as soon as the hero is visible and live, then the status well pops in with the note; tap to skip; never under Reduce Motion. Arriving from the push, the note's journal row is highlighted too.

**What stays afterwards**: for 24 h after a watering the waterer's can rests on the ground beside the trunk (partner's left, yours right); after "watered together", both cans and the faint rainbow. Always paired with the status line in text.

### C10. Reduce Motion, VoiceOver, Dynamic Type

**Reduce Motion** (`accessibilityReduceMotion`):
- Sky life, ambience and the tree are still (the canvas's `.still` pose); stars do not twinkle; no parallax; the caption crossfades in 0.2 s.
- Any watering: a 0.3 s crossfade of the tree from its plain look to lush (from its droop pose to fresh with `GardenTreeLook.withersWhenThirsty`), the soil darkens, a static `drop.fill` (18 pt, water blue) shows above the soil for 1.2 s, the dots update without ripples, one success haptic. `together` fades the static rainbow in to 25%; `rainReturns` crossfades plain → lush in 0.4 s. Replays are skipped. The ceremony crossfades (C8).

**VoiceOver**:
- The band is one element: a stable label "Your garden" and the shown tree as its **value**, "Our tree. Tree 1 of 4. Blooming, in a meadow with a windmill, in the evening, in autumn. Café Giảng. Watered by Sam today at 9:14 PM. 3 memories shine around it. 2 sealed letters wait on it.", which VoiceOver speaks again after every adjust (review A11Y-2); thirst said in words ("Ready for water", "A little thirsty", "Resting"); with two trees or more it is adjustable, hint "Swipe up or down to visit your other trees." (`accessibilityAdjustableAction` moves the pager); custom actions **Show the place**, **Change look**, **Show your garden**. The chips and dots are folded into it, not separate elements.
- Water control: label as shown; value the state ("Thirsty. Last drink Sun at 9:14 PM."); hint "Waters every tree and lets Sam see it." (legacy partner: "Waters every tree."); custom action **Water with a note**. After watering: `AccessibilityNotification.Announcement("Watered all 4 trees. Sam will see it on Journey.").post()`.
- Status well: one element, "Sam watered today at 9:14 PM. Note from Sam: Thinking of our first coffee. Actions: Water back, Reply in Chat."
- Canvases, effects, the note tag, cans and particles are hidden (as today).
- Thirst is stated in text only: the tree never droops or fades (0.0 #3), and with `GardenTreeLook.withersWhenThirsty` its droop and colour still never stand alone (Differentiate Without Colour holds).

**Dynamic Type**: every word below the band uses `JourneyFont`; at accessibility sizes the band is 168 pt, the place chip moves out of the band into the caption's first row, row 1 stacks, and the water control and "Add a note" become two full-width rows. Checked at AX5 on 375×667 (K3).

### C11. Per-frame budget and measurement

Target device: the oldest iOS 18 phones (A12, iPhone XS/XR); an A13 if no A12 is available.

| Work | Budget |
|---|---|
| Tree (existing painter, incl. its 2 blurred fills) | ≤ 2.5 ms |
| Sky life + scene life + season particles (≤ 30 primitives) | ≤ 1.0 ms |
| Effect (≤ 80 particles + 2 sprites) | ≤ 1.5 ms |
| **Total while watering** | ≤ 5 ms of a 16.7 ms frame; idle ≤ 3.5 ms at 30 fps |
| Static layer from disk (decode off the main actor) | ≈ 2–5 ms off-main, ≈ 0 on the main actor |
| Static layer render (memory and disk miss, main actor) | ≤ 8 ms each, at most one per frame (pre-warm spreads them); never during a swipe |
| First appearance of Journey (or of a page) | placeholder on the first frame; band complete ≤ 300 ms with renders (cold), ≤ 100 ms from disk (warm); no frame over 16.7 ms |
| Backdrop memory tier | ≤ `GardenBackdropBudget.memoryCostLimit` (≈ 19 MB at 351 pt, ≈ 22 MB at 416 pt) |
| Memory with 8 trees and the Garden sheet open | ≤ +40 MB over baseline |

DEBUG builds wrap each painter in `os_signpost` intervals (`garden.backdrop.render`, `garden.backdrop.disk`, `garden.ambient`, `garden.tree`, `garden.effect`); Instruments (SwiftUI, Animation Hitches, Time Profiler) must show no static-layer renders while idle, no main-actor render while a swipe is in flight, nothing animating on a hidden tab, under a Journey sheet or in Low Power Mode, and no hitch over one frame while paging or watering.

### C12. Assets

None. Scenes, species, cans, clouds, rain, fireflies, rainbows, the seed packet and the note tag are `Path`, gradients and a few SF Symbols (`drop.fill`, `leaf.fill`, `mappin`, `tree.fill`, `heart.fill`, the scene stamps). The only images are map snapshots made at runtime and the cached renders of our own painters. This keeps the binary small and follows light and dark for free; the cost is drawing code (≈ 150–250 lines per scene), which is why scenes are split across two packages.

---

## D. Places

### D1. The place picker (`GardenPlacePicker`, P9; pushed inside the plant form, never a second sheet)

- Title **Where is it?**; toolbar **Skip for now**. A segmented control **Search | Drop a pin**.
- **Search**: field "Search for a place or address"; typing updates `MKLocalSearchCompleter.queryFragment` (debounced 250 ms); rows show a category glyph, title and subtitle (at most 12). Before typing: "Your garden's places" (other trees' places), then "Recent" (this phone's last 5 picks, names and coordinates only, purged with the garden caches), then the hint "Search by name, like “Highlands Coffee Nguyễn Huệ” or “Lisbon Oceanarium”."
- **Choose a result**: `MKLocalSearch(request: MKLocalSearch.Request(completion:))` resolves it; a confirmation card over a small non-interactive map shows the name (editable, "Name this place", 80 graphemes), the locality line, the toggle **Show the exact spot** and the filled **Use this place**.
- **Drop a pin**: a live `Map` with a fixed centre pin; pan and zoom under it; the bottom card says "Move the map to put the pin on the spot.", proposes a name from reverse geocoding (`areasOfInterest.first ?? subLocality ?? locality`, e.g. "Near Hoàn Kiếm Lake"), the precision toggle and **Use this place**.
- **Precision defaults** (privacy by default): a point of interest (café, park, beach…) → exact ON; an address result or a dropped pin (it may be someone's home) → OFF, "Only the area (about 1 km)", and the name defaults to the locality ("Đà Nẵng"), never the street.
- **Footnote on every step**: "Only you and Sam can see this place. Coupley never reads your phone's location."
- **Where the map starts**: the bounding box of the garden's places; else one `MKLocalSearch` for the phone's region name (`Locale.current.region`) to frame the country; else the world. Never the device's position.
- **States**: "Searching…" · "No places found for “xyz”. Try another name, or drop a pin." · offline "Place search needs a connection. Drop a pin or skip for now." · failure "Couldn't search right now. Try again, or drop a pin."
- Apple Maps covers small places in Vietnam less well than elsewhere: the pin and a typed name are first-class, not a fallback.
- The result returned to the plant form is a `GardenPlaceCandidate` (P9-internal): the `GardenPlace` (already rounded), whether it was an address or pin, its `GardenPOIGroup` and the item's ISO country code (used only to suggest the look, never stored).

### D2. MapKit APIs (iOS 18.6 minimum, iOS 26.1 SDK)

| Need | API |
|---|---|
| As-you-type suggestions | `MKLocalSearchCompleter`, `resultTypes = [.pointOfInterest, .address]`, `pointOfInterestFilter = .includingAll`, `region` = the bias above; delegate `completerDidUpdateResults`, `completer(_:didFailWithError:)` |
| Resolve a suggestion | `MKLocalSearch(request:)`, `try await start()` → `MKMapItem`: `name`, `pointOfInterestCategory`, `timeZone`, coordinate and locality (`placemark` before iOS 26; `location` and the address representations under `if #available(iOS 26, *)`) |
| Name a dropped pin | `CLGeocoder.reverseGeocodeLocation` before iOS 26; `MKReverseGeocodingRequest` under `#available(iOS 26, *)`; no permission involved |
| Pick on a map | SwiftUI `Map(position:)` + `.onMapCameraChange(frequency: .onEnd)`, `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))`, `.mapControls { MapCompass(); MapScaleView() }` |
| Postcards, thumbnails | `MKMapSnapshotter` (`MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)`, `pointOfInterestFilter = .excludingAll`, light/dark trait), `try await start()` |
| The places map | SwiftUI `Map` with `Annotation` (exact) and `MapCircle` (area) |
| Open in Maps | `MKMapItem` built from the stored coordinate and name (iOS 26: `MKMapItem(location:address:)` behind `#available`), `openInMaps(launchOptions:)` |

Never used: `CLLocationManager`, `MapUserLocationButton`, `UserAnnotation` (each would prompt for location). `Coupley-Info.plist` gains **no** `NSLocation…` key. With MemberImportVisibility, files touching these types `import MapKit` and `import CoreLocation` (an import never prompts). `GardenPlaceSearch` is a `@MainActor` class; its `MKLocalSearchCompleterDelegate` conformance is an isolated conformance (approachable concurrency infers it; MapKit calls the delegate on the main thread); verify zero warnings in Debug and Release. APIs deprecated in iOS 26 do not warn at the 18.6 deployment target; the `#available` branches keep it that way when the target rises.

### D3. What is stored, exactly

The `place` map on a tree, a seed or a change request. Nothing else about places exists anywhere.

| Field | Type | Example | Rules |
|---|---|---|---|
| `name` | string | "Café Giảng" | 1–320 (client 80 graphemes); the POI name or the couple's words; area → defaults to the locality |
| `locality` | string, optional | "Hoàn Kiếm, Hà Nội" | ≤ 320; district and city (+ country abroad); **never street or number** |
| `lat`, `lng` | number | 21.0345, 105.8543 | exact: rounded to 4 dp (≈ 11 m); area: 2 dp (≈ 1.1 km); **checked by the rules** |
| `precision` | `"exact"` \| `"area"` | "exact" | required |
| `poi` | string, optional | "MKPOICategoryCafe" | ≤ 64; `MKPointOfInterestCategory.rawValue`, only to re-suggest a look |
| `tz` | string, optional | "Asia/Ho_Chi_Minh" | ≤ 64; paints the sky at the place's hour |

**Not stored**: the device's location (never read), street address lines, postcode, search text or history (the 5 "Recent" picks live only in this phone's UserDefaults and are purged), Apple's place identifiers, the country code.

**Who can read it**: the two members of the couple (rules: `isCoupleMember`). Cloud Functions receive documents in trigger events but never log or push place fields; push copy never names a place (lock screens are public). AI features never read `timeTreeMeta` (`buildRelationshipContext` reads users, couples, moods and anniversaries; P2 adds a comment there saying the garden must stay out). The widget never shows places.

**When it is deleted**: with its tree (let rest), with the couple's shared data (any version's "Delete shared data", account deletion), and by `onCouplePurged` when the couple document goes; device copies (cache, snapshots, recent picks) when the app leaves `.ready`.

### D4. Point-of-interest category → group → look

P9 maps MapKit's constants to a contract group with a `switch` (never by comparing raw strings); the contract maps the group to a scene (`GardenLookSuggestion.scene(group:countryCode:preset:)`), then `GardenLook.suggested(scene:forOurTree:)` picks the species.

| `MKPointOfInterestCategory` (¹ iOS 18+) | Group | Scene |
|---|---|---|
| `.beach`, `.surfing`¹, `.swimming`¹ | beach | Seaside |
| `.marina`, `.aquarium`, `.kayaking`¹, `.fishing`¹ | water | Seaside |
| `.park`, `.zoo`, `.golf`¹, `.miniGolf`¹ | park | Meadow |
| `.cafe`, `.bakery`, `.restaurant`, `.foodMarket`, `.brewery`, `.winery`, `.distillery`¹, `.store` | food | City Lights |
| `.nightlife`, `.theater`, `.movieTheater`, `.musicVenue`¹, `.hotel`, `.spa`¹, `.beauty`¹, `.fitnessCenter`, `.bowling`¹, `.conventionCenter`¹, `.planetarium`¹, `.skating`¹ | nightOut | City Lights |
| `.nationalPark`, `.campground`, `.hiking`¹, `.rockClimbing`¹, `.skiing`¹, `.rvPark`¹ | nature | Rice Terraces if the country is VN, LA, KH, TH, MM, PH, ID, CN, NP or BT; else Mountain Lake |
| `.museum`, `.landmark`¹, `.nationalMonument`¹, `.castle`¹, `.fortress`¹ | heritage | Lantern Town if the country is VN, CN, JP, KR, TW, HK, MO, TH, LA, KH, MM, SG or MY; else Campus |
| `.university`, `.school`, `.library` | campus | Campus |
| `.amusementPark`, `.stadium`, `.fairground`¹, `.baseball`¹, `.basketball`¹, `.soccer`¹, `.tennis`¹, `.volleyball`¹, `.goKart`¹, `.skatePark`¹ | sportsFun | Meadow |
| `.airport`, `.publicTransport`, `.carRental` | travel | Mountain Lake for "Our first trip", else City Lights |
| any other category | other | the preset's look (A3) |
| an address or a dropped pin | (none) | Home for "Our first home", else the preset's look |

All iOS 18 categories exist at the 18.6 minimum (verified against the iOS 26.1 SDK headers). The suggestion is only the starting value; the couple can pick any look.

### D5. The map view and snapshots

- **The places map** (`GardenMapView`, P9, pushed from the Garden sheet): muted standard style, no POIs, no user location. Each exact tree is an `Annotation`: a 34 pt circle in the look's accent with `tree.fill` (white), the tree's name under it. Each area tree is a `MapCircle` of 600 m (15% fill) with the name, never a pin. The camera fits all places with 20% padding (one place: an 800 m span). Tapping a tree opens its postcard. A **List** toggle shows the same places as an accessible list (VoiceOver). Empty: "None of your trees has a place yet. Add one from a tree's card."
- **Snapshots** (`GardenMapSnapshotter.shared`, P9): exact → an 800 m span centred on the spot with a tree pin drawn at `snapshot.point(for:)`; area → a 6 km span with a soft circle, no pin. Sizes: postcard 343×229, seed sheet 120 pt tall, lists 56×56; light and dark rendered separately. Memory `NSCache` (30 images) + disk `Library/Caches/GardenSnapshots/<sha256(lat4,lng4,precision,w,h,scheme)>.png` with a 30-day TTL; purged when the app leaves `.ready`. At most 2 snapshotters at once; a row that scrolls away cancels its job. Offline or failed → the scene swatch, silently. Lists never contain a live `Map`.
- **Attribution**: snapshot images do not carry Apple's legal label, so every snapshot view (`GardenSnapshotImage`) overlays, bottom-leading, a capsule "Apple Maps · Legal" (`JourneyFont.meta`, white on 55% black); **Legal** opens `https://www.apple.com/legal/internet-services/maps/`. The live maps carry Apple's own label.

### D6. Privacy: what changes and what must be said

**Principles**: no device location, ever; places are optional and chosen; "the area" lets a couple store a neighbourhood instead of a spot and is the default for addresses and pins; places never appear on a lock screen or in logs.

**What Apple receives**: the text typed into place search and the map areas shown (MapKit search, tiles and snapshots), under Apple's privacy policy. Nothing else about the couple.

**Privacy page (`index.html`, P4) — exact edits**, published on or before the day the garden build reaches users:
1. *Information We Collect → Couple data* becomes: "moods, reactions, messages, chat photos, goals, challenges, dreams, memories, anniversaries, the trees in your Journey garden and the notes you leave when you water them, the places you choose for those trees, and any content you create together."
2. A new block after *Photos & Media*:

   > **📍 Places in your garden**
   > You can give a tree in your Journey garden a real place, like where you first met. You choose it by searching or by dropping a pin on a map; Coupley never asks for or reads your phone's location. We store the place's name, its area (such as the district and city, never the street), and its map position: either the exact spot (to about 11 metres) or only the area (to about 1 kilometre), as you choose. Only you and your partner can see your places, and they never appear in notifications. Place searches and maps are provided by Apple Maps: what you type in the search and the map areas you look at are sent to Apple to find places and draw maps, under Apple's privacy policy, and are not stored by Coupley. Places are not used for ads and are not sent to our AI features. They are deleted when you let a tree rest, when you delete your shared data after disconnecting, or when you delete your account.

3. *How Your Data Is Shared* gains the bullet: "Place searches and maps in the Journey garden are provided by Apple, as described under Places in your garden."
4. *Last updated* (the privacy section's line, `index.html` line ~290): the date the page is published. The terms section's date stays.

**App Store privacy answers** (App Store Connect → App Privacy; the user's action, before the garden build is submitted):
- Add **Location → Precise Location**: collected, used for **App Functionality**, **linked to the user**, **not used for tracking**. Exact spots are stored to 4 decimals and describe where the couple has been; declaring them is the conservative reading.
- Add **Location → Coarse Location**, purpose **App Functionality**, **linked to the user**, **not used for tracking**: "area" places are stored to 2 decimals, which Apple defines as coarse (fewer than three decimal places). If Coarse Location is already declared for another purpose (for example AdMob's), add App Functionality to it and keep the existing purposes.
- **User Content → Other User Content** (tree titles, watering and seed notes): App Functionality, linked, no tracking, if not already declared for memories and chat.

**Privacy manifest** (`Coupley/PrivacyInfo.xcprivacy`, P4; one manifest for every configuration). `NSPrivacyCollectedDataTypes` (empty in 1.3) gets:
- now, on the branch: `NSPrivacyCollectedDataTypeOtherUserContent`, linked, not tracking, App Functionality (the pre-garden app's chat, letters and memories already justify it);
- **at Gate 3 only**, in the same change that sets `GardenFeature.isEnabled = true` for every configuration (its doc comment carries the Gate 3 checklist): `NSPrivacyCollectedDataTypePreciseLocation`, `NSPrivacyCollectedDataTypeLinked` = true, `NSPrivacyCollectedDataTypeTracking` = false, purposes `[NSPrivacyCollectedDataTypePurposeAppFunctionality]` (exact places), and `NSPrivacyCollectedDataTypeCoarseLocation`, linked, not tracking, App Functionality ("area" places). Until then a Release build has the garden off and stores no place, so a binary cut from the branch before Gate 3 (a hotfix, a TestFlight build) must not declare location it does not collect (review REL-1). Debug builds are never distributed, so no per-configuration manifest is needed.
- The manifest declares no collected data types in 1.3 although the app already stores photos, names and user ids; that pre-existing gap is flagged to the user (L2 #5) rather than changed silently. No new required-reason API is used (UserDefaults is already declared, CA92.1).

**FAQ (`FAQView.swift`, P4) — exact text**:
- *What is Journey?* becomes: "Journey is your story together. Your tree grows with every day since your start date, and the countdowns show your next anniversary and milestone. Your tree lives in a garden: give it a place, plant more trees together for the places that matter, and water them every couple of days. Memories you add appear on the timeline and as stars around the tree. Future letters between you show up there too: sealed ones hang from the branches until they open, then they bloom."
- New *What is the garden?*: "Your tree and up to seven more, each for a place or a moment that matters to you both, like where you first met. New trees are planted only when you both agree: one of you sends a seed, the other plants it. Water the garden every couple of days. One tap waters every tree, a little note can go with it, and your partner sees who watered and when."
- New *What if we forget to water?*: "Nothing bad happens. A tree never dies, never wilts and never loses its growth. Water just makes it greener and fuller for a day or two." (0.0 #3; it follows `GardenTreeLook.withersWhenThirsty` like the guide's Watering text, B6: with the switch on it reads "Nothing bad happens. A tree never dies and never loses its growth. It gets a little thirsty, then it rests, and a little water wakes it up again." Both answers stay in the code.)
- New *Who can see our places?*: "Only the two of you. You pick a place by searching or dropping a pin, and you choose whether to keep the exact spot or only the area. Coupley never reads your phone's location, and place names never appear in notifications. Place search uses Apple Maps."
- New *Why can't I change our start date on my own?*: "Your start date belongs to you both, so changing it is a suggestion your partner agrees to. If your partner still uses an older version of Coupley, they can change it from there."
- *Is my data private?* first sentence becomes: "Your moods, messages, goals, memories, garden, places and photos are visible only to you and your connected partner."
- *Where do our anniversary and other special dates go?* first sentence becomes: "Your anniversary countdown comes from your start date in Journey, …" (rest unchanged).
- Every sentence above stays true for existing couples (a start date set by one partner, Our tree recorded without a consent step) and for a partner on an older version.

---

## E. Data model

### E1. Overview

```
couples/{coupleId}
  timeTreeMeta/                     ONE flat collection, never a subcollection
    config                          EXISTING start date. Unchanged schema and rule. Our tree exists iff this exists.
    tree_our, tree_p1 … tree_p7     planted trees; the slot is the id (8 at most)
    seed_our                        proposal: plant Our tree (only while no config)
    seed_<uid>_1 … seed_<uid>_3     proposal: plant a place tree (each member creates only their own three ids)
    change_our, change_p1 … p7      proposal: change a planted tree
    rest_p1 … rest_p7               proposal: let a place tree go
    startdate                       proposal: new start date
    water_<20 alnum>                one watering (immutable)
    waterer_<uid>                   that member's last watering (12-hour rule)
users/{uid}
  capabilities.garden               int 1, written by every garden build for itself
  gardenPushToken                   string, = fcmToken when the token device runs a garden build
  notificationPreferences.garden    bool, default true (absent = true)
appConfig/garden                    rules probe + remote off switch (admin-written, optional)
gardenPushClaims/{key}              server only: push idempotency
gardenPushDaily/{uid}_{yyyymmdd}    server only: 6 garden pushes per recipient per UTC day
pushDryRun/{auto}                   emulator only: what a push would have been
```

Every garden document carries `docType` (`tree`, `proposal`, `water`, `waterer`). Writes are explicit dictionaries (never Codable), so key sets match the rules' `hasOnly` lists exactly (the Future Letters convention). Reads decode with `ServerTimestampBehavior.estimate` and treat every field added later as optional; malformed documents are skipped (I7). Field names are unique per document type so queries need no composite index (only waterings have `wateredAt`).

### E2. `config` and how the 1.2 start date maps in

| Field | Type | Written by |
|---|---|---|
| `startDate` | timestamp: 10:00 UTC of the picked day from the overhaul build on; any instant from 1.1/1.2 | legacy apps directly; garden apps only in the first-planting transaction (raw `seed_our.startDay`) and the start-date agreement (raw `startdate.startDay`) |
| `setBy` | string uid | legacy apps; first planting: the **proposer** (it is their seed) |
| `setByName` | string, optional | legacy apps; first planting: the proposer's display name if known, else absent |
| `setAt` | timestamp | legacy apps (device clock); first planting: server time |
| `updatedAt` | timestamp | legacy apps (device clock); garden writes: server time |

Garden apps add **no field** here and read `startDate` only through `JourneyCalendarDay.localDay(ofStored:)`. The first planting uses `setData` (no merge: `config` is checked absent in the same transaction); the agreement uses `updateData(["startDate", "updatedAt"])`, keeping `setBy`/`setByName`/`setAt` exactly as a 1.2 edit does. A 1.2 reader decodes both unchanged.

Mapping existing couples: `config` exists, in either date format → Our tree is planted (`origin: legacy`); until `tree_our` is recorded, the client synthesises it (`GardenTree.unrecordedOurTree`). No backfill job, no migration write other than the recording transaction.

### E3. `tree_<slot>`

| Field | Type | Set when | Written by |
|---|---|---|---|
| `docType` | `"tree"` | create | planter / recorder |
| `slot` | `"our"`, `"p1"`…`"p7"` (= id suffix); immutable | create | planter / recorder |
| `key` | string 8–64 `[A-Za-z0-9-]` (UUID); immutable | create | from the seed / new UUID when recording |
| `title` | string 1–160 (client 40 graphemes) | create, change | from the seed / change ("Our tree" for Our tree) |
| `preset` | token (`ourTree` only on `tree_our`) | create, change | from the seed / change |
| `momentDay` | timestamp (stored calendar day), optional, never on `tree_our` | create, change | from the seed / change (raw copy) |
| `place` | map (D3), optional | create, change | from the seed / change (raw copy) |
| `scene`, `species` | tokens `^[a-zA-Z]{1,32}$` | create, change, look | seed / change / either partner |
| `origin` | `"together"` \| `"legacy"`; immutable | create | planter / recorder |
| `plantedAt` | server timestamp; immutable; absent when legacy | planting | the planter (accepter) |
| `plantedBy` | `[proposerUid, planterUid]`; immutable; absent when legacy | planting | the planter |
| `agreedStartDay` | timestamp; `tree_our` only, always there | planting, start-date agreement, recording | accepter / recorder (raw copy) |
| `agreementKind` | `plant` \| `change` \| `startDate` \| `recorded` | every agreement | accepter / recorder |
| `agreementBy` | `[proposer, accepter]`, or `[recorder]` | every agreement | accepter / recorder |
| `agreementAt` | server timestamp | every agreement | accepter / recorder |
| `fromProposal` | proposal id, absent when recorded | planting, change, start date | accepter |
| `lookBy`, `lookAt` | uid, server timestamp, optional | look change | the changer |
| `prevScene`, `prevSpecies` | tokens, optional | look change | the changer ("Change it back") |
| `updatedAt` | server timestamp | every write | everyone |

### E4. Proposals (`seed_our`, `seed_<uid>_<n>`, `change_<slot>`, `rest_<slot>`, `startdate`)

- **Ids**: a place seed is `seed_<creator uid>_<n>`, n ∈ {1, 2, 3}, the creator's first free number, chosen inside the sending transaction (T0). The id names the creator, not the current proposer: a counter keeps it. Ids are reused once a seed is planted, taken back or let go, so device state is keyed by the seed's `key` (a UUID), never by its id (E11).
- **Versions**: `at` (server time of the latest create, edit or counter) doubles as the version stamp. A consent action carries `GardenProposalVersion(rev, at in whole ms)` from the snapshot it showed; the transaction compares both with the proposal it reads. A proposal re-created under the same fixed id restarts at `rev 1` with a new `at`, so it never passes for the version the user saw.

| Field | Type | Notes |
|---|---|---|
| `docType` | `"proposal"` | |
| `kind` | `plant` \| `change` \| `rest` \| `startDate`; immutable | |
| `slot` | `our` (seed_our, startdate, change_our), `new` (place seed), `p1`…`p7` (change, rest); immutable | |
| `key` | string; immutable | plant: a new UUID (the future tree's key); others: the tree's key |
| `by` | uid | the current proposer: the creator, or whoever answered with their own version |
| `at` | server timestamp | every create, edit, counter |
| `rev` | int | 1 on create, +1 on every edit or counter |
| `note` | string ≤ 560 (client 140 graphemes), optional | |
| `startDay` | timestamp (stored day) | `seed_our` (required) and `startdate` |
| `fromStartDay` | timestamp | `startdate` only: `config.startDate` as the proposer saw it (raw copy; rules ±1 s) |
| `title`, `preset`, `momentDay`, `place`, `scene`, `species` | as E3 | `plant` and `change` (the full intended content, look included); never on `rest`/`startDate` |

### E5. `water_<id>`

Id: `"water_" +` a Firestore auto id generated on the phone before the write (it seeds the effect).

| Field | Type | Written by |
|---|---|---|
| `docType` | `"water"` | the waterer |
| `by` | uid | the waterer |
| `wateredAt` | server timestamp (`request.time`) | the waterer, `FieldValue.serverTimestamp()` |
| `note` | string ≤ 400 (client 100 graphemes / 400 UTF-8 bytes), optional | the waterer |
| `effect` | token (`GardenEffect.rawValue`) | the waterer |

Never updated; deleted only in a purge. "Together", "first" and "returned" are derived from server times, never stored, so a write queued offline can never carry a stale claim (the stored `effect` is only what the waterer saw).

### E6. `waterer_<uid>`

| Field | Type |
|---|---|
| `docType` | `"waterer"` |
| `lastWateredAt` | server timestamp: the same `request.time` as the watering in the same batch |
| `lastWateringId` | that watering's id |

The rules allow a new `lastWateredAt` only after 11 h 50 min of server time. Readable by both partners (times only).

### E7. `users/{uid}` (additive, optional fields)

| Field | Written by | Read by |
|---|---|---|
| `capabilities.garden` (int 1) | the garden VM at `start()`: `setData(["capabilities": ["garden": 1]], merge: true)` (confirmed, fire and forget) | the partner's garden app ("can answer seeds"); never compared as a version |
| `gardenPushToken` (string) | `NotificationService.saveFCMToken` in the same merge as `fcmToken` (garden builds only); deleted by `clearFCMToken` | the push function: garden pushes only when `gardenPushToken == fcmToken` (the token device runs a garden build) |
| `notificationPreferences.garden` (bool) | `NotificationService.savePreferences` (via `firestorePrefsDict`); absent = true | the push function; mirrored to `GardenDefaultsKey.notificationsEnabled` for local reminders |

Legacy builds' `setData(merge: true)` writes to the user document never remove these (deep merge).

### E8. `appConfig/garden`

Optional, admin-written (console). Absent ⇒ enabled. `{enabled: false}` ⇒ `disabledRemotely`. Readable by any signed-in user (`get` only); its rule is the "rules deployed" probe (D3).

The switch-off holds on both sides:
- **App**: the last definitive answer is kept per backend (`remoteDisabled.<backend>`, E11, kept on purge), so a cold, offline or slow launch keeps the garden off, and its reminders cancelled, until the backend answers enabled again.
- **Push function**: `onTimeTreeMetaWritten` reads this document after `classify` and before any claim, read or write, and sends no garden push while `enabled === false` (G3, `garden.isSwitchedOff`). A missing document or field means on.

### E9. Server-only collections (Admin SDK; the catch-all rule denies clients)

- `gardenPushClaims/{key}`: `{at}`; created with `create()` before sending; keys `w_{c}_{wateringId}`, `p_{c}_{proposalId}_{atMs}`, `a_{c}_{slot}_{agreementAtMs}`; deleted after 7 days by `cleanupOldData`.
- `gardenPushDaily/{uid}_{yyyymmdd}`: `{count, day, at}`; transaction; ≤ 6; deleted after 7 days.
- `pushDryRun/{auto}`: `{userId, type, title, body, data, options, at}`; only when `FUNCTIONS_EMULATOR === "true"`.

### E10. Listeners and queries (no new indexes)

| Listener / query | Owner | Index |
|---|---|---|
| `timeTreeMeta/config` (metadata changes on; the anchor service's cache-miss rule) | `GardenViewModel` via the service; unchanged `TimeTreeViewModel` and `WidgetSyncService` listeners stay | doc |
| `timeTreeMeta` `whereField("docType", in: ["tree","proposal","waterer"])` (metadata on) | `GardenViewModel` | single-field |
| `timeTreeMeta` `order(by: "wateredAt", descending: true).limit(to: 60)` (metadata on) | `GardenViewModel` | single-field |
| `timeTreeMeta` `order(by: "wateredAt", descending: true).limit(to: 3)` (metadata on; newest confirmed) | `WidgetSyncService` (reminders) | single-field |
| journal pages `order(by: wateredAt desc).start(after: [ts]).limit(50)` | `GardenViewModel` | single-field |
| `users/{partnerId}` | `GardenViewModel` | doc |
| `appConfig/garden` get | `GardenViewModel.start()` | doc |
| function: `where("wateredAt", ">=", t−24h).where("wateredAt", "<", t)`, `where("wateredAt", "<", t).orderBy desc limit 1`, `where("docType", "==", "tree")` | `onTimeTreeMetaWritten` | single-field |

`firestore.indexes.json` does not change.

### E11. Device storage (all keys `coupley.garden.*`, `GardenDefaultsKey`)

| Key | Holds | Purged on leaving `.ready` |
|---|---|---|
| `cache.{c}` | trees (with places and looks) and the last 10 waterings without notes, JSON, for an offline first paint | yes |
| `seenWatering.{c}` | id of the newest partner watering shown on Journey | yes |
| `ceremonySeen.{c}.{key}` | the ceremony played here | yes |
| `inviteDismissed.{c}` | "Give your tree a home" answered | yes |
| `snoozed.{c}.{seedKey}` | "Not now" until (date); seeds only, keyed by the seed's key because ids are reused | yes |
| `noticeSeen.{c}.{id}` | one-time notices dismissed | yes |
| `homeDraft.{c}` | a voided `seed_our`'s place and look (contains a place) | yes |
| `selectedSlot.{c}` | the pager's page | yes |
| `myOpenSeeds.{c}` | JSON map seed key → {id, title, preset, setAside} of the seeds I sent, keyed by the key because ids are reused (to detect "set aside" and title its notice) | yes |
| `lastWateringMs.{c}` | latest server watering time (reminder re-plan from a push) | yes |
| `activeCoupleId` | the bound couple (WidgetSyncService) | removed on unbind |
| `notificationsEnabled` | mirror of the Garden toggle | yes |
| `startDateSeen.{c}` | the start date this device last saw agreed or acknowledged, so a start date changed any other way is told once per device (SEC-2) | yes |
| `serverOffset.<backend>` | estimated server clock offset, per backend (`<Firebase project id>@<Firestore host>`), written only by the real backend | yes |
| `rulesVerified.<backend>` | the probe answered (enabled or switched off) from this backend; a DEBUG emulator run or the lab never vouches for production | **kept** |
| `remoteDisabled.<backend>` | the backend's last definitive answer was `appConfig/garden {enabled: false}` (E8) | **kept** |
| `Recent` places (P9) | last 5 picks | yes (P9's `purge()`) |
| `Library/Caches/GardenSnapshots/` | map snapshots | yes (P9's `purge()`) |
| `Library/Caches/GardenBackdrops/v<artVersion>/` | renders of our own scene art (no user data), ≤ 48 MB | **kept** (only the memory tier is cleared; iOS may purge it) |

---

## F. Firestore rules and the tests that prove them

### F1. Rule text (P1)

**Replaces only** the current `match /timeTreeMeta/{docId}` block (four lines, fully open) inside `match /couples/{coupleId}`, and **adds** a top-level `appConfig` match before the catch-all. Uses the file's existing helpers `incoming()`, `coupleDoc()`, `isCoupleMember()`, `isDisconnectedCouple()`, `isSignedIn()`. Each operation is ONE `allow` statement whose `||` branches start with a document-id test (no document access), cheapest first, so a 300-document purge batch from 1.2 costs one couple read.

```
      // ---- Time Tree metadata: the start date and the shared garden ----
      //
      // ONE flat collection, never a subcollection: every shared-data purge
      // since 1.2 deletes this collection page by page, so the garden's
      // places and notes leave with it.
      //
      //   config            The start date. Exactly as open as 1.1/1.2 need it
      //                     (they set it directly). Every day count reads it.
      //   tree_our          Our tree; tree_p1 … tree_p7 place trees. The slot is
      //                     the id, so a garden holds 8 trees at most.
      //   seed_our          A proposal to plant Our tree (only while no config).
      //   seed_<uid>_<n>    A proposal to plant a place tree; n is 1-3 and a
      //                     member creates only their own ids (3 open at most).
      //   change_<slot>     A proposed new name / place / moment / look.
      //   rest_p1 … p7      A proposal to let a place tree go.
      //   startdate         A proposed new start date.
      //   water_<20>        One watering: who, server time, note, effect.
      //   waterer_<uid>     That member's last watering (one per 12 hours).
      //
      // A tree is planted or changed only by the member who did NOT make the
      // proposal's latest version, in ONE transaction that copies it exactly
      // and deletes it. Every time a partner is shown is request.time.
      match /timeTreeMeta/{docId} {

        function meta(id) {
          return /databases/$(database)/documents/couples/$(coupleId)/timeTreeMeta/$(id);
        }
        function me() { return request.auth.uid; }
        function active() {
          return isCoupleMember(coupleId)
            && coupleDoc(coupleId).get('status', 'active') != 'disconnected';
        }
        function changed() { return incoming().diff(resource.data).affectedKeys(); }

        // Within a second: Date <-> Timestamp round trips in the iOS SDK can
        // move an instant by a microsecond, and 1.1/1.2 store raw instants.
        function sameInstant(a, b) {
          return a is timestamp && b is timestamp
            && a > b - duration.value(1, 's')
            && a < b + duration.value(1, 's');
        }
        // A calendar day (JourneyCalendarDay.storedMoment, 10:00 UTC today).
        // The hour is NEVER checked.
        function isDay(t) {
          return t is timestamp
            && t > timestamp.date(1900, 1, 1)
            && t < request.time + duration.value(2, 'd');
        }
        function isText(s, max) { return s is string && s.size() > 0 && s.size() <= max; }
        function optText(m, k, max) { return !(k in m) || isText(m[k], max); }
        function isToken(s) { return s is string && s.matches('^[a-zA-Z]{1,32}$'); }
        function isKey(s) { return s is string && s.matches('^[A-Za-z0-9-]{8,64}$'); }
        function isRounded(x, scale) {
          return math.abs(x * scale - math.round(x * scale)) < 0.000001;
        }

        // A place the couple chose. "Only the area" is a promise the server keeps.
        function isPlace(p) {
          return p is map
            && p.keys().hasAll(['name', 'lat', 'lng', 'precision'])
            && p.keys().hasOnly(['name', 'locality', 'lat', 'lng', 'precision', 'poi', 'tz'])
            && isText(p.name, 320)
            && optText(p, 'locality', 320)
            && optText(p, 'poi', 64)
            && optText(p, 'tz', 64)
            && p.lat is number && p.lat >= -90 && p.lat <= 90
            && p.lng is number && p.lng >= -180 && p.lng <= 180
            && ((p.precision == 'exact' && isRounded(p.lat, 10000) && isRounded(p.lng, 10000))
                || (p.precision == 'area' && isRounded(p.lat, 100) && isRounded(p.lng, 100)));
        }

        // What a tree is. `slot`: 'our', 'new' (a place seed) or 'p1'…'p7'.
        // Scene, species and preset are tokens, not lists: a later app may add
        // looks without a rules deploy (unknown ones draw as Meadow / oak).
        function isContent(m, slot) {
          return isText(m.title, 160)
            && isToken(m.preset) && isToken(m.scene) && isToken(m.species)
            && (!('place' in m) || isPlace(m.place))
            && (slot == 'our'
                  ? (m.preset == 'ourTree' && !('momentDay' in m))
                  : (m.preset != 'ourTree' && (!('momentDay' in m) || isDay(m.momentDay))));
        }
        function sameDay(a, b) {
          return (!('momentDay' in a) && !('momentDay' in b))
            || ('momentDay' in a && 'momentDay' in b && sameInstant(a.momentDay, b.momentDay));
        }
        function sameContent(a, b) {
          return a.title == b.title && a.preset == b.preset
            && a.scene == b.scene && a.species == b.species
            && a.get('place', null) == b.get('place', null)
            && sameDay(a, b);
        }

        function isTreeDoc() { return docId.matches('^tree_(our|p[1-7])$'); }
        function isPlaceSeedDoc() { return docId.matches('^seed_[A-Za-z0-9]{1,128}_[1-3]$'); }
        // Creating a place seed: only my own three ids (string equality, no
        // regex built from the uid), so open seeds are bounded by construction.
        function isMySeedDoc() {
          return docId == 'seed_' + me() + '_1' || docId == 'seed_' + me() + '_2'
            || docId == 'seed_' + me() + '_3';
        }
        function isProposalDoc() {
          return docId == 'seed_our' || docId == 'startdate' || isPlaceSeedDoc()
            || docId.matches('^change_(our|p[1-7])$') || docId.matches('^rest_p[1-7]$');
        }
        function isWaterDoc() { return docId.matches('^water_[A-Za-z0-9]{20}$'); }
        function isWatererDoc() { return docId == 'waterer_' + me(); }

        // ---------- proposals ----------

        function proposalKeys() {
          return ['docType', 'kind', 'slot', 'key', 'by', 'at', 'rev', 'note',
                  'startDay', 'fromStartDay',
                  'title', 'preset', 'momentDay', 'place', 'scene', 'species'];
        }
        function treeOf(slot) { return get(meta('tree_' + slot)).data; }

        // The id says what a proposal is about, so two of a kind collide
        // instead of piling up. Our tree's seed is void once a start date
        // exists; a start-date suggestion is void once the date moves.
        function proposalFits(m) {
          return (docId == 'seed_our' && m.kind == 'plant' && m.slot == 'our'
                    && !exists(meta('config'))
                    && isDay(m.startDay) && !('fromStartDay' in m)
                    && isContent(m, 'our'))
            || (isPlaceSeedDoc() && m.kind == 'plant' && m.slot == 'new'
                    && exists(meta('config'))
                    && !m.keys().hasAny(['startDay', 'fromStartDay'])
                    && isContent(m, 'new'))
            || (docId == 'change_' + m.slot && m.kind == 'change'
                    && exists(meta('tree_' + m.slot)) && m.key == treeOf(m.slot).key
                    && !m.keys().hasAny(['startDay', 'fromStartDay'])
                    && isContent(m, m.slot))
            || (docId == 'rest_' + m.slot && m.kind == 'rest' && m.slot != 'our'
                    && exists(meta('tree_' + m.slot)) && m.key == treeOf(m.slot).key
                    && !m.keys().hasAny(['startDay', 'fromStartDay', 'title', 'preset',
                                         'momentDay', 'place', 'scene', 'species']))
            || (docId == 'startdate' && m.kind == 'startDate' && m.slot == 'our'
                    && exists(meta('tree_our')) && m.key == treeOf('our').key
                    && isDay(m.startDay)
                    && sameInstant(m.fromStartDay, get(meta('config')).data.startDate)
                    && !m.keys().hasAny(['title', 'preset', 'momentDay', 'place',
                                         'scene', 'species']));
        }

        // Created by its proposer, or answered with a new version: whoever
        // writes it becomes the proposer, and the OTHER member must answer.
        function isProposal(m, previousRev) {
          return m.keys().hasOnly(proposalKeys())
            && m.docType == 'proposal'
            && isKey(m.key)
            && m.by == me()
            && m.at == request.time
            && m.rev == previousRev + 1
            && optText(m, 'note', 560)
            && proposalFits(m);
        }

        // ---------- trees ----------

        function treeKeys() {
          return ['docType', 'slot', 'key', 'title', 'preset', 'momentDay', 'place',
                  'scene', 'species', 'origin', 'plantedAt', 'plantedBy', 'agreedStartDay',
                  'agreementKind', 'agreementBy', 'agreementAt', 'fromProposal',
                  'lookBy', 'lookAt', 'prevScene', 'prevSpecies', 'updatedAt'];
        }
        function isTree(m) {
          return m.keys().hasOnly(treeKeys())
            && m.docType == 'tree'
            && docId == 'tree_' + m.slot
            && isKey(m.key)
            && isContent(m, m.slot)
            && ((m.slot == 'our') == ('agreedStartDay' in m))
            && m.updatedAt == request.time;
        }

        // Planted together: the partner's seed, exactly, deleted in this same
        // transaction, stamped with the server's time and both names. Our
        // tree's first planting also writes the start date, in the 1.2 format.
        function plantedFrom(m) {
          let id = m.fromProposal;
          let p = get(meta(id)).data;
          return (id == 'seed_our' || id.matches('^seed_[A-Za-z0-9]{1,128}_[1-3]$'))
            && exists(meta(id)) && !existsAfter(meta(id))
            && p.kind == 'plant'
            && p.by != me()
            && p.by in coupleDoc(coupleId).userIds
            && ((m.slot == 'our') == (p.slot == 'our'))
            && m.key == p.key
            && sameContent(m, p)
            && m.origin == 'together'
            && m.plantedAt == request.time
            && m.plantedBy == [p.by, me()]
            && m.agreementKind == 'plant'
            && m.agreementBy == [p.by, me()]
            && m.agreementAt == request.time
            && !m.keys().hasAny(['lookBy', 'lookAt', 'prevScene', 'prevSpecies'])
            && (m.slot != 'our'
                || (!exists(meta('config'))
                    && sameInstant(getAfter(meta('config')).data.startDate, p.startDay)
                    && sameInstant(m.agreedStartDay, p.startDay)));
        }

        // Our tree from a start date set before the garden (or by an older
        // app): recorded as it is, by either partner. Never with a place.
        function recordedLegacy(m) {
          return m.slot == 'our'
            && exists(meta('config'))
            && m.origin == 'legacy'
            && !m.keys().hasAny(['momentDay', 'place', 'plantedAt', 'plantedBy', 'fromProposal',
                                 'lookBy', 'lookAt', 'prevScene', 'prevSpecies'])
            && sameInstant(m.agreedStartDay, get(meta('config')).data.startDate)
            && m.agreementKind == 'recorded'
            && m.agreementBy == [me()]
            && m.agreementAt == request.time;
        }

        function keepsIdentity() {
          return incoming().slot == resource.data.slot
            && incoming().key == resource.data.key
            && incoming().origin == resource.data.origin
            && incoming().get('plantedAt', null) == resource.data.get('plantedAt', null)
            && incoming().get('plantedBy', null) == resource.data.get('plantedBy', null);
        }
        // A new look, by either of you, at any time: only the look changes.
        function looksChanged() {
          return changed().hasOnly(['scene', 'species', 'prevScene', 'prevSpecies',
                                    'lookBy', 'lookAt', 'updatedAt'])
            && isToken(incoming().prevScene) && isToken(incoming().prevSpecies)
            && incoming().lookBy == me()
            && incoming().lookAt == request.time;
        }
        // A change the partner proposed: exactly its content, deleted with it.
        function changedFrom(m) {
          let id = 'change_' + m.slot;
          let p = get(meta(id)).data;
          return m.fromProposal == id
            && exists(meta(id)) && !existsAfter(meta(id))
            && p.by != me() && p.by in coupleDoc(coupleId).userIds
            && p.key == m.key
            && sameContent(m, p)
            && m.agreementKind == 'change'
            && m.agreementBy == [p.by, me()]
            && m.agreementAt == request.time
            && changed().hasOnly(['title', 'preset', 'momentDay', 'place', 'scene', 'species',
                                  'fromProposal', 'agreementKind', 'agreementBy',
                                  'agreementAt', 'updatedAt']);
        }
        // A start date the partner proposed against the date as it STILL is,
        // written to config in the same transaction.
        function startDateFrom(m) {
          let p = get(meta('startdate')).data;
          return m.slot == 'our'
            && m.fromProposal == 'startdate'
            && exists(meta('startdate')) && !existsAfter(meta('startdate'))
            && p.by != me() && p.by in coupleDoc(coupleId).userIds
            && p.key == m.key
            && sameInstant(get(meta('config')).data.startDate, p.fromStartDay)
            && sameInstant(getAfter(meta('config')).data.startDate, p.startDay)
            && sameInstant(m.agreedStartDay, p.startDay)
            && m.agreementKind == 'startDate'
            && m.agreementBy == [p.by, me()]
            && m.agreementAt == request.time
            && changed().hasOnly(['agreedStartDay', 'fromProposal', 'agreementKind',
                                  'agreementBy', 'agreementAt', 'updatedAt']);
        }
        // An older app changed config directly: recorded as it now is.
        function reRecorded(m) {
          return m.slot == 'our'
            && sameInstant(m.agreedStartDay, get(meta('config')).data.startDate)
            && m.agreementKind == 'recorded'
            && m.agreementBy == [me()]
            && m.agreementAt == request.time
            && changed().hasOnly(['agreedStartDay', 'agreementKind', 'agreementBy',
                                  'agreementAt', 'updatedAt']);
        }

        // ---------- waterings ----------

        // The watering and the waterer's own turn travel in one batch; the
        // time is the server's; Our tree must exist.
        function isWatering(m) {
          return m.keys().hasOnly(['docType', 'by', 'wateredAt', 'note', 'effect'])
            && m.docType == 'water'
            && m.by == me()
            && m.wateredAt == request.time
            && optText(m, 'note', 400)
            && isToken(m.effect)
            && exists(meta('config'))
            && getAfter(meta('waterer_' + me())).data.lastWateringId == docId
            && getAfter(meta('waterer_' + me())).data.lastWateredAt == request.time;
        }
        function isTurn(m) {
          return m.keys().hasOnly(['docType', 'lastWateredAt', 'lastWateringId'])
            && m.docType == 'waterer'
            && m.lastWateredAt == request.time
            && m.lastWateringId is string
            && m.lastWateringId.matches('^water_[A-Za-z0-9]{20}$')
            && !exists(meta(m.lastWateringId))
            && existsAfter(meta(m.lastWateringId));
        }

        // ---------- access ----------

        allow read: if isCoupleMember(coupleId);

        allow create: if (docId == 'config' && isCoupleMember(coupleId))   // unchanged since 1.2
          || (isProposalDoc() && active() && isProposal(incoming(), 0)
              && (!isPlaceSeedDoc() || isMySeedDoc()))
          || (isTreeDoc() && active() && isTree(incoming())
              && (plantedFrom(incoming()) || recordedLegacy(incoming())))
          || (isWaterDoc() && active() && isWatering(incoming()))
          || (isWatererDoc() && active() && isTurn(incoming()));

        allow update: if (docId == 'config' && isCoupleMember(coupleId))   // unchanged since 1.2
          || (isProposalDoc() && active()
              && isProposal(incoming(), resource.data.rev)
              && incoming().kind == resource.data.kind
              && incoming().slot == resource.data.slot
              && incoming().key == resource.data.key)
          || (isTreeDoc() && active() && isTree(incoming()) && keepsIdentity()
              && (looksChanged() || changedFrom(incoming())
                  || startDateFrom(incoming()) || reRecorded(incoming())))
          // Once per 12 hours per person (11 h 50 min of grace).
          || (isWatererDoc() && active() && isTurn(incoming())
              && request.time > resource.data.lastWateredAt + duration.value(710, 'm'));

        // The purge (any app version) right after config, so a 300-document
        // batch costs one couple read; then the garden's own deletes: any
        // member may delete a proposal (taken back, let go, kept, carried
        // out: the tree rules check that write); a place tree goes only with
        // the partner's rest request, in the same transaction.
        allow delete: if (docId == 'config' && isCoupleMember(coupleId))   // unchanged since 1.2
          || isDisconnectedCouple(coupleId)
          || (isProposalDoc() && isCoupleMember(coupleId))
          || (docId.matches('^tree_p[1-7]$') && active()
              && exists(meta('rest_' + docId.split('_')[1]))
              && !existsAfter(meta('rest_' + docId.split('_')[1]))
              && get(meta('rest_' + docId.split('_')[1])).data.by != me()
              && get(meta('rest_' + docId.split('_')[1])).data.key == resource.data.key);
      }
```

Top level, before the catch-all:

```
    // ------------------------------------------------------------------
    // /appConfig/{docId}
    // ------------------------------------------------------------------
    // Read-only app switches. appConfig/garden doubles as the probe that
    // tells the app the garden rules are deployed (they ship together).
    match /appConfig/{docId} {
      allow get: if isSignedIn();
      allow list, write: if false;
    }
```

Header comment: the data-model list gains `/timeTreeMeta/{id} — the start date (open, 1.1/1.2 write it) and the garden (trees, proposals, waterings, waterers)` and `/appConfig/{docId} — read-only app switches`; the security model gains: "* timeTreeMeta: config stays open; garden trees are written only by the member who did not make the proposal (or recorded from an existing start date), one watering per member per 12 hours, all times request.time."

### F2. Notes

- **Access budget** (limit 20 per batch/transaction, cached gets count once): first planting ≈ 5 distinct documents (couple, `seed_our` before/after, `config` before/after); a watering ≈ 5 (couple, `config`, `waterer_<me>` after, `water_<id>` before/after); a start-date agreement ≈ 5; a 300-delete purge batch 1 (couple). Test 46 checks a mixed purge batch.
- **Short-circuit**: `&&`/`||` short-circuit in rules; an error in one `||` branch does not fail a branch that holds; each operation has one `allow` statement so evaluation order is explicit.
- **Deployed as one file**: the working tree's hardened `/memories` and Future Letters blocks are not deployed yet either. The deploy gate is ONE emulator run of every suite (memories, futureLetters, garden) plus the mutants, three times in a row.
- **After legacy builds are retired** (not now): tighten `config` so `startDate` changes only alongside a garden agreement (`getAfter(tree_our).agreedStartDay` within 1 s of `incoming().startDate`). Until then legacy writes must keep landing (test 4).
- **Seed bound**: a place seed can only be *created* under `seed_<own uid>_1…3` (`isMySeedDoc`, string equality), so at most 3 exist per creator and 6 per couple; updates (edits, counters) and deletes keep the generic pattern. Firebase Auth uids are base-62 (28 characters); a uid outside `[A-Za-z0-9]{1,128}` could not send place seeds, which no current sign-in method produces.
- **Versions (ABA)** need no rule: the rules already require `at == request.time` on every create, edit and counter, so every version has a distinct `at`; the client's transaction compares it (I4).

### F3. Emulator tests (`firestore-tests/garden.rules.test.mjs`, P1)

Its own database (`forDatabase('garden-rules')`, because `node --test` runs files in parallel). Every server time is a top-level field and every write is a full `set`, a top-level `update` mask, or a delete, so **`emulator.mjs` needs no change**. A transaction's commit is evaluated like a batch, so each transaction is tested as one `commit([...])`. Denials must be 403 (never 400/404), like the existing files.

```js
import { test, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { forDatabase, SERVER_TIME, value } from './emulator.mjs'

const { reset, commit, setDoc, getDoc, listDocs, W } = forDatabase('garden-rules')
const A = 'alice', B = 'bob', M = 'mallory'
const C = 'couples/c1', META = `${C}/timeTreeMeta`
const D = (id) => `${META}/${id}`
const HOUR = 3600e3, DAY = 24 * HOUR
const at = (ms) => new Date(Date.now() + ms)
const day10 = (y, m, d) => new Date(Date.UTC(y, m - 1, d, 10))      // storedMoment
const SEED = `seed_${A}_1`, W1 = 'water_' + 'w'.repeat(20)
const ok = (r, why = '') => assert.ok(r.ok, `expected ALLOW ${why}: ${r.status} ${JSON.stringify(r.body)}`)
const no = (r, why = '') => assert.equal(r.status, 403, `expected DENY (403) ${why}, got ${r.status} ${JSON.stringify(r.body)}`)

const place = { name: 'Café Giảng', locality: 'Hoàn Kiếm, Hà Nội', lat: 21.0345, lng: 105.8543,
                precision: 'exact', poi: 'MKPOICategoryCafe', tz: 'Asia/Ho_Chi_Minh' }
const content = { title: 'Where we first met', preset: 'firstMet', momentDay: day10(2023, 3, 12),
                  place, scene: 'cityLights', species: 'cherry' }
const seed = (o = {}, id = SEED, by = A) =>
  W.set(D(id), { docType: 'proposal', kind: 'plant', slot: 'new', key: 'k-seed-0001', by,
                 at: SERVER_TIME, rev: 1, note: 'Remember?', ...content, ...o })
const plant = (slot = 'p1', o = {}, by = B, proposer = A, id = SEED) => [
  W.set(D(`tree_${slot}`), { docType: 'tree', slot, key: 'k-seed-0001', ...content, origin: 'together',
    plantedAt: SERVER_TIME, plantedBy: [proposer, by], agreementKind: 'plant',
    agreementBy: [proposer, by], agreementAt: SERVER_TIME, fromProposal: id, updatedAt: SERVER_TIME, ...o }),
  W.del(D(id)),
]
const water = (id = W1, by = A, o = {}) => [
  W.set(D(id), { docType: 'water', by, wateredAt: SERVER_TIME, effect: 'can', ...o }),
  W.set(D(`waterer_${by}`), { docType: 'waterer', lastWateredAt: SERVER_TIME, lastWateringId: id }),
]
const couple = (status = 'active') => setDoc(C, { userIds: [A, B], status }, 'owner')
const anchor = (startDate = day10(2024, 1, 26)) =>
  setDoc(D('config'), { startDate, setBy: A, setAt: at(-DAY), updatedAt: at(-DAY) }, 'owner')
const ourTree = (o = {}) => setDoc(D('tree_our'), { docType: 'tree', slot: 'our', key: 'k-our-00001',
  title: 'Our tree', preset: 'ourTree', scene: 'meadow', species: 'oak', origin: 'legacy',
  agreedStartDay: day10(2024, 1, 26), agreementKind: 'recorded', agreementBy: [A],
  agreementAt: at(-DAY), updatedAt: at(-DAY), ...o }, 'owner')

beforeEach(async () => { await reset(); ok(await couple(), 'seed couple') })
```

| # | Test | Expect |
|---|---|---|
| **config: 1.2 parity** | | |
| 1 | a member creates `config` with the 1.2 payload (client `setAt`/`updatedAt`, a raw-instant `startDate`) | allow |
| 2 | a member merges an edit with the `setByName` delete; a member deletes `config` | allow, allow |
| 3 | outsider / signed-out write to `config` | deny |
| 4 | a 1.2 direct start-date edit lands while a `startdate` suggestion waits | allow |
| **probe** | | |
| 5 | signed-in get `appConfig/garden` (missing → 404, present → 200, never 403); signed-out get; any write | allow, deny, deny |
| 6 | list `appConfig` | deny |
| **unknown ids** | | |
| 7 | create `notes`, `tree_p8`, `tree_new`, `water_short`, `seed_x`, `seed_` + 20 alphanumerics (the old pattern), `change_p8`, `rest_our`, `waterer_bob` (by A) | deny each |
| **seeds** | | |
| 8 | A sends a place seed (config exists) | allow |
| 9 | a place seed without `config` | deny |
| 10 | malformed: `by: B` under A; client `at`; `rev: 2`; extra key `plantedAt`; title of 161 chars; empty title; note of 561; scene `sea side`; `preset: ourTree`; `slot: 'p1'`; `momentDay` +3 days; outsider; signed out; disconnected couple | deny each |
| 11 | place validation: `lat: 91`; `lng: 'east'`; no `precision`; extra `accuracy`; `area` with 21.0345; `exact` with 5 decimals | deny each; `area` 21.03/105.85 and `exact` 4 dp allow |
| 12 | A edits her seed (`rev: 2`, same kind/slot/key, new `at`) | allow; changing key, slot or kind deny; `rev: 3` deny; `rev: 1` deny |
| 13 | B counters (`by: B`, `rev: 2`) | allow; B updating while keeping `by: A` deny |
| 14 | `seed_our` without `config` | allow; with `config` deny; `seed_alice_1` with `slot: 'our'` deny |
| 15 | A deletes, B deletes a seed; outsider deletes | allow, allow, deny |
| **planting** | | |
| 16 | B plants A's seed (tree_p1 + delete seed) | allow; stored `plantedBy` = [A, B] |
| 17 | A plants her own seed | deny |
| 18 | tree differs from the seed (title / place / momentDay / scene / species) | deny each; `momentDay` 1 ms off allow |
| 19 | tree written without deleting the seed | deny |
| 20 | client `plantedAt`; client `agreementAt`; `plantedBy: [B, A]`; `agreementBy: [B]`; with `lookBy` | deny each |
| 21 | `tree_p2` with `slot: 'p1'`; `fromProposal` naming a missing seed | deny each |
| 22 | Our tree's first planting by B: `config` set (`startDate` = the seed's, `setBy: A`) + `tree_our` create + delete `seed_our` | allow; `config.startDate` one day off deny; without the `config` write deny; with `config` already present deny |
| **recording Our tree** | | |
| 23 | B records `tree_our` (`origin: legacy`, `agreedStartDay` = config, `recorded`, `[B]`) | allow; `agreedStartDay` 1 ms off allow |
| 24 | recording with a `place` / `plantedAt` / `preset: firstMet` / without `config` / `agreedStartDay` one day off | deny each |
| 25 | after an owner (1.2) move of `config`: A re-records `agreedStartDay` to the new value | allow; to any other value deny |
| **looks and changes** | | |
| 26 | either member changes scene/species with `prev*`, `lookBy`, server `lookAt` | allow; the same write touching `title` deny; client `lookAt` deny |
| 27 | `change_p1` by A (full content); B updates `tree_p1` to it and deletes `change_p1` | allow |
| 28 | change carried out with different content / touching `plantedAt` / a key mismatch / by A herself | deny each |
| 29 | `change_our` with a `momentDay` | deny; `change_our` with a place, carried out | allow |
| 30 | a change removing the place (proposal without `place`), carried out with the field deleted | allow |
| **start date** | | |
| 31 | `startdate` with `fromStartDay` = config (and 1 ms off) | allow; one day off deny; without `tree_our` deny |
| 32 | B agrees: `config` update (`startDate`, `updatedAt`) + `tree_our` update + delete `startdate` | allow; by A deny; `config` written with another day deny |
| 33 | owner moves `config` (1.2), then B agrees | deny (void) |
| 34 | agreement without the `config` write | deny |
| **rest** | | |
| 35 | `rest_p1` by A; B deletes `tree_p1` + `rest_p1` | allow |
| 36 | A (asker) deletes `tree_p1`; B deletes `tree_p1` without a request; `rest_our` create; deleting `tree_our` while active | deny each |
| 37 | `rest_p1` whose `key` is not the tree's | deny (at create) |
| **watering** | | |
| 38 | A waters (watering + turn) with `config` | allow |
| 39 | the watering alone; the turn alone | deny, deny |
| 40 | A again at once | deny; turn seeded at −12 h then water allow; at −11 h deny |
| 41 | B waters right after A; both in one second | allow, allow |
| 42 | no `config` | deny |
| 43 | malformed: `by: B` under A; client `wateredAt`; note of 401; extra key `together`; effect `rain cloud`; disconnected; outsider | deny each |
| 44 | update or delete a watering while active | deny |
| **purge and reads** | | |
| 45 | disconnected couple: delete `waterer_A` and `water_*` | allow |
| 46 | disconnected couple: ONE batch deleting `config`, 8 trees, 4 proposals, 20 waterings, 2 waterers | allow |
| 47 | active couple: deleting a watering, a waterer, a planted tree directly | deny each |
| 48 | members get and list `timeTreeMeta`; outsider and signed-out get/list | allow; deny |
| **seed bounds** | | |
| 49 | A creates `seed_alice_1`, `seed_alice_2`, `seed_alice_3` | allow each; then `seed_alice_4`, `seed_alice_0`, `seed_alice_x` and `seed_bob_1` (written by A, `by: A`) deny each |
| 50 | B counters `seed_alice_2` (`by: B`, `rev: 2`; the id keeps A's uid); A plants B's version (`tree_p1` + delete `seed_alice_2`) | allow, allow |
| **couple document (review SEC-1, SEC-3)** | | |
| 51 | a member disconnects, purges garden documents, then tries to set the couple active again and resume | deny the resume |
| 52 | a member adds a third uid to `userIds`; that uid proposes or answers | deny each |
| 53 | one seed planted into `p1` and `p2` (either order) in one commit; `p1` alone | deny; allow |
| 54 | the lowest free slot up to `p7` (the heaviest batch: every optional field plus the duplicate seed's delete); `p(n+1)` while `p(n)` is free; `p8` in a full garden | allow; deny; deny |
| 55 | with `p2` free (`p1` and `p3` planted): `p4`; `p2` | deny; allow |

Test 7 also covers `tree_p0`. `firestore-tests/couples.rules.test.mjs` (its own database `couples-rules`, 11 tests) covers the couples update rule for every app version: the pairing batch, the disconnect batch (and a resend), the purge, every app merge on an active and a disconnected couple, a couple without a `status` field; and denies a status set back to active, any change to `userIds`, a set without `userIds`, and outsiders.

The existing `memories` and `futureLetters` tests must stay green in the same run. Latest run: 100/100 (garden 55, couples 11, futureLetters 17, memories 17).

**Expression budget.** Firestore allows 1,000 expressions per request and 10 document accesses per operation (the emulator enforces both). The heaviest garden write, planting into `p7`, passes with about 100–120 expressions to spare; test 54 replays it, so an addition to the tree-create path that breaks the budget fails the suite.

### F4. Mutants (run from the scratchpad, never committed)

Each must fail at least one test: (1) no cooldown; (2) client `wateredAt` accepted; (3) the proposer can plant; (4) no `rev + 1`; (5) a planted tree deletable without a rest request; (6) a watering without its turn; (7) `waterer_<anyone>` writable; (8) slot pattern `tree_p[0-9]`; (9) Our tree planted without the `config` write; (10) writes allowed in a disconnected couple; (11) the purge delete denied; (12) `config` tightened with `setBy == me` (breaks 1.2 parity); (13) area precision unchecked; (14) `fromStartDay` unchecked (stale suggestions accepted); (15) place-seed creation unbounded (`isMySeedDoc` dropped from `allow create`); (16) a couple's `userIds` may change; (17) a couple set without `userIds` allowed; (18) `status` may leave `disconnected`; (19) one seed planted into any slot; (20–25) the lowest-free-slot check skips `p1` … `p6`. Latest run: 25/25 caught.

### F5. How to run

```
firebase emulators:exec --only firestore --project demo-coupley-rules "node --test firestore-tests/"
```

A `demo-` project keeps the emulator offline. **Prerequisites** (K0): a Java 21 runtime (installed user-locally with the user's approval: `export JAVA_HOME=$(/usr/libexec/java_home -v 21)`), firebase-tools (15.15.0) and Node 20+ (20.19.6). Gate for asking the user to approve `firebase deploy --only firestore:rules`: all three suites green three times in a row, every mutant caught.

---

## G. Cloud Functions (P2)

### G1. Shared helper changes in `functions/index.js`

1. `sendNotification(userId, type, title, body, data, options)` gains two options, defaults unchanged for every existing caller:
   - `quiet = false`: when true the APNs `aps` omits `sound` and `badge` and sets `"interruption-level": "passive"`; Android omits the sound.
   - `contentAvailable = false`: when true adds `"content-available": 1` to `aps` (the alert push also wakes a suspended app's `didReceiveRemoteNotification`).
2. **Emulator dry run**: when `process.env.FUNCTIONS_EMULATOR === "true"` (set by the emulator itself), right before `messaging.send` it writes `pushDryRun/{auto}` = `{userId, type, title, body, data, options: {threadId, quiet, contentAvailable}, at}` and returns `true`. Production never takes this path.
3. A comment in `buildRelationshipContext`: the garden (`timeTreeMeta`) and its places must never be read for AI context.

### G2. `functions/garden.js` (pure, no Firebase imports, unit-tested)

```js
"use strict";
const HOUR = 3600e3;
const TOGETHER_MS = 24 * HOUR;                // = GardenCadence.togetherWindow
const REST_MS = 7 * 24 * HOUR;                // = GardenCadence.rainReturnsAfter
const DAILY_CAP = 6;                          // garden pushes per recipient per UTC day
const QUIET_FROM = 22, QUIET_UNTIL = 7;       // recipient's local hours 22:00–06:59
const PUSH = { watered: "garden_watered", proposal: "garden_proposal", agreed: "garden_agreed" };

const isWaterId = (id) => /^water_[A-Za-z0-9]{20}$/.test(id);
const isProposalId = (id) => id === "seed_our" || id === "startdate" || /^seed_[A-Za-z0-9]{1,128}_[1-3]$/.test(id)
  || /^change_(our|p[1-7])$/.test(id) || /^rest_p[1-7]$/.test(id);

/** What a timeTreeMeta write means for a push, or null (config, waterers, looks,
 *  edits by the proposer, deletions, recordings are all silent). */
function classify(docId, before, after) {
  if (isWaterId(docId)) {
    if (before || !after || after.docType !== "water" || !after.by || !after.wateredAt) return null;
    return { kind: "watered", wateringId: docId, by: after.by, at: after.wateredAt, note: after.note || null };
  }
  if (isProposalId(docId)) {
    if (!after || after.docType !== "proposal" || !after.by || !after.at) return null;
    const isCounter = !!before && before.by !== after.by;
    if (before && !isCounter) return null;
    return { kind: "proposal", proposalId: docId, by: after.by, atMs: after.at.toMillis(), isCounter, proposal: after };
  }
  const tree = /^tree_(our|p[1-7])$/.exec(docId);
  if (tree) {
    if (!after || !after.agreementAt || !["plant", "change", "startDate"].includes(after.agreementKind)) return null;
    if (before && before.agreementAt && before.agreementAt.isEqual(after.agreementAt)) return null;
    const [proposerId, accepterId] = Array.isArray(after.agreementBy) ? after.agreementBy : [];
    if (!proposerId || !accepterId || proposerId === accepterId) return null;
    return { kind: "agreed", slot: tree[1], proposerId, accepterId,
             agreementAtMs: after.agreementAt.toMillis(), tree: after };
  }
  return null;
}

/** Garden pushes go only to a token device that runs a garden build, with the toggle on. */
function canReceiveGardenPush(user) {
  return !!user && typeof user.fcmToken === "string" && user.fcmToken.length > 0
    && user.gardenPushToken === user.fcmToken
    && !(user.notificationPreferences && user.notificationPreferences.garden === false);
}

/** "first" | "together" | "returned" | "plain" from server times (ms), as GardenMoment.of. */
function wateringMoment({ atMs, partnerLastBeforeMs, previousAnyMs }) {
  if (previousAnyMs == null) return "first";
  if (partnerLastBeforeMs != null && atMs - partnerLastBeforeMs <= TOGETHER_MS) return "together";
  if (atMs - previousAnyMs >= REST_MS) return "returned";
  return "plain";
}

function cleanText(s, max) {
  if (typeof s !== "string") return null;
  const t = s.replace(/[\u0000-\u001F\u007F]/g, " ").replace(/\s+/g, " ").trim();
  if (!t) return null;
  const chars = Array.from(t);                       // code points, never half an emoji
  return chars.length > max ? chars.slice(0, max - 1).join("") + "…" : t;
}
const quote = (note) => { const t = cleanText(note, 100); return t ? `“${t}”` : null; };
const titled = (title) => `“${cleanText(title, 40) || "your tree"}”`;
function apart(ms) { const h = ms / HOUR; return h < 1 ? "a few minutes" : h < 2 ? "an hour" : `${Math.floor(h)} hours`; }

/** A stored calendar day (10:00 UTC) names its UTC date; any other instant
 *  (1.1/1.2) names the day in the recipient's zone, like localDay(ofStored:). */
function isStoredDay(d) {
  return d.getUTCHours() === 10 && d.getUTCMinutes() === 0 && d.getUTCSeconds() === 0 && d.getUTCMilliseconds() === 0;
}
function dayText(date, timeZone) {
  const opts = { day: "numeric", month: "long", year: "numeric" };
  try { return date.toLocaleDateString("en-GB", { ...opts, timeZone: isStoredDay(date) ? "UTC" : (timeZone || "UTC") }); }
  catch { return date.toLocaleDateString("en-GB", { ...opts, timeZone: "UTC" }); }
}

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

/** A new proposal or a counter. `treeTitle` is the target tree's title for rest/startDate. */
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

/** An agreement, sent to the proposer. */
function agreementCopy({ name, kind, slot, title, agreedStartDay, timeZone }) {
  if (kind === "plant" && slot === "our")
    return { title: "Your tree is planted 🌳", body: `${name} said yes. It grows from ${dayText(agreedStartDay.toDate(), timeZone)}.` };
  if (kind === "plant") return { title: `${name} said yes 🌳`, body: `Your tree for ${titled(title)} is planted. Come see it grow.` };
  if (kind === "change") return { title: `${name} agreed 🌳`, body: `${titled(title)} has its new details.` };
  if (kind === "startDate")
    return { title: "Start date updated", body: `${name} agreed: your story begins on ${dayText(agreedStartDay.toDate(), timeZone)}.` };
  return null;
}

function isQuietHour(timeZone, now = new Date()) {
  try {
    const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone: timeZone || "UTC", hour: "numeric", hourCycle: "h23" }).format(now));
    return hour >= QUIET_FROM || hour < QUIET_UNTIL;
  } catch { return false; }
}
const utcDayKey = (now = new Date()) => now.toISOString().slice(0, 10).replace(/-/g, "");

module.exports = { TOGETHER_MS, REST_MS, DAILY_CAP, PUSH, classify, canReceiveGardenPush, wateringMoment,
                   cleanText, apart, isStoredDay, dayText, wateringCopy, proposalCopy, agreementCopy,
                   isQuietHour, utcDayKey };
```

### G3. Triggers and IO helpers in `functions/index.js`

```js
const garden = require("./garden");

/** True the first time `key` is seen (Firestore triggers are at-least-once). */
async function claimOnce(key) {
  try { await db.collection("gardenPushClaims").doc(key).create({ at: FieldValue.serverTimestamp() }); return true; }
  catch (e) { if (e.code === 6) return false; throw e; }          // ALREADY_EXISTS
}

/** At most DAILY_CAP garden pushes per recipient per UTC day. */
async function takeGardenSlot(userId) {
  const ref = db.collection("gardenPushDaily").doc(`${userId}_${garden.utcDayKey()}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists ? (snap.get("count") || 0) : 0;
    if (count >= garden.DAILY_CAP) return false;
    tx.set(ref, { count: count + 1, day: garden.utcDayKey(), at: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

/** The actor's partner, if the couple is active and the partner's token device can show the garden. */
async function gardenRecipient(coupleId, actorId) {
  const couple = await db.collection("couples").doc(coupleId).get();
  if (!couple.exists) return null;
  const c = couple.data() || {};
  if (c.status === "disconnected") return null;
  const ids = Array.isArray(c.userIds) ? c.userIds : [];
  if (!ids.includes(actorId)) return null;
  const to = ids.find((id) => id !== actorId);
  if (!to) return null;
  const user = await db.collection("users").doc(to).get();
  const u = user.exists ? user.data() : null;
  if (!garden.canReceiveGardenPush(u)) return null;
  return { id: to, timezone: u.timezone || null };
}

async function sendGardenPush(recipient, type, copy, data, coupleId, { contentAvailable = false } = {}) {
  if (!(await takeGardenSlot(recipient.id))) return;
  await sendNotification(recipient.id, type, copy.title, copy.body,
    { coupleId, navigateTo: "journey", ...data },
    { skipRateLimit: true, skipDuplicateCheck: true, threadId: `coupley-garden-${coupleId}`,
      quiet: garden.isQuietHour(recipient.timezone), contentAvailable });
}

exports.onTimeTreeMetaWritten = onDocumentWritten("couples/{coupleId}/timeTreeMeta/{docId}", async (event) => {
  const { coupleId, docId } = event.params;
  const before = event.data?.before?.exists ? event.data.before.data() : null;
  const after = event.data?.after?.exists ? event.data.after.data() : null;
  const ev = garden.classify(docId, before, after);
  if (!ev) return;
  if (await gardenSwitchedOff()) {          // appConfig/garden {enabled: false} (E8)
    console.log(`[Garden] switched off; ${ev.kind} in ${coupleId} not pushed`);
    return;
  }
  if (ev.kind === "watered") return handleWatering(coupleId, ev);
  if (ev.kind === "proposal") return handleProposal(coupleId, ev);
  return handleAgreement(coupleId, ev);
});

async function handleWatering(coupleId, ev) {
  if (!(await claimOnce(`w_${coupleId}_${ev.wateringId}`))) return;
  const recipient = await gardenRecipient(coupleId, ev.by);
  if (!recipient) return;
  const meta = db.collection(`couples/${coupleId}/timeTreeMeta`);
  const atMs = ev.at.toMillis();
  const [recent, previous, trees] = await Promise.all([
    meta.where("wateredAt", ">=", Timestamp.fromMillis(atMs - garden.TOGETHER_MS)).where("wateredAt", "<", ev.at).get(),
    meta.where("wateredAt", "<", ev.at).orderBy("wateredAt", "desc").limit(1).get(),
    meta.where("docType", "==", "tree").get(),
  ]);
  const partnerLast = recent.docs.filter((d) => d.get("by") === recipient.id)
    .map((d) => d.get("wateredAt").toMillis()).sort((a, b) => b - a)[0] ?? null;
  const previousAny = previous.empty ? null : previous.docs[0].get("wateredAt").toMillis();
  const moment = garden.wateringMoment({ atMs, partnerLastBeforeMs: partnerLast, previousAnyMs: previousAny });
  const copy = garden.wateringCopy({ name: await getDisplayName(ev.by), note: ev.note, moment,
    treeCount: Math.max(1, trees.size), msAfterPartner: partnerLast == null ? 0 : atMs - partnerLast });
  await sendGardenPush(recipient, garden.PUSH.watered, copy,
    { gardenFocus: "watering", wateringId: ev.wateringId, moment, wateredAtMs: String(atMs) },
    coupleId, { contentAvailable: true });
}

async function handleProposal(coupleId, ev) {
  if (!(await claimOnce(`p_${coupleId}_${ev.proposalId}_${ev.atMs}`))) return;
  const recipient = await gardenRecipient(coupleId, ev.by);
  if (!recipient) return;
  let treeTitle = null;
  const slot = ev.proposal.slot;
  if (!ev.proposal.title && slot && slot !== "new") {
    const tree = await db.doc(`couples/${coupleId}/timeTreeMeta/tree_${slot}`).get();
    treeTitle = tree.exists ? tree.get("title") : null;
  }
  const copy = garden.proposalCopy({ name: await getDisplayName(ev.by), proposal: ev.proposal,
    isCounter: ev.isCounter, treeTitle, timeZone: recipient.timezone });
  await sendGardenPush(recipient, garden.PUSH.proposal, copy,
    { gardenFocus: "proposal", proposalId: ev.proposalId, kind: ev.proposal.kind }, coupleId);
}

async function handleAgreement(coupleId, ev) {
  if (!(await claimOnce(`a_${coupleId}_${ev.slot}_${ev.agreementAtMs}`))) return;
  const recipient = await gardenRecipient(coupleId, ev.accepterId);
  if (!recipient || recipient.id !== ev.proposerId) return;
  const copy = garden.agreementCopy({ name: await getDisplayName(ev.accepterId), kind: ev.tree.agreementKind,
    slot: ev.slot, title: ev.tree.title, agreedStartDay: ev.tree.agreedStartDay, timeZone: recipient.timezone });
  if (!copy) return;
  await sendGardenPush(recipient, garden.PUSH.agreed, copy,
    { gardenFocus: "tree", treeSlot: ev.slot, kind: ev.tree.agreementKind }, coupleId);
}
```

Logging: only ids and types (`[Garden] watered c1/water_…`), never notes, titles or place fields.

### G4. Payload keys (strings, as `sendNotification` coerces)

| Key | Values |
|---|---|
| `type` | `garden_watered`, `garden_proposal`, `garden_agreed` |
| `coupleId` | the couple (the app ignores focus for another couple) |
| `navigateTo` | `journey` |
| `gardenFocus` | `watering`, `proposal`, `tree` |
| `wateringId` / `proposalId` / `treeSlot` | the object to open |
| `moment` | `first`, `together`, `returned`, `plain` (waterings) |
| `kind` | `plant`, `change`, `rest`, `startDate` |
| `wateredAtMs` | the watering's server time (re-plans reminders from a background wake) |

APNs: `thread-id` `coupley-garden-{coupleId}`; `interruption-level` `passive` without sound or badge during the recipient's quiet hours, else `active` with the default sound and badge; `content-available: 1` on waterings.

### G5. Volume, rate limits and dedupe

- Watering pushes are bounded by the rules: one watering per person per 12 h ⇒ at most 2 a day from each partner.
- Every garden push uses `skipRateLimit: true, skipDuplicateCheck: true` (a direct partner act, like chat; it must not consume or be blocked by the 2-a-day nudge budget that low-mood alerts depend on), plus the garden's own claim (exactly once) and its own cap (6 per recipient per UTC day, transaction).
- Quiet hours: 22:00–06:59 in the recipient's `users.timezone` (written by the activity heartbeat).
- No push to a legacy partner, ever (no token match). No "update Coupley" pushes.

### G6. `onCouplePurged`

```js
// When a couple document is deleted (only possible once disconnected), delete
// everything still under it: whatever an older app's purge left behind (1.1
// never purged timeTreeMeta; 1.2 purges it best-effort), garden places and
// notes included, and Future Letters bodies a 1.2 deletion orphans.
exports.onCouplePurged = onDocumentDeleted(
  { document: "couples/{coupleId}", timeoutSeconds: 540, memory: "512MiB" },
  async (event) => {
    await db.recursiveDelete(db.collection("couples").doc(event.params.coupleId));
    console.log(`[Purge] couple ${event.params.coupleId} subtree deleted`);
  });
```

Deleting `memories` documents here also fires the overhaul's `onMemoryDeleted`, which removes their photos.

### G7. `cleanupOldData`

Adds: delete `gardenPushClaims` and `gardenPushDaily` documents whose `at` is older than 7 days (paged, 300 per batch), and `pushDryRun` (exists only on the emulator). Redeployed with the garden functions.

### G8. Testing before any deploy

1. **Unit** (`functions/test/garden.test.js`, `node --test functions/test/garden.test.js`, no new dependency; Node 20+ — this Mac has 20.19.6; `engines.node: "22"` only sets the deployed runtime, and the functions emulator prints a version warning and runs on the host's Node):
   - `classify`: water create → watered; water update/delete → null; proposal create (`seed_alice_1`, `seed_our`, `startdate`, `change_p2`, `rest_p3`) → proposal; the old `seed_` + 20-character id → null; edit by the proposer → null; counter (`by` changed) → proposal with `isCounter`; proposal delete → null; tree agreement new → agreed; same `agreementAt` → null; `recorded` → null; look change → null; `config` / `waterer_x` → null.
   - `wateringMoment`: first; partner 23 h 59 min before → together; 24 h 1 min → plain; previous 7 days → returned; together beats returned; a partner watering after this one does not count.
   - copy: every branch with and without a note; a 140-character note cut to 100 with "…"; an emoji at the cut is never split; one tree vs many; control characters stripped; a 60-character title cut to 40.
   - `dayText`: `Date.UTC(2023, 2, 12, 10)` → "12 March 2023" whatever the machine's zone; a raw 1.2 instant `Date.UTC(2023, 2, 11, 18)` → "12 March 2023" in `Asia/Ho_Chi_Minh` and "11 March 2023" in `America/Los_Angeles`.
   - `isQuietHour`: 21:59 / 22:00 / 06:59 / 07:00 in `Asia/Ho_Chi_Minh` and `America/Los_Angeles` (including a DST day); an invalid zone → false.
   - `canReceiveGardenPush`: missing user; no token; token without `gardenPushToken`; mismatched tokens; matching tokens; matching with `garden: false`.
2. **Emulator end to end** (`functions/test/garden.emulator.test.mjs`, skipped unless `FIRESTORE_EMULATOR_HOST` is set; needs Java 21, K0):
   `firebase emulators:exec --only firestore,functions --project demo-coupley-rules "node --test functions/test/garden.emulator.test.mjs"` (with a dummy `OPENAI_API_KEY` in `functions/.secret.local`, git-ignored by the new `functions/.gitignore`, so the existing functions load). Seeds users (garden token / legacy token / toggle off, time zones) and a couple through the REST harness as `owner`, writes as `owner`, polls `pushDryRun` for up to 10 s. Cases: plain; with note; first; together (both orders); returned; partner legacy (no push); toggle off (no push); disconnected couple (no push); the seventh push of the day dropped; counter vs edit; agreement to the proposer only; `recorded` silent; a duplicated event (call `claimOnce` twice: true then false); quiet hour → `quiet: true`; couple deletion → `onCouplePurged` empties `timeTreeMeta`, `memories` and `futureLetters`.
3. **Deploy** (the user's explicit approval, after the rules): `firebase deploy --only functions:onTimeTreeMetaWritten,functions:onCouplePurged,functions:cleanupOldData`. The `sendNotification` change ships inside that bundle; other functions keep their deployed code until their own redeploy. Without the functions the app works fully, with no pushes and no copy promising one.

---

## H. Local reminders (P4)

**Owner**: `WidgetSyncService`, already the single owner of Journey's reminders, whose listeners live for the whole paired session. It gains one listener, `timeTreeMeta.order(by: "wateredAt", descending: true).limit(to: 3)` with metadata changes on, and plans from the newest watering **without pending writes** (my own pending watering re-plans once the server confirms it), and only once its anchor state is resolved. It queues garden work on its existing serial chain, so garden, capsule and crown work never interleave and a sign-out cancels all of it.

**The chain refactor** (the must-fix): `enqueueReminderWork` today hands its work a `TimeTreeNotificationScheduling`. It now hands a pair:

```swift
@MainActor struct JourneyReminderSchedulers {
    let journey: TimeTreeNotificationScheduling
    let garden: GardenReminderScheduling
}
private func enqueueReminderWork(_ work: @escaping (JourneyReminderSchedulers) async -> Void)
```

Existing call sites change from `{ scheduler in await scheduler.rescheduleCrowns(...) }` to `{ s in await s.journey.rescheduleCrowns(...) }`. `stopJourneyReminders()` awaits `s.journey.cancelAll()` then `s.garden.cancelAll()`.

**Scheduler**: `GardenReminderScheduler: GardenReminderScheduling` (`@MainActor final class`), two identifiers at most:

| Id | Fires | Title / body |
|---|---|---|
| `tt.garden.ready` | the first 19:00 local **at or after** `lastWateredAt + 48 h` (so between 48 and 72 h) | "The garden is ready for water 💧" / one of three lines (B8) chosen by `JourneyTreeOrnament.stableSeed(wateringId) % 3`, so both phones say the same |
| `tt.garden.rest` | the first 19:00 local at or after `lastWateredAt + 168 h` | "Your garden is resting 🌙" / "No rush. Whenever you're ready, a little water wakes it up." |

- "First 19:00 at or after T": `Calendar.current.nextDate(after: T.addingTimeInterval(-1), matching: DateComponents(hour: 19, minute: 0), matchingPolicy: .nextTime)`; scheduled with `UNCalendarNotificationTrigger(dateMatching: year/month/day/hour/minute, repeats: false)` without a time zone (floating), so DST and travel keep it at 19:00 wherever the phone is (crowns do the same). Skipped if the moment is less than 60 s away.
- `reschedule(_ plan:)`: **first the monotonic guard**: if `plan.isStale(storedLastWateringMs:)` against `lastWateringMs.{c}` (a plan that would schedule but knows an older watering than the one already planned, or none at all), it returns without touching anything. Then it does nothing but `cancelAll()` when `!plan.hasOurTree`, `plan.lastWateredAt == nil` (a never-watered garden is invited on screen, never nagged), or `!plan.isEnabled`. Otherwise it stores `lastWateringMs.{c}` = the plan's time (so the stored value only moves forward), removes both pending requests, removes **delivered** `tt.garden.*` whose `userInfo.wateringId` differs from `plan.lastWateringId` (a newer watering made them untrue; a delivered reminder for the current watering stays), then adds the ones still in the future. It checks `Task.isCancelled` before every add.
- **Why monotonic**: the push path (below) and a chain step built from an older cached snapshot can interleave, most likely in a short background wake where the server snapshot never arrives before suspension. With the guard, a step that knows only the older watering can never restore `tt.garden.ready` for it or move `lastWateringMs` backwards. `lastWateringMs` is written only from confirmed server times (a snapshot without pending writes, or a push's `wateredAtMs`) and is removed with the other garden keys when the app leaves `.ready`.
- `plan.isEnabled` = the `notificationsEnabled` mirror (default true); `reschedule` additionally no-ops (after `cancelAll()`) unless notification authorization is `.authorized` or `.provisional`.
- `userInfo`: `type` = `gardenReady` / `gardenRest`, `coupleId`, `wateringId`, `body` (for the in-app list); `threadIdentifier` `coupley-journey`; sound default. Tapping opens Journey (`.garden(.overview)`); the hero's water CTA pulses once (Reduce Motion: no pulse).
- `cancelAll()`: pending AND delivered `tt.garden.*`. Called from `stopJourneyReminders()` and from `CoupleyApp.syncNotificationBinding` when leaving `.ready`.

**Re-planning, so a reminder never fires after the partner watered**:
1. Every snapshot of WidgetSyncService's latest-watering listener (cache or server) whose newest confirmed watering changed queues `reschedule` with a revision counter (a newer one supersedes); the monotonic guard drops anything older than what is already planned.
2. Foreground: WidgetSyncService observes `UIApplication.didBecomeActiveNotification` and re-queues.
3. Background wake: the watering push carries `content-available: 1`, `coupleId`, `wateringId` and `wateredAtMs`. `AppDelegate.application(_:didReceiveRemoteNotification:)` (already present, `nonisolated`) extracts those Sendable strings and awaits `GardenReminderScheduler.replanFromPush(coupleId:wateredAtMs:wateringId:)` (`@MainActor static`), which proceeds only if `coupleId == UserDefaults[activeCoupleId]` (written by WidgetSyncService on bind, removed on unbind) and the mirror is on. When WidgetSyncService is bound to that couple (same process), it enqueues the plan on the service's serial chain (`WidgetSyncService.shared.queueGardenReplan(fromPushWateredAtMs:wateringId:)`); otherwise it calls the scheduler directly. The plan is `{lastWateredAt: wateredAtMs, lastWateringId, hasOurTree: true (a watering requires the start date), isEnabled: mirror}`; the monotonic guard makes either path and any interleaving safe. Best effort: iOS may not wake a force-quit app; the next launch corrects everything.
4. The Garden toggle: `NotificationViewModel` writes the mirror on load/save and calls `WidgetSyncService.shared.gardenRemindersPreferenceChanged()`.
5. The anchor listener (start date appears or disappears) re-queues too.

**The 64-request budget** (iOS keeps the 64 soonest pending requests per app):

| Owner | Prefix | At most |
|---|---|---|
| FutureLetterNotificationScheduler | `fl.ready.` | 8 |
| TimeTreeNotificationScheduler, capsules | `tt.capsule.` | 20 |
| TimeTreeNotificationScheduler, crowns | `tt.crown.` | 3 |
| **GardenReminderScheduler** | **`tt.garden.`** | **2** |
| Together | `tg.*` | about one per active challenge plus milestones |
| Micro actions, legacy anniversaries | own | a few |

Journey, letters and the garden use at most 33. Both garden requests always fire within 8 days, so they are among the soonest and the last iOS would drop.

---

## I. Client architecture

### I1. New files (Xcode folders are file-system synchronized; each compiles on creation)

| Path | Package | Responsibility |
|---|---|---|
| `Coupley/Features/Garden/Models/GardenContract.swift` | P0 (lead) | the shared contract (`contract.swift`) |
| `Coupley/Features/Garden/Models/GardenCopy.swift` | P3 | every status line, CTA title, request/notice/journal/home string (pure, `nonisolated`, uses the contract) |
| `Coupley/Features/Garden/Services/GardenService.swift` | P3 | `FirestoreGardenService: GardenServicing`: listeners, the watering batch, confirmed writes, the transaction wrapper |
| `Coupley/Features/Garden/Services/GardenTransactions.swift` | P3 | `nonisolated enum GardenTransactions`: the pure bodies T1–T13 (snapshot dictionaries in, writes out) |
| `Coupley/Features/Garden/Services/GardenCodec.swift` | P3 | dictionary encoders/decoders for every document, raw-copy helpers, defensive decoding (I7) |
| `Coupley/Features/Garden/Services/GardenConnectivity.swift` | P3 | `NWPathMonitor` wrapper: `GardenConnectivityMonitoring` |
| `Coupley/Features/Garden/Services/InMemoryGardenService.swift` | P3 | `#if DEBUG` `GardenServicing` with scripted partner actions and a clock offset (lab, DEBUG-only previews) |
| `Coupley/Features/Garden/ViewModels/GardenViewModel.swift` | P3 | state, lifecycle, actions (I3) |
| `Coupley/Features/Garden/ViewModels/GardenViewModel+Models.swift` | P3 | derived `hero`, `requests`, `homeLine`, `journal`, notices, ceremony and replay detection |
| `Coupley/Features/Garden/Services/GardenReminderScheduler.swift` | P4 | H |
| `Coupley/Core/FirebaseEmulatorSwitch.swift` | P4 | the whole file inside `#if DEBUG`: the `-useFirestoreEmulator` launch argument (K0) |
| `Coupley/Features/Garden/Views/Scenes/GardenSceneKit.swift` | P5 | shared primitives, sky pass helpers, season particles, palette helpers |
| `Coupley/Features/Garden/Views/Scenes/GardenBackdropCache.swift` | P5 | `GardenBackdropCache.shared: GardenBackdropProviding` |
| `Coupley/Features/Garden/Views/Scenes/GardenSceneRegistry.swift` | P5 | `extension GardenSceneID { nonisolated var painter: any GardenScenePainting }` |
| `Coupley/Features/Garden/Views/Scenes/MeadowScene.swift`, `SeasideScene.swift`, `CityLightsScene.swift`, `MountainLakeScene.swift` | P5 | four painters |
| `Coupley/Features/Garden/Views/Scenes/LanternTownScene.swift`, `RiceTerracesScene.swift`, `CampusScene.swift`, `HomePorchScene.swift` | P6 | four painters |
| `Coupley/Features/TimeTree/Views/TreeCanvasSpecies.swift` | P7 | species canopies (C5) |
| `Coupley/Features/TimeTree/Views/TreeCanvasVitality.swift` | P7 | lushness, soil bed, dew, revival, the note tag; droop, fallen leaves and dry soil kept for `GardenTreeLook.withersWhenThirsty` (C6) |
| `Coupley/Features/Garden/Views/Effects/WateringEffectPainter.swift` | P8 | `nonisolated enum WateringEffectPainter: WateringEffectDrawing`: dispatch, analytic particle math, the golden first drop |
| `Coupley/Features/Garden/Views/Effects/WateringEffects+Pour.swift` | P8 | `can`, `together` |
| `Coupley/Features/Garden/Views/Effects/WateringEffects+Sky.swift` | P8 | `rainCloud`, `morningDew`, `moonlitDrizzle`, `rainReturns` |
| `Coupley/Features/Garden/Views/Effects/GardenOverlays.swift` | P8 | resting cans, the 24 h rainbow, after-glow, page-dot ripple shape, the Reduce Motion drop |
| `Coupley/Features/Garden/Views/Effects/PlantingCeremonyOverlay.swift` | P8 | C8 |
| `Coupley/Features/Garden/Services/GardenHaptics.swift` | P8 | one `CHHapticEngine` with drizzle, rain, dew ticks, heartbeat; `UIImpactFeedbackGenerator` fallback; silent when system haptics are off |
| `Coupley/Features/Garden/Services/GardenPlaceSearch.swift` | P9 | completer, resolve, reverse geocode, `MKPointOfInterestCategory → GardenPOIGroup`, recent picks |
| `Coupley/Features/Garden/Services/GardenMapSnapshotter.swift` | P9 | `GardenMapSnapshotter.shared: GardenMapSnapshotting` |
| `Coupley/Features/Garden/Views/Places/GardenPlacePicker.swift` | P9 | D1 |
| `Coupley/Features/Garden/Views/Places/GardenMapView.swift` | P9 | D5 places map |
| `Coupley/Features/Garden/Views/Places/GardenSnapshotImage.swift` | P9 | a snapshot view with attribution and the swatch fallback |
| `Coupley/Features/Garden/Views/Sheets/GardenPlantSheet.swift` | P9 | `GardenPlantSheet` (sheet) + `GardenPlantForm` (pushable content), B5.1 |
| `Coupley/Features/Garden/Views/Sheets/GardenSeedSheet.swift` | P9 | B5.2 (+ `HoldToPlantButton`, `SeedPacketView`) |
| `Coupley/Features/Garden/Views/Sheets/TreePostcardView.swift` | P9 | B5.4 (+ the look picker) |
| `Coupley/Features/Garden/Views/Hero/GardenHero.swift` | P10 | B3 (pager, chips, dots, caption, CTA row, empty/unavailable states) |
| `Coupley/Features/Garden/Views/Hero/GardenScenePage.swift` | P10 | C2 layer stack, the page clock, `GardenMotionGate`, parallax |
| `Coupley/Features/Garden/Views/Hero/GardenRequestsSection.swift` | P10 | B4 cards and quiet zone |
| `Coupley/Features/Garden/Views/Sheets/GardenSheet.swift` | P10 | B5.5 shelf, waiting, places, watering |
| `Coupley/Features/Garden/Views/Sheets/GardenJournalView.swift` | P10 | the journal (pushed) |
| `Coupley/Features/Garden/Views/Sheets/WaterNoteSheet.swift` | P10 | B5.6 |
| `Coupley/Features/Garden/Views/GardenHomeRow.swift` | P10 | B7 |
| `Coupley/Features/Garden/Views/Debug/GardenLabView.swift` | P10 | `#if DEBUG` lab (K6), with the Reminders and Backdrop viewers |
| `firestore-tests/garden.rules.test.mjs` | P1 | F3 |
| `functions/garden.js`, `functions/test/garden.test.js`, `functions/test/garden.emulator.test.mjs`, `functions/.gitignore` | P2 | G |

### I2. Changed files

| File | Package | Change |
|---|---|---|
| `firestore.rules` | P1 | F1 (replace the `timeTreeMeta` block, add `appConfig`, header comments) |
| `functions/index.js` | P2 | G1, G3, G6, G7 |
| `Coupley/Features/Widget/Services/WidgetSyncService.swift` | P4 | H: latest-watering listener (newest confirmed of 3), `JourneyReminderSchedulers` chain refactor, `queueGardenReminders`, `queueGardenReplan(fromPushWateredAtMs:wateringId:)`, foreground observer, `activeCoupleId` on bind/unbind, `gardenRemindersPreferenceChanged()`, garden cancel in `stopJourneyReminders` |
| `Coupley/CoupleyApp.swift` | P4 | DEBUG: `FirebaseEmulatorSwitch` in place of `FirebaseApp.configure()` when `-useFirestoreEmulator` is passed (K0); AppDelegate silent-push re-plan; `syncNotificationBinding` leaving `.ready`: `await GardenReminderScheduler().cancelAll()`, `GardenViewModel.purgeLocalCaches()`, `GardenBackdropCache.shared.removeAll()`, `GardenMapSnapshotter.shared.purge()` |
| `Coupley/Features/SmartNudge/Services/NotificationService.swift` | P4 | `saveFCMToken` adds `gardenPushToken: token` in the same merge (when `GardenFeature.isEnabled`); `clearFCMToken` deletes it too |
| `Coupley/Features/SmartNudge/ViewModels/NotificationViewModel.swift` | P4 | `handleNudgeTap`: garden types (`GardenNotification.allTypes`) → `journeyFocus = .garden(.overview)`; `handleTappedNudge`: a garden focus whose payload `coupleId` differs from the session's becomes `.garden(.overview)`; mirror `preferences.garden` to `GardenDefaultsKey.notificationsEnabled` on load and save and call `WidgetSyncService.shared.gardenRemindersPreferenceChanged()` |
| `Coupley/Features/SmartNudge/Models/NudgeModels.swift` | P4 | `NotificationPreferences.garden: Bool = true`, read with `?? true`, written in `firestorePrefsDict` |
| `Coupley/Features/SmartNudge/Views/NotificationSettingsView.swift` | P4 | the **Garden** toggle row (`leaf.fill`, green) |
| `Coupley/Features/PartnerConnection/Services/ConnectionService.swift` | P4 | `"timeTreeMeta"` moves out of the best-effort `try?` list into a required `try await deleteCollection(...)` (after Future Letters, before the simple list), with a comment: "Holds the garden's places and notes. Keep it flat: a flat purge cannot see subcollections." |
| `Coupley/Features/Settings/Views/FAQView.swift`, `index.html`, `Coupley/PrivacyInfo.xcprivacy` | P4 | D6 exact text |
| `Coupley/Features/TimeTree/Views/RelationshipTreeCanvas.swift` | P7 | I5 API, species dispatch, vitality, external clock, sky-aware palette, anchors, note tag; private layout/painter types become `internal` (still file-group private by convention) so the two new P7 files can extend them |
| `Coupley/Features/TimeTree/Views/AnchorSetupSheet.swift` | P9 | a `Mode` (`.directSave` today / `.suggest(...)`), B5.7 |
| `Coupley/Features/TimeTree/Views/MilestonePickerSheet.swift` | P9 | `onPlantTree: (() -> Void)? = nil` first row (B6) |
| `Coupley/Features/TimeTree/Views/JourneyTreeGuideSheet.swift` | P9 | the Watering and Your places sections (B6); `growsFromPlanting: Bool = false` for a place tree's guide (B3 row 1, B6) |
| `Coupley/Features/TimeTree/Views/TimeTreeView.swift` | P10 | I5 |
| `Coupley/Features/TimeTree/Views/TimeTreeHeader.swift` | P10 | `showsHero: Bool = true`; `false` renders only the countdown block |
| `Coupley/Features/TimeTree/Models/JourneyLetter.swift` | P10 | `JourneyFocus.garden(GardenFocus)`; `init?(notificationUserInfo:)` returns `.garden(GardenFocus(...))` for garden types before its own switch |
| `Coupley/ContentView.swift` | P10 | owns `@StateObject gardenViewModel`; lifecycle; passes it to Journey and the Home line to the dashboard |
| `Coupley/Features/CoupleSync/Views/CoupleDashboardView.swift` | P10 | `gardenLine: GardenHomeLine? = nil`, `onOpenGarden: ((GardenFocus) -> Void)? = nil`; `GardenHomeRow` in the ambient zone |
| `Coupley/Core/DesignSystem.swift` | P10 | `TierContainer` and `BrandCard` gain `insetsContent: Bool = true` (C1) |
| `Coupley/Features/Settings/Views/DebugMenuView.swift` | P10 | a `#if DEBUG` link to `GardenLabView`; a Status row "Firebase: emulator (127.0.0.1)" while `FirebaseEmulatorSwitch.isActive` |

Unchanged: `Coupley-Info.plist` (no location keys; `remote-notification` background mode already present), entitlements, `firestore.indexes.json`, `firebase.json`, `TimeTreeViewModel.swift` (its `setAnchor` stays for the direct-save path), `TimeTreeAnchorService.swift`, `AccountDeletionService.swift` (its `deleteSharedData` call now purges the garden as a required step), `firestore-tests/emulator.mjs`.

### I3. `GardenViewModel` (P3)

Owned by `ContentView` as a `@StateObject` (like `FutureLetterViewModel`, because Home's row and push routing need it too), handed to `TimeTreeView` as `@ObservedObject`. Lifecycle like the letters: built with ContentView's session, `rebind(session:)` on a couple change, `start()` on appear and foreground (idempotent), `stop()`. `isAvailable` is false unpaired and on `UserSession.demo` (`session.coupleId != UserSession.demo.coupleId`).

```swift
@MainActor
final class GardenViewModel: ObservableObject {
    init(session: UserSession,
         service: GardenServicing? = nil,                       // FirestoreGardenService()
         connectivity: GardenConnectivityMonitoring? = nil,     // GardenConnectivity()
         chat: CoupleChatServicing? = nil)                      // FirestoreCoupleChatService()

    // Lifecycle (ContentView / Journey)
    var isAvailable: Bool { get }
    func rebind(session: UserSession)
    func start()                     // probe, listeners, capability write, record Our tree, clock
    func stop()
    func refreshClock()              // foreground, significantTimeChange
    func resumeTicking()             // the hero appeared: minute tick for the sky
    func pauseTicking()
    static func purgeLocalCaches()   // every coupley.garden.* key except GardenDefaultsKey.keptOnPurge

    // State
    @Published private(set) var availability: GardenAvailability
    @Published private(set) var anchor: GardenAnchorState
    @Published private(set) var docs: GardenDocsSnapshot
    @Published private(set) var waterings: GardenWateringsSnapshot
    @Published private(set) var partner: GardenPartnerInfo
    @Published private(set) var selectedSlot: GardenSlot
    @Published private(set) var playback: GardenEffectPlayback?     // what the selected page plays now
    @Published private(set) var ceremony: GardenCeremony?
    @Published private(set) var notices: [GardenNotice]
    @Published private(set) var errorMessage: String?
    @Published private(set) var busyProposalId: String?
    @Published private(set) var isWatering: Bool
    @Published private(set) var afterWateringLine: String?         // the 4-second line (B3 row 3)
    @Published private(set) var now: Date

    // Derived (pure, from the state above + GardenCopy)
    var hero: GardenHeroModel { get }
    var requests: [GardenRequestModel] { get }       // for me and mine, ordered (B4)
    var homeLine: GardenHomeLine? { get }
    var primaryAction: GardenPrimaryAction { get }
    var treeCount: Int { get }
    var canPlantMore: Bool { get }
    var partnerName: String { get }
    func tree(_ slot: GardenSlot) -> GardenTree?
    func proposal(id: String) -> GardenProposal?
    func journalEntries() -> [GardenJournalEntry]                 // the live last 60
    func loadJournalPage(before: Date?) async -> [GardenJournalEntry]
    func draft(for mode: GardenDraft.Mode) -> GardenDraft         // prefilled (preset title, suggested look, memory day)

    // Actions (each ends with errorMessage set on failure; consent actions return success)
    func select(_ slot: GardenSlot)
    func water(note: String?)                                     // starts the effect at once, then writes
    func propose(_ draft: GardenDraft) async -> Bool              // routes by draft.mode
    func takeBack(_ proposalId: String) async -> Bool
    func letGo(_ proposalId: String) async -> Bool                // also "Keep it" for change/startDate/rest
    func plant(_ proposalId: String, seen: GardenProposalVersion, alsoDelete: String?) async -> Bool
    func agree(_ proposalId: String, seen: GardenProposalVersion) async -> Bool  // change, startDate, rest
    func requestRest(_ slot: GardenSlot, note: String?) async -> Bool
    func suggestStartDate(day: Date, note: String?) async -> Bool
    func changeLook(_ slot: GardenSlot, to look: GardenLook) async
    func undoLook(_ slot: GardenSlot) async
    func snooze(_ proposalId: String)
    func perform(_ notice: GardenNotice) async                    // "OK" records, "Change it back", "Water again"
    func dismiss(_ notice: GardenNotice)
    func dismissError()
    func reveal(_ focus: GardenFocus)                             // select the page, queue the replay
    func markWateringSeen()
    func acknowledgeCeremony()
    func tellPartnerToUpdate() async -> Bool                      // sends the chat line after the user's Send
}
```

Behaviours that matter:
- **`start()`**: probe (`GardenProbeResult`, answers kept per backend, real backend only: enabled ⇒ store `rulesVerified.<backend>` and clear `remoteDisabled.<backend>`; rulesMissing ⇒ `.unavailable(.rulesMissing)`; offline ⇒ `remoteDisabled` ? stay `.disabledRemotely` : `rulesVerified` ? continue : `.unavailable(.neverOnline)`; disabledRemotely ⇒ store `remoteDisabled.<backend>`, stop, cancel the garden reminders; a launch with `remoteDisabled` set starts at `.disabledRemotely` while the probe runs); attach the four listeners; `announceCapability` once per launch, **only after the probe returned enabled** (a garden build against rules that are not deployed announces nothing); when the anchor exists, `tree_our` is missing and the device is online ⇒ `recordOurTree` (a transaction that does nothing if it exists); delete void proposals it sees (`seed_our` with a start date; `startdate` whose `fromStartDay` ≠ config ±1 s), the proposer's client first.
- **Listener failures**: `.unavailable(.listenerFailed)`; retry on foreground and after 3, 6 and 9 s (the letters' pattern). Never merged into Journey's own listener error.
- **Garden-level vs per-tree** (A6): `hero.status`, `hero.waterAction`, `waterTitle`, `primaryAction`, `homeLine` and the VoiceOver water value are derived from `GardenWaterState.garden(lastWateredAt: L, now:)` and the timeline only; `selectedSlot` is not an input to any of them. Each `GardenPageModel.visual` is `GardenTreeVisual.forTree(lastWateredAt: L, plantedAt: tree.plantedAt, now:)`.
- **Versions** (D5): request cards and sheets read `proposal.version` (nil while it has pending writes, which disables their actions) and pass it as `seen`; the service's transaction compares it (I4).
- **Optimistic watering**: `water(note:)` cleans the note (`GardenLimits.wateringNote`), takes `newWateringId`, derives the moment from the snapshot, chooses and stores the effect, sets `playback` (start = now), then commits the batch. The listener's pending write shows the watering at once (estimated time); after 3 s still pending the status says "Watering… it reaches Sam when you're back online". A rejection within 2.5 s removes nothing (the SDK rolls the local write back) and sets the error; a queued watering refused later disappears from the snapshot and raises the `wateringRefused` notice.
- **Replay**: when the newest watering is the partner's, confirmed, not `seenWatering`, and the hero is visible ⇒ `playback` = its stored effect with `isReplay: true` (skipped under Reduce Motion); `markWateringSeen()` stores the id.
- **Ceremony**: the planter sets `ceremony` after the plant transaction succeeds; the proposer gets it when a tree whose `plantedBy[0] == me` and `plantedAt` within 7 days appears and `ceremonySeen` is unset; a timed-out plant that commits later is caught the same way.
- **Set aside**: a seed key in `myOpenSeeds` that disappears from a **server** snapshot with no tree carrying it ⇒ the `seedSetAside` notice.
- **Legacy start-date change**: `config.startDate` not within 1 s of `tree_our.agreedStartDay` ⇒ the `startDateChangedElsewhere` notice; **OK** runs `recordStartDate`.
- **Clock**: `now` moves on a one-shot timer aimed at the next boundary (48/72/168 h, cooldown end, together window end, dew/wet end, 24 h overlays), on the minute tick while the hero is visible, on foreground and on snapshots. State boundaries use `Date() + serverOffset` (from this device's acknowledged waterings, clamped ±10 min); displayed times are always server timestamps.
- **Cache**: `cache.{c}` holds trees and the last 10 waterings without notes for an offline first paint; written on server snapshots only.
- **Copy**: every string comes from `GardenCopy` (P3), `GardenError.message` or the contract's localized properties; views never build garden copy themselves. `GardenCopy` uses `String(localized:comment:)` for every sentence (formats with placeholders, never concatenated fragments) and shows titles through `displayTitle` (M0).
- **Set aside and snooze with reused ids**: `myOpenSeeds` maps seed key → {id, title, preset, setAside}, and a seed counts as set aside only when its key disappears; snoozes are keyed by the seed's key.

### I4. `FirestoreGardenService` (P3): writes and transactions

**The watering batch** (works offline, ≤ 2.5 s):
```swift
let batch = db.batch()
var water: [String: Any] = [GardenField.docType: "water", GardenField.by: me,
                            GardenField.wateredAt: FieldValue.serverTimestamp(),
                            GardenField.effect: effect.rawValue]
if let note { water[GardenField.note] = note }
batch.setData(water, forDocument: meta.document(wateringId))
batch.setData([GardenField.docType: "waterer",
               GardenField.lastWateredAt: FieldValue.serverTimestamp(),
               GardenField.lastWateringId: wateringId],
              forDocument: meta.document(GardenDocID.waterer(uid: me)))
try await batch.commitConfirmed()
```

**Other confirmed writes**: `changeLook` (`updateDataConfirmed`: `scene`, `species`, `prevScene`, `prevSpecies`, `lookBy`, `lookAt` = server, `updatedAt` = server; queued offline is fine, the rules accept it whenever it lands); `announceCapability` (`setDataConfirmed(["capabilities": ["garden": 1]], merge: true)` on `users/{me}`).

**The transaction wrapper** (every consent action):
1. If `connectivity.isOnline == false` ⇒ throw `.offline` at once (the SDK would otherwise retry for many seconds).
2. Run `db.runTransaction` with a body that only calls a `nonisolated static` function in `GardenTransactions` (snapshots and Sendable values in, writes out); nothing main-actor-isolated runs on Firestore's queue.
3. Race it against `GardenCadence.transactionTimeout` (10 s); on timeout throw `.timedOut` (the UI never shows success; the listener reveals the truth; a ceremony can still play from the listener).
4. Map errors: thrown `GardenError` (carried through `errorPointer` as an NSError in a `GardenError` domain) ⇒ itself; `permissionDenied` ⇒ `.denied`; `unavailable`/`deadlineExceeded` ⇒ `.offline`; `aborted`/`failedPrecondition` ⇒ `.changed`; else `.other`.

**Raw copies**: every carried-out write builds the tree (and `config`) from the proposal's **raw snapshot dictionary** read inside the transaction (`Timestamp`s and the `place` map copied as values, never decoded to `Date`/`Double` and re-encoded), so the rules' equality checks hold; the rules add ±1 s anyway.

**Version check (ABA)**: T3, T6, T7 and T10–T12 compute `GardenProposalVersion(rev, GardenProposalVersion.millis(seconds: at.seconds, nanoseconds: at.nanoseconds))` from the raw snapshot they read and compare it with the `seen` version the user was shown; any difference → `.changed`. The codec computes the shown version from the same raw `Timestamp` the same way, so the two integers are equal exactly when it is the same version. A proposal taken back and re-sent under the same fixed id restarts at `rev 1` but has a new `at`, so it fails the check instead of being carried out unseen. (`seed_our` also gets a new `key` UUID on re-creation; the `at` check covers every kind uniformly.)

| # | Transaction | Reads | Checks (→ error) | Writes |
|---|---|---|---|---|
| T0 | `proposePlaceSeed` | `seed_<me>_1`, `_2`, `_3`, `config` | no `config` → `.invalid`; all three exist → `.tooManySeeds` | create the first free `seed_<me>_n` (`rev 1`, a new UUID `key`, `by: me`, `at: server`, the draft's content with `storedTitle`) |
| T1 | `proposeOurTree` | `seed_our`, `config` | `seed_our` by partner → `.partnerProposedFirst`; by me → run T3 instead; `config` exists → `.startDateSetElsewhere` | create `seed_our` (`rev 1`, `startDay` = `storedMoment(draft.startDay)`) |
| T2 | `proposeStartDate` | `startdate`, `config`, `tree_our` | partner's exists → `.partnerProposedFirst`; mine → edit; no `config` or `tree_our` → `.invalid` | create `startdate` with `fromStartDay` = raw `config.startDate` |
| T3 | `editProposal` (edit or counter) | the proposal | missing → `.gone`; version ≠ `seen` → `.changed`; edit mode and `by != me` → `.notYours` | the full proposal, `by: me`, `at: server`, `rev + 1`, same kind/slot/key |
| T4 | `takeBack` | the proposal, then trees | missing and a tree carries its key → `.alreadyPlanted`; missing → `.gone`; `by != me` → `.notYours` | delete |
| T5 | `letGo` / keep | the proposal | missing → `.gone` | delete |
| T6 | `plant` (`seed_our`) | `seed_our`, `config`, `tree_our` | missing → `.gone`/`.alreadyPlanted`; `by == me` → `.invalid`; version ≠ `seen` → `.changed`; `config` exists → `.startDateSetElsewhere` | `config` set (raw `startDay`, `setBy` = proposer, `setByName` if known, `setAt`/`updatedAt` server); create `tree_our` (raw content, `origin together`, `plantedAt`/`agreementAt` server, `plantedBy`/`agreementBy` [proposer, me], `agreedStartDay` raw, `fromProposal`); delete `seed_our` |
| T7 | `plant` (place seed) | the seed, `tree_p1…p7`, optional `alsoDelete` | as T6; no free slot → `.full` | create `tree_pN` (first free); delete the seed; delete `alsoDelete` (my duplicate) only if it is still mine (`by == me`), else leave it |
| T8 | `proposeChange` | `change_<slot>`, `tree_<slot>` | partner's exists → `.partnerProposedFirst`; mine → edit; tree missing → `.gone` | create `change_<slot>` with the full content and the tree's key |
| T9 | `proposeRest` | `rest_<slot>`, `tree_<slot>` | as T8 | create `rest_<slot>` |
| T10 | `agree` (change) | `change_<slot>`, `tree_<slot>` | missing → `.gone`; `by == me` → `.invalid`; version ≠ `seen` or key mismatch → `.changed` | update the tree's identity + look from the raw proposal (`FieldValue.delete()` for an absent `place`/`momentDay`), agreement fields, `fromProposal`, `updatedAt`; delete the proposal |
| T11 | `agree` (startDate) | `startdate`, `config`, `tree_our` | `by == me` → `.invalid`; version ≠ `seen` → `.changed`; `config.startDate` not within 1 s of `fromStartDay` → `.startDateChanged` | `config` `updateData([startDate: raw startDay, updatedAt: server])`; `tree_our` update (`agreedStartDay` raw, agreement fields, `fromProposal`); delete `startdate` |
| T12 | `agree` (rest) | `rest_<slot>`, `tree_<slot>` | `by == me` → `.invalid`; version ≠ `seen` or key mismatch → `.changed` | delete the tree; delete the request |
| T13 | `recordOurTree` / `recordStartDate` | `tree_our`, `config` | nothing to do when already as it is | create `tree_our` (`origin legacy`, Meadow/oak, title "Our tree", `agreedStartDay` raw `config.startDate`, `recorded`, `[me]`) / update `agreedStartDay` + agreement fields; delete a void `startdate` in the same transaction |

`deleteVoidProposal` is a plain `deleteConfirmed` (any member may delete a proposal).

### I5. Integration points

**`RelationshipTreeCanvas` (P7) — new API, existing call sites unchanged**
```swift
init(stage: TreeGrowthStage, season: TreeSeason, daysTogether: Int, memoryCount: Int, crownActive: Bool,
     ornaments: [JourneyTreeOrnament] = [], onSelectOrnament: ((String) -> Void)? = nil,
     style: TreeCanvasStyle = .hero, vitality: TreeVitality = .healthy, clock: TreeCanvasClock = .own,
     noteTag: TreeNoteTag? = nil, onSelectNoteTag: (() -> Void)? = nil)
static func blossomCapacity(at stage: TreeGrowthStage) -> Int            // unchanged
static func anchors(in size: CGSize, stage: TreeGrowthStage,
                    species: GardenSpecies = .oak) -> TreeCanvasAnchors  // from TreeCanvasLayout
```
- `clock: .external(time:pose:)`: no `TimelineView`, no own pause logic; the canvas draws one frame for the given time and pose. `.own` keeps today's behaviour exactly.
- `style.backdrop` replaces the colour-scheme lookup in `TreeCanvasPalette` (`.automatic` = today).
- `style.topologySeed` (nil = days together) seeds leaves, blossoms and fruit.
- Ornament and note-tag tap targets come from the same (drooped) layout as the drawing; the note tag sits on the lowest right limb at 72% of its length (on a seed or sprout it rests on the ground right of the trunk), 36×36 pt target.

**`TimeTreeView` (P10)**
- New init parameters: `isLettersSheetPresented: Bool = false` (ContentView passes `lettersViewModel.route != nil`), `garden: GardenViewModel`, `onOpenChat: @escaping () -> Void = {}`. It passes `GardenHero(isCovered:)` = `isJourneySheetPresented || isLettersSheetPresented || viewModel.pendingCrownCelebration != nil || garden.ceremony != nil` (the motion gate's `journeySheetPresented`; review RND-2): nothing presented over Journey fires `onDisappear`.
- Garden mode = `GardenFeature.isEnabled && garden.availability != .disabledRemotely`: content becomes `GardenHero` → `GardenRequestsSection` → `TimeTreeHeader(showsHero: false)` → letters → timeline; otherwise exactly today's layout.
- One `@State gardenSheet: GardenSheetRoute?` (`.plant(GardenDraft.Mode)`, `.seed(id)`, `.postcard(GardenSlot)`, `.garden`, `.waterNote`) presented with `.sheet(item:)`; included in `isJourneySheetPresented`, `closeJourneySheets` and (plant, water note) `isEditingSomething`. `showAnchorSheet` now opens `AnchorSetupSheet` in `.suggest` mode in garden mode.
- `PlantingCeremonyOverlay` in the ZStack at zIndex 901, shown only while no crown overlay is up.
- `handleFocus(.garden(let f))`: waits until `garden.availability != .loading` (or an error), respects `isEditingSomething` like capsules, closes Journey sheets, then `garden.reveal(f)`; `.proposal(id)` then opens the seed sheet after 450 ms (the capsule pattern).
- Masthead: the tally includes trees; the + is filled when `garden.primaryAction.isMastheadPlusFilled` (garden mode) or `viewModel.anchor != nil` (legacy); label "Add a memory, a letter or a tree" when a tree can be planted. The picker gets `onPlantTree` when `garden.canPlantMore`.
- The hero calls `garden.resumeTicking()`/`pauseTicking()` from one "on screen" check (`heroVisible && tabShown && !isCovered && scenePhase == .active`), re-evaluated on appear, disappear, scroll visibility, `isCovered` and scene-phase changes, so a partner's replay and a due ceremony are held, never used up unseen, under a sheet or in the background (review CONF-3).

**`ContentView` (P10)**: `@StateObject private var gardenViewModel = GardenViewModel(session:)` (built in `init` like the letters); `onAppear` → `rebind(session: live)` + `start()`; foreground → `start()`; `significantTimeChange` → `refreshClock()`; `coupleId` change → `rebind`. Passes `garden:` and `onOpenChat: { selectedTab = .chat }` to `TimeTreeView`; passes `gardenLine: gardenViewModel.homeLine` and `onOpenGarden: { focus in journeyFocus = .garden(focus); selectedTab = .anniversary }` to `CoupleDashboardView`.

**`WidgetSyncService`, `CoupleyApp`, `NotificationService`, `NotificationViewModel`, `ConnectionService` (P4)**: as I2 and H.

### I6. Concurrency and zero warnings

- Contract value types, the scene painters (P5/P6) and the effect painter (P8) are `nonisolated` (checked: the contract typechecks with warnings as errors under the project's flags, including off-main use). They never call members of `TreeGrowthStage` or `TreeSeason`: both enums are main-actor isolated in the project (no `nonisolated`), the garden does not change them, and a nonisolated access is a warning, which the zero-warnings policy forbids (verified with the scratchpad typecheck against the repo's real `TreeGrowthStage.swift`). They use the contract's `GardenSceneSeason` and the anchors handed to them instead.
- **The tree painter stays main-actor isolated**, exactly like today's `TreeCanvasPainter`, which already runs inside `Canvas(rendersAsynchronously: true)` and builds clean: P7's `TreeCanvasSpecies`, `TreeCanvasVitality` and every helper that reads stage or season members are not marked `nonisolated` (verified: such a painter reading `canopyColors`/`canopyFullness` typechecks with zero warnings). P8's ceremony time-lapse draws through `RelationshipTreeCanvas`, a main-actor view, so it needs nothing more.
- `FirestoreGardenService` is `@MainActor`; transaction bodies are `nonisolated static` functions in `GardenTransactions` capturing only Sendable values (strings, ints, `DocumentReference`s).
- `GardenPlaceSearch`: `@MainActor` class with an isolated `MKLocalSearchCompleterDelegate` conformance.
- `AppDelegate.didReceiveRemoteNotification` stays `nonisolated`, extracts Sendable strings, then awaits the `@MainActor` re-plan.
- MemberImportVisibility: explicit `import MapKit`, `import CoreLocation`, `import CoreHaptics`, `import Network`, `import FirebaseFirestore`, `import UserNotifications` wherever their members are used.
- iOS 26-only MapKit APIs behind `#available(iOS 26, *)`; deprecated-in-26 APIs do not warn at 18.6.
- Builds clean in Debug and Release with zero warnings (the project's policy).

### I7. Defensive decoding (P3, `GardenCodec`)

- Skip any document whose required fields are missing or mistyped; unknown tokens decode to fallbacks (scene → Meadow, species → oak, preset → custom, effect → can).
- Never show a tree as planted unless (`origin == together` and `plantedBy` has two different couple members) or (`origin == legacy` and the slot is `our` and a start date exists). Anything else is ignored (it can only come from a hand-made write).
- Ignore a watering whose `by` is not a couple member; ignore proposals whose `by` is not a member.
- `tree_our` without a start date (only possible through a hand-made write) is ignored; the no-start-date hero shows.

---

## J. Edge cases

### J1. Races

| Race | What happens |
|---|---|
| Both partners water at the same moment | Two batches, two turn documents: both land. By server time one is a few milliseconds later and is the "together" one: its push tells the earlier waterer "You watered together 💧"; the earlier one's push is plain. Each phone played its own effect at the tap; when the snapshot shows the pair, the rainbow overlay appears on both. |
| One person waters from two devices | The second batch is refused by the 12-hour rule: within 2.5 s → the error strip "You already watered recently. You can water again …"; queued → the "didn't go through" notice. |
| Planting while the proposer edits | The plant transaction re-reads the seed: its version changed → nothing written, "Sam just changed this. Take another look." |
| The proposer takes a seed or request back and sends it again under the same fixed id, between the partner's tap and the transaction's read (ABA) | The re-created proposal restarts at `rev 1` but carries a new server `at`; the version check fails → "Sam just changed this. Take another look." Nothing the partner did not see is planted or agreed. |
| Two seeds of mine sent from two of my devices at once | Each sending transaction (T0) reads `seed_<me>_1…3` and takes the first free number; contention retries the body, which takes the next one, or fails with `.tooManySeeds`. |
| Planting while the proposer takes it back | The seed is gone: "Sam took this back." |
| Taking back while the partner plants | The seed is gone and a tree carries its key: "Too late, Sam planted it just now 🌳" and the ceremony plays. |
| Both answer a seed with their own version | Counters are transactions comparing the version: the second aborts with "Sam just changed this. Take another look." |
| Both send Our tree's seed | Fixed id in a transaction: the second sender sees "Sam sent one at the same moment. Here it is." |
| Two seeds planted at once into the last free slots | Each plant transaction reads every slot; contention retries the body, which picks the next free slot, or fails with `.full`. |
| A look change and a change agreement cross | The agreement applies its proposal's look; the look change, queued, lands after and wins (both are legitimate; cosmetic). |
| A start-date agreement and a legacy direct edit cross | The rules refuse the agreement (`fromStartDay` no longer matches); the client deletes the void suggestion and shows the "changed in an older version" notice. |
| A rest request and a change request on the same tree | Whichever is carried out first wins; a change on a rested tree finds no tree (`.gone`) and is deleted as void. |
| The proposer edits while the partner counters | Both transactions compare the version; the loser sees `.changed` or `.notYours`. An edit is never queued, so it cannot land after a planting. |
| A legacy partner plants while `seed_our` waits | Planting `seed_our` is refused (`config` exists): "Your start date was just set in an older version of Coupley. Your tree is planted."; the seed is deleted; its place and look become the home invite. |
| A consent transaction times out but commits | The UI said "That didn't reach Sam yet…"; the listener shows the truth a moment later (and the ceremony plays for the planter). |

### J2. Time zones and daylight saving

- Every instant (waterings, plantings, proposals) is a server timestamp shown in the viewer's zone (`FutureLetterClock`); the journal adds the partner's local time when their `users.timezone` differs.
- Thresholds are durations: 48 hours is 48 hours across a DST change.
- Reminders are "the first 19:00 local at or after the threshold", floating calendar triggers: they stay at 19:00 through DST and travel.
- Days (start date, moment) are stored calendar days read with `localDay(ofStored:)`: the same date for both partners everywhere except UTC−11 and UTC+14 on legacy builds (an existing limit).
- Pushes format a stored day as its UTC date and a legacy instant in the recipient's zone.
- Quiet push hours use the recipient's `users.timezone`.
- The sky follows the place's zone; a place without `tz` (or no place) uses the phone's.

### J3. Clock skew

- The server decides everything that matters: watering times, the 12-hour rule, planting and agreement times. Changing the phone's clock cannot water early, backdate a watering or reorder a planting.
- The phone's clock only decides how fresh the garden *looks*, corrected by the server offset estimate. A wildly wrong clock shows "Ready for water" a little early or late, nothing more; ages use `max(0, now − at)`.
- "You can water again …" is the server time of my last watering + 12 h, shown in local time.

### J4. Offline

- Watering and a look change queue offline (confirmed writes, ≤ 2.5 s) and get the server's time on arrival.
- Every proposal and every consent action is a transaction: it fails at once offline ("You're offline. Planting needs a connection so you both see the same tree."); none is ever queued, so no seed or answer can land later against state that changed.
- First launch offline: Our tree is drawn from the start date and the cache; recording happens on the next online start; the garden says "Connect once to start your garden." if the probe never succeeded on this install.
- Nothing hangs: confirmed writes return within 2.5 s; transactions within 10 s.

### J5. Disconnect, unpairing, account deletion

- **Disconnect**: the rules refuse every garden write (`active()`); both phones leave `.ready`, which cancels garden reminders (pending and delivered) and purges the garden caches, the backdrop cache, snapshots and recent places.
- **Delete shared data (garden build)**: `timeTreeMeta` is a required step of `deleteSharedData` (a failure surfaces instead of being swallowed); then the couple document is deleted and `onCouplePurged` removes anything left.
- **Delete shared data or the account from 1.2**: 1.2 deletes `timeTreeMeta` best-effort; `onCouplePurged` removes whatever remains. **From 1.1**: 1.1 never touched `timeTreeMeta`; `onCouplePurged` removes it.
- **A new pairing** starts an empty garden (a new couple document).
- `users/{uid}.capabilities` and `gardenPushToken` carry no personal content and go with the user document.

### J6. Smaller cases

- Notes are trimmed; whitespace-only is no note; graphemes and UTF-8 bytes are both capped so the server never refuses an accepted note.
- Notifications switched off: discovery on Journey and Home still works.
- The partner renames themself: pushes use the name at send time.
- A moment before the relationship began ("where we first met"): allowed; that tree may be older than Our tree.
- Our tree's title never changes; its change requests carry a place and a look only.
- An "area" place shows its locality as its name unless the couple typed one.
- Letters, memory stars and the crown ring only ever appear on Our tree.
- A stage change while a page is visible (midnight): the tree redraws on the next frame, no animation (as today).
- `UserSession.demo` and unpaired sessions: the garden view model never listens; DEBUG-only previews use `InMemoryGardenService` (K7).
- A preset title in another language: the stored title is the base default ("Our first trip"), so a partner whose phone is in another language reads the preset's localized title; a title the couple typed shows exactly as typed for both.
- A slot reused after a rest: identity is the `key`, so ceremony and seen flags and push claims never collide.
- A tree deleted while viewed: the pager selects its neighbour; an open postcard closes with "This tree is resting now."
- Reduce Motion toggled mid-effect: the effect ends at its last frame and the tree shows its fresh pose.
- Low Power Mode: ambient life pauses (as the tree does today); one-shot effects still play.
- The widget is unchanged.

---

## K. Test plan

### K0. Test environment and prerequisites

**On this Mac** (checked 14 Nov 2026):

| Tool | State | Needed for |
|---|---|---|
| Java 21 runtime | **missing** ("Unable to locate a Java Runtime"). Installing one is a download that needs the user's approval (L2 #0), e.g. `brew install --cask temurin@21`, then `export JAVA_HOME=$(/usr/libexec/java_home -v 21)` | every emulator run: K1 (rules gate and mutants), K2's end-to-end suite, K5 against the emulators |
| firebase-tools | 15.15.0, installed | emulators, deploys |
| Node | 20.19.6, installed | the rules and functions suites (`functions/package.json`'s `engines: 22` only sets the deployed runtime) |
| Xcode | iOS 26.1 SDK | two iOS 18.6+ simulators |

**The emulators for the app** (repo root): `firebase emulators:start --only auth,firestore,functions --project demo-coupley-rules` (default ports, `firebase.json` has no `emulators` block: Auth 9099, Firestore 8080, Functions 5001, UI 4000; the functions load with the dummy `functions/.secret.local` of G8.2, and every push lands in the `pushDryRun` outbox). The `demo-` project keeps everything offline: nothing can reach `coupley-fcbb2`. For K5.10, add `--config <scratchpad>/firebase.pre-garden.json`: a copy of `firebase.json` whose `firestore.rules` points at the pre-garden rules saved from `git show 155ed55:firestore.rules` (no `appConfig` match).

**The app switch** (P4, `Coupley/Core/FirebaseEmulatorSwitch.swift`, the whole file inside `#if DEBUG`; Release builds contain none of it):
- Launch argument `-useFirestoreEmulator` (scheme → Run → Arguments, or `xcrun simctl launch <device> <bundle id> -useFirestoreEmulator`); optional `-emulatorHost <ip>` for a physical device (default `127.0.0.1`, which a simulator shares with the Mac).
- `AppDelegate.application(_:didFinishLaunchingWithOptions:)` replaces its first line, before `NotificationService.shared` or anything else touches Firebase:
  ```swift
  #if DEBUG
  if FirebaseEmulatorSwitch.isRequested { FirebaseEmulatorSwitch.configureFirebase() } else { FirebaseApp.configure() }
  #else
  FirebaseApp.configure()
  #endif
  ```
- `configureFirebase()`: builds `FirebaseOptions` from `GoogleService-Info.plist`, sets `projectID = "demo-coupley-rules"` (the emulators' project, so the CLI's rules and the function triggers apply to the app's writes and the real project's data is unreachable), calls `FirebaseApp.configure(options:)`, then `Auth.auth().useEmulator(withHost: host, port: 9099)` and `Firestore.firestore().useEmulator(withHost: host, port: 8080)` (host plus SSL off) before the first Firestore call, and sets `isActive = true` (the Debug menu's Status row). The SDK's on-disk cache is per project id, so emulator data never mixes with real data.
- Accounts: each simulator signs up with the app's existing email/password flow (`AuthService`: `createUser(withEmail:password:)`) against the Auth emulator, and the two pair through the normal pairing flow (Firestore only; the app calls no callable function). Sign in with Apple and Google do not work against the Auth emulator.
- Known limits of this mode: no FCM token (Firebase Installations needs the real project), so push routing is tested with `xcrun simctl push` payloads (K5.11) and push content with the functions emulator's dry-run outbox (G8.2); the AI endpoints (`onRequest`, production) reject emulator tokens, so AI features fail; photo features are out of scope.

**Fallback without the switch** (so no gate depends on it): K5.10 runs against production **before Gate 1** on a test couple with a DEBUG garden build. The deployed rules have no `appConfig` match, so the probe is denied exactly as in the field, and the build writes nothing garden-related (the capability is announced only after an enabled probe; the only write is the additive `gardenPushToken` user field). The other K5 checks then run on a production test couple after Gate 1.

**Legacy builds for K5.7**: `git worktree add <scratchpad>/coupley-1.2 155ed55` (the shipped 1.2), likewise `a33486e` (the garden-less 1.3) and `1825885` (1.1), each built from its own worktree and never committed to. Legacy builds have no emulator switch, so K5.7 runs on a production test couple after Gates 1 and 2 (optionally, a scratch-only copy of the switch lets the 1.2 worktree join the emulators).

### K1. Rules (emulator, P1)

`firestore-tests/garden.rules.test.mjs` (F3, 50 tests) with the existing `memories` and `futureLetters` suites in one run (F5), then the 15 mutants (F4). Needs Java 21 (K0). Gate for asking to deploy the rules: green three times in a row and every mutant caught.

### K2. Functions (P2)

`node --test functions/test/garden.test.js` (pure logic, G8.1; runs today on Node 20.19) and the emulator end-to-end suite (G8.2, needs Java 21) with the dry-run outbox. Gate for asking to deploy the functions.

### K3. Pure Swift logic (no test target exists)

Compiled in the scratchpad with `swiftc` and the project's flags (warnings as errors) against stubs of the project types and the repo's real `TreeGrowthStage.swift`, run as a macOS executable (`scratchpad/garden/typecheck/run.sh`). The contract's own logic was checked this way while writing this spec: state boundaries 47.99/48/71.99/72/167.99/168 h and a future server time, the thirst curve, moments at 23.9 h/24.1 h/7 d and own waterings, effect determinism and no repeat, water actions, the primary-action resolver, place rounding, the sky at noon and night in Asia/Ho_Chi_Minh, seasons for Hà Nội/Paris/Melbourne/no place, the revival overshoot, the tree frame on the knoll, the UTF-8 note cap; and, after the review: the **garden-level state** (`L` 80 h ago and a tree planted 2 h ago ⇒ garden `thirsty`, CTA `waterDue`, resolver `heroWater`, the new tree's look freshly planted (wet soil and dew, no lushness) and Our tree's plain, with no page input to any control), **no hero button and a filled +** in `loading` and every `unavailable` reason with and without a start date, `GardenProposalVersion` (millisecond conversion; a re-created proposal at `rev 1` with a new `at` differs; no version while pending), **seed ids** (first free number, full, malformed ids rejected, proposal-id recognition), **titles** (a stored base default shows the localized title, typed text shows as typed, `storedTitle` trims and falls back to the default), the localized `spokenSetting` format, `GardenMotionGate` (a Journey sheet freezes the page; Low Power allows effects only; a neighbour is frozen), `GardenBackdropBudget` (3.12 MB per page variant at 351×208@2x, 3.70 MB at 416 pt, a 6-variant memory limit) and the **monotonic reminder guard** (an older plan is ignored, the same or a newer one applies, a cold empty snapshot cannot cancel, no-Our-tree and toggle-off plans always cancel, nothing stored ⇒ applies). P3 adds, the same way: `GardenCopy` (every B3 status row, CTA titles for 1 and n trees, after-watering lines, request lines, journal pairing and the partner-time line), `GardenCodec` round trips (every document kind; unknown tokens; a planted tree without two planters ignored; raw `Timestamp` copies untouched; the version the codec shows equals the one `GardenTransactions` computes from the same raw snapshot; a 1.2 `Timestamp` with nanoseconds), the pure transaction bodies (T0 takes the first free `seed_<me>_n` and fails with `.tooManySeeds` at three; T3/T6/T7/T10–T12 refuse a re-created proposal with `rev 1` and a new `at`; T7 leaves an `alsoDelete` seed that is no longer mine), the garden-level copy (swiping between a fresh new tree and a thirsty Our tree changes neither `hero.status`, `hero.waterTitle` nor `primaryAction`), and `displayTitle` everywhere a title is shown; P4 adds the reminder plan (first 19:00 at or after +48 h / +7 d at 08:59, 19:00, 19:01, across Europe/London and America/New_York DST changes; delivered-reminder pruning by watering id) and the interleaving case (a push plan for a newer watering, then a queued chain step built from an older cached snapshot: no `tt.garden.ready` for the older watering, `lastWateringMs` unchanged).

### K4. Rendering checks (P5–P8)

`ImageRenderer` contact sheets (macOS or simulator) for the user's art review: 8 scenes × {day, night, the 06:00 and 19:00 blends} × 6 seasons × light/dark, at 351×208 and 402×208 and the 168 pt band; nothing drawn outside the band; the trunk base on the knoll apex; the front grass overlapping the trunk; 5 species × 8 stages × lushness {0, 1}, and × thirst {0.5, 1} for the look kept behind `GardenTreeLook.withersWhenThirsty` (the app never draws thirst, C6), with letters on Our tree's species (envelopes ride the drooped limbs; tap targets land on them); every effect at t = 0.25/0.5/0.75; the ceremony's key frames.

### K5. Simulator and device checks (two simulators, two accounts; against the emulators through the DEBUG `-useFirestoreEmulator` switch (K0), or on a production test couple after Gate 1 where stated)

1. **Existing couple, first launch** (an anchor written the 1.2 way): same day count, stage, letters, stars, crown; Meadow and oak; "Give it its first water"; the invite card; `tree_our` recorded `legacy`.
2. **New couple**: Our tree's seed → the partner holds to plant → ceremony on both (the proposer's on its next Journey visit) → `config` in the 1.2 format (a 1.2 build reading it is checked in K5.7). Then the proposer takes a seed back and re-sends it while the partner's plant sheet is open: planting answers "Sam just changed this. Take another look." (version check).
3. **Watering loop**: water with a note; partner: push, Home row, wet soil, dew, note tag, the stored effect replayed, "Water back"; water back → together on both, the rainbow for 24 h, both cans; the 12-hour lock and its copy.
4. **Time travel** (lab clock offset): ready, thirsty and resting copy while every tree keeps its plain look (lush only in the first 48 h after a watering; never a droop, 0.0 #3); the rain returns; reminders at 19:00.
5. **Seeds**: send, edit, take back, counter, let go, Not now; both send Our tree's seed at once; plant-while-edit (lab "delay the next commit 3 s"); garden full; a fourth open seed of mine → "You have 3 seeds waiting for Sam…"; duplicate preset → "Plant Sam's".
6. **Start date**: suggest, agree, keep; a 1.2-style direct write (lab button or a 1.2 build) → the notice, the void suggestion deleted.
7. **Partner on a legacy build** (production test couple after Gates 1 and 2, K0): the second simulator runs **`155ed55`, the shipped 1.2**. Check: "Sam needs the latest Coupley…", Tell Sam sends only after Send; no garden push arrives at the 1.2 phone; a 1.2 start-date edit (a raw instant through a plain `setData(merge:)`) shows the "changed in an older version" notice, voids a pending suggestion and keeps day counts equal on both phones; 1.2's "Delete shared data" after a disconnect (its purge has no Future Letters step and deletes `timeTreeMeta` best-effort) leaves nothing once `onCouplePurged` has run. Repeat the start-date edit and the purge with **`a33486e`** (the garden-less 1.3) and the purge with **`1825885`** (1.1, which never purges `timeTreeMeta`: `onCouplePurged` must remove it).
8. **Places**: search a café in Hà Nội and a beach in Đà Nẵng; drop a pin (area by default, 2 decimals in Firestore); postcard light/dark with the attribution; Open in Maps; the places map (pin vs circle); no location prompt anywhere (Settings → Privacy & Security → Location Services lists no Coupley entry).
9. **Offline** (a production test couple after Gate 1 with Network Link Conditioner at 100% loss, or the emulators stopped with `--export-on-exit` and restarted with `--import`): watering pending then delivered with the server's time; sending a seed and planting fail fast with the offline line; first launch offline.
10. **Rules missing**: the app on the emulators started with the pre-garden rules (K0 `--config`) → `unavailable(.rulesMissing)`, no garden write attempted, no hang, no hero button (the + filled), the rest of Journey fine; or, before Gate 1, the K0 production fallback. `appConfig/garden {enabled: false}` (written as `owner` on the emulator) → the pre-garden Journey.
11. **Push routing**: `xcrun simctl push` with `garden_watered`, `garden_proposal`, `garden_agreed` payloads (G4 keys), cold launch and foreground: Journey opens on the right tree, note or seed; a payload with another `coupleId` opens the overview; a watering push while backgrounded moves the pending reminders, checked in the lab's **Reminders** viewer (K6): `tt.garden.ready` moves to the new watering, a delivered one for the older watering is removed, and a later "older snapshot" from the lab changes nothing.
12. **Accessibility**: VoiceOver through the hero (adjustable pager, custom actions, announcements), requests, every sheet, the ceremony and the map list; Reduce Motion across every effect, replay and the ceremony; Dynamic Type up to AX5; Bold Text; Increase Contrast (solid chips); dark mode on every scene; both `ThemeVariant`s.
13. **Hero height**: 375×667 (iPhone SE 3rd gen) — the countdown block's first row on the first screen when no request card shows; AX5 reachable by scrolling; 402 and 440 pt widths.
14. **Performance** (A12, else A13; Instruments): C11 budgets; no static-layer renders while idle; nothing animating on a hidden tab, under any Journey sheet (open the water-note, plant and Garden sheets) or in Low Power Mode; no hitch over one frame while paging or watering. **First appearance**, measured cold (disk tier empty: lab → Backdrop → Clear disk) and warm: the placeholder on the first frame, the band complete within 300 ms cold and 100 ms warm, no frame over 16.7 ms. **Paging under memory pressure**: 8 trees in 8 different scenes at 18:30 local (both variants needed): no main-actor render while a swipe is in flight (signpost `garden.backdrop.render` only between swipes), the memory tier within `GardenBackdropBudget.memoryCostLimit`, neighbours present in memory after 0.3 s of rest.
15. **Time zones**: the second simulator with `TZ=America/Los_Angeles`: times, the journal's partner-time line, the quiet push flag (functions suite), the sky by place zone, a DST day.

### K6. DEBUG lab (`GardenLabView`, P10, from the Debug menu)

On `InMemoryGardenService` (never writes Firestore): clock offset slider (0, +47, +71, +167, +200 h) and time scale (1×, 60×); scripted partner: waters (with or without a note), sends a seed, counters, takes a seed back and re-sends it (ABA), asks to rest, suggests a start date, "Pretend Sam is on 1.2"; effects lab (each effect, the first drop, a replay, the many-trees ripple, a Reduce Motion preview); scene gallery (8 scenes × a time-of-day slider × season × light/dark); species gallery (5 × 8 stages × thirst 0/0.5/1, passed to the painter directly so the look kept behind `GardenTreeLook.withersWhenThirsty` stays reviewable; letters on/off); ceremony replay for any tree; "Write the start date like 1.2"; "Delay the next commit 3 s"; a frame-time HUD (`CADisplayLink`). Two viewers read the real system state:
- **Reminders**: the pending and the delivered `tt.garden.*` requests from `UNUserNotificationCenter` (identifier, next trigger date in local time, `wateringId`, body), the stored `lastWateringMs`, **Re-plan now**, **Simulate a watering push** (calls `GardenReminderScheduler.replanFromPush` with a chosen time, as the background wake does) and **Simulate an older snapshot** (queues a plan one hour older: nothing may change).
- **Backdrop**: memory-tier use against `memoryCostLimit`, disk-tier size, hit/miss/render counts since launch, **Clear memory**, **Clear disk**.

### K7. SwiftUI previews

One per scene and sky variant, per species, per hero state (B3–B3.5), per sheet, and the ceremony, in the `#Preview` style of `RelationshipTreeCanvas.swift` (frames drawn so clipping shows). `#Preview` bodies compile in Release (none of the repo's 43 `#Preview` blocks is guarded), and `InMemoryGardenService` exists only in DEBUG, so **every preview that builds a `GardenViewModel` or touches `InMemoryGardenService` sits inside `#if DEBUG … #endif`**; previews of pure painters, overlays and value-driven views need no guard. M3 builds Release to prove it.

---

## L. Risks, approvals, open questions and rollout

### L1. Risks

1. **Scope.** The largest Journey change yet (≈ 35 new files). Mitigated by the shared contract, ten packages with disjoint files, day-1 stubs and gates.
2. **Hand-drawn art must look good.** No art pipeline: quality lives in Canvas code. Mitigation: K4 contact sheets reviewed in light and dark before merge; scenes split across two engineers.
3. **Rule complexity.** The `timeTreeMeta` block becomes the file's most intricate. Mitigation: 50 tests, 15 mutants, the whole-file gate, ≤ 5 distinct document reads per request.
4. **Legacy coexistence.** A legacy partner can still change the start date alone (stated in A10; rules cannot tell a legacy writer of `config` apart). `onCouplePurged` must be deployed before the garden app reaches users, so a 1.1 deletion cannot orphan places.
5. **Push fatigue.** Bounded by the 12-hour rule (≤ 2 watering pushes a day per sender), the 6-a-day garden cap, passive nights, the Garden toggle and at most two local reminders per watering.
6. **Privacy label and policy.** App Store Connect must declare Precise Location and `index.html` must ship the Places section on or before release.
7. **Older phones.** Budgets set (C11) and measured on A12/A13.
8. **Apple Maps coverage in Vietnam** is thinner: the pin and typed names are first-class.
9. **The Journey review is still editing** `TimeTreeHeader`, `TimeTreeView` and `RelationshipTreeCanvas`: re-read them before coding (M0).
10. **A reminder after a force-quit**: iOS does not deliver silent work to a force-quit app, so a "ready" reminder can fire after the partner watered; tapping it shows "Sam watered…". Accepted (the alternative is a scheduled server job).
11. **`onCouplePurged` deletes everything still under a deleted couple**, not only the garden (e.g. Future Letters bodies a 1.2 deletion leaves today). Intended: it is what "Delete shared data" promises.
12. **Tooling.** The rules gate, the mutants and the functions' end-to-end suite need a Java 21 runtime, which this Mac lacks; until the user approves installing one (L2 #0), no emulator gate can run and no deploy can be requested. The pure functions tests and the contract checks run without it.
13. **Emulator mode is partial.** Against the emulators the app has no FCM token, no Apple/Google sign-in and no AI; those paths are covered by `simctl push`, the dry-run outbox and the production test couple (K0, K5.7).

### L2. What needs the user's explicit approval

| # | Action | When |
|---|---|---|
| 0 | Installing a Java 21 runtime on this Mac (a download, e.g. `brew install --cask temurin@21`), needed by the Firestore and Functions emulators | before the P1 and P2 gates (and before any K5 run on the emulators) |
| 1 | `firebase deploy --only firestore:rules` — the whole file: the working tree's hardened `memories` and Future Letters blocks, the garden block and `appConfig` | after K1 (three green runs, mutants caught); first |
| 2 | `firebase deploy --only functions:onTimeTreeMetaWritten,functions:onCouplePurged,functions:cleanupOldData` (the `sendNotification` change rides along) | after K2; after the rules; before the app |
| 3 | Publishing the privacy page (`index.html` on GitHub Pages: commit and push) with the Places section, the Couple data line, the Apple Maps bullet and the new date | on or before the day the garden build reaches users |
| 4 | App Store Connect → App Privacy: add **Location → Precise Location** (App Functionality, linked, not tracking) for exact places and **Location → Coarse Location** with the purpose App Functionality (linked, not tracking) for "area" places, keeping any purpose already declared for it; **Other User Content** if not already declared | before submitting the garden build |
| 5 | `Coupley/PrivacyInfo.xcprivacy`: Other User Content is declared on the branch now; Precise Location and Coarse Location are re-added in the Gate 3 change that turns the garden on for every configuration (D6), so they ship in the garden binary and never in a pre-Gate 3 Release build; whether to also declare the pre-existing photos, name and user-id collection the manifest omits today | with the garden build (Gate 3) |
| 6 | Creating `appConfig/garden {enabled: false}` in the console | only if the garden must be switched off after release |
| 7 | Submitting the garden build (version number per Q5) | after Gate 3 |

### L3. Open questions for the user

**Answered by the user on 14 Nov 2026 (see 0.0).** Kept for the record:

1. **"Bởi cả 2"**: either partner waters and watering together within 24 h is a celebrated bonus (**default**), or the garden counts as watered only when both have watered in the same cycle (closest to "by both", but a busy partner leaves it half-dry)? The data supports both; only `GardenWaterState`, the copy and the push moment change.
2. **First start date with a partner on an older app**: keep "both must agree" — the seed waits and the older-app partner can still set the date from their side (**default**) — or let the garden user set it alone, as today?
3. **How place trees grow**: from the day of their moment, so a 2023 trip arrives as a big tree with a time-lapse ceremony (**default**), or from the day they are planted (every tree starts as a seed)?
4. **Constants to confirm** (all server-enforced or server-computed): one watering per person per 12 h; "together" = within 24 h; ready at 48 h, thirsty at 72 h, resting at 7 days; 8 trees; 3 open seeds per person; two reminders at 19:00; at most 6 garden pushes a day; quiet 22:00–06:59.
5. **Release order and version**: the garden is capability-based, so it works whichever ships first, but which version number does it get, given that 1.3 (`a33486e`: Future Letters and the Journey overhaul, `MARKETING_VERSION` 1.3) is the current release build and its review fixes are still landing?

### L4. Rollout

| Gate | What | Owner |
|---|---|---|
| 0 | The contract copied to `Coupley/Features/Garden/Models/GardenContract.swift`; every package's day-1 stubs merged, including P4's emulator switch (so P3 and P10 can test against the emulators from day 1); the app builds with zero warnings in Debug and Release; `GardenFeature.isEnabled` is on in DEBUG and off in Release (the contract's `#if DEBUG`), so a release cut from the branch before Gate 3 stays pre-garden | lead |
| 1 | **approval 0** (Java 21) → P1 green (K1) → **approval 1** → rules deployed | P1 + user |
| 2 | P2 green (K2) → **approval 2** → functions deployed | P2 + user |
| 3 | P3–P10 merged and reconciled (M3); the lead sets `GardenFeature.isEnabled = true` for every configuration (dropping the `#if DEBUG`) and, in the same change, re-adds Precise and Coarse Location to `PrivacyInfo.xcprivacy` (D6); K3–K5 pass; **approvals 3–5** done (the privacy page published with a new *Last updated* date, the App Store privacy answers); rules and functions live (Gates 1–2). The checklist is in `GardenFeature`'s doc comment | lead + user |
| 4 | TestFlight: two garden phones and a 1.2 phone, every push type, a purge from 1.2 → **approval 7** → submit | lead + user |

No phase splits the user's request: places, extra trees, consent, watering, pushes, scenes and animations all ship together at Gate 3.

---

## M. BUILD PACKAGES

### M0. Ground rules for every package

- **Re-read before coding**: `TimeTreeView.swift`, `TimeTreeHeader.swift`, `RelationshipTreeCanvas.swift`, `JourneyLetter.swift` may have changed since 14 Nov (the Journey review). Build against the code as it is then; if a signature here no longer matches, keep this spec's intent and report the delta at reconciliation.
- **The contract is read-only** (`Coupley/Features/Garden/Models/GardenContract.swift`). A needed change goes to the lead, who changes it for everyone.
- **Disjoint ownership**: a package edits only the files it owns below. Everything else is read-only to it.
- **Day-1 stubs**: on day 1 every package commits its owned files with every symbol other packages consume (exact signatures from this section, bodies returning placeholders), so cross-package references compile from the start. Stub-only commits must build with zero warnings.
- **Zero warnings** in Debug and Release, Swift 5 mode, default MainActor isolation; explicit imports (MemberImportVisibility).
- **Isolation**: `nonisolated` for the contract's values, the scene painters (P5/P6) and the effect painter (P8); none of them calls a `TreeGrowthStage` or `TreeSeason` member (main-actor isolated, unchanged). The tree painter (P7) keeps today's main-actor isolation.
- **Copy** comes from this spec verbatim; garden strings live in `GardenCopy` (P3) or the contract, except sheet-local labels and placeholders owned by P9/P10 views.
- **Localization** (the working tree's convention): every user-facing garden string is `String(localized:comment:)` (or a `Text`/`LocalizedStringResource` literal in a view), written as a whole sentence or as one format with placeholders (`String(localized: "\(name) watered your garden")`), never by joining fragments; VoiceOver labels that state several facts join complete localized sentences. A `String` handed to `BrandCTA` is already localized. Titles are shown through `GardenTree.displayTitle` / `GardenPreset.displayTitle(stored:)`; preset titles are stored as base-language data (`storedDefaultTitle`), never localized text.
- **Previews**: any `#Preview` that builds a `GardenViewModel` or touches `InMemoryGardenService` sits inside `#if DEBUG … #endif` (K7).

**Shared read-only files** (all packages): the contract; `Coupley/Core/FirestoreConfirmedWrite.swift`; `Coupley/Core/DesignSystem.swift` (except P10); `Coupley/Features/TimeTree/Models/JourneyLetter.swift` (except P10); `RelationshipAnchor.swift`; `TreeGrowthStage.swift` (main-actor isolated; nobody changes it); `TimeMemory.swift`; `Coupley/Features/Auth/Services/AuthService.swift` (email/password sign-up used against the Auth emulator); `Coupley-Info.plist`; `Coupley/GoogleService-Info.plist` (read by the emulator switch); `CrownMilestone.swift`; `Coupley/Features/FutureLetter/Models/FutureLetter.swift` (`FutureLetterClock`); `Coupley/Features/FutureLetter/Services/*` and `ViewModels/*` (patterns); `Coupley/Features/CoupleSync/Models/CoupleModels.swift` (`UserSession`); `Coupley/Features/TimeTree/Services/TimeTreeAnchorService.swift` (`FirestorePath.timeTreeMeta`); `TimeTreeNotificationScheduler.swift`; `CrownCelebrationOverlay.swift`; `Coupley/Features/CoupleChat/Services/CoupleChatService.swift` (`CoupleChatServicing.sendText(_:coupleId:senderId:)`); `firestore-tests/emulator.mjs`; `firebase.json`; `functions/package.json`.

### P1 — Firestore rules and emulator tests

- **Owns**: `firestore.rules`, `firestore-tests/garden.rules.test.mjs`.
- **Prerequisite**: a Java 21 runtime (K0; installing it needs the user's approval, L2 #0).
- **Does**: F1 exactly (replace the `timeTreeMeta` block; add `appConfig`; header comments; the bounded place-seed ids with `isMySeedDoc`); F3's 50 tests on `forDatabase('garden-rules')`; F4's 15 mutants run from the scratchpad (not committed); F5 gate.
- **Provides**: the deployed-to-be rules matching E (doc ids including `seed_<uid>_<1–3>`, `docType`, field names, `hasOnly` lists, rounding, `rev`, `at == request.time`, 710-minute cooldown).
- **Consumes**: E (field names must equal `GardenField` in the contract; seed ids must equal `GardenDocID.placeSeed`).
- **Done when**: all suites green three times in a row; every mutant caught; a short note listing access counts for the heaviest requests.

### P2 — Cloud Functions and their tests

- **Owns**: `functions/index.js`, `functions/garden.js` (new), `functions/test/garden.test.js` (new), `functions/test/garden.emulator.test.mjs` (new), `functions/.gitignore` (new: `.secret.local`, `.env.local`).
- **Prerequisite**: Node 20+ (installed) for the unit suite; a Java 21 runtime for the emulator suite (K0, L2 #0).
- **Does**: G1 (`sendNotification` `quiet` and `contentAvailable` options, the emulator dry run, the `buildRelationshipContext` comment), G2 (including the `seed_<uid>_<1–3>` proposal ids), G3 (`onTimeTreeMetaWritten` and helpers), G6 (`onCouplePurged`), G7 (`cleanupOldData` additions), G8 tests.
- **Provides**: push types and payload keys equal to `GardenNotification` (contract); `wateringMoment` equal to `GardenMoment.of`.
- **Consumes**: E field names; the existing helpers `getDisplayName`, `sendNotification`, `db`, `Timestamp`, `FieldValue`, `onDocumentWritten`, `onDocumentDeleted`.
- **Done when**: unit and emulator suites green; no place field, note or title is logged.

### P3 — Garden data, logic and view model

- **Owns**: `Coupley/Features/Garden/Models/GardenCopy.swift`, `Coupley/Features/Garden/Services/GardenService.swift`, `Coupley/Features/Garden/Services/GardenTransactions.swift`, `Coupley/Features/Garden/Services/GardenCodec.swift`, `Coupley/Features/Garden/Services/GardenConnectivity.swift`, `Coupley/Features/Garden/Services/InMemoryGardenService.swift`, `Coupley/Features/Garden/ViewModels/GardenViewModel.swift`, `Coupley/Features/Garden/ViewModels/GardenViewModel+Models.swift`.
- **Does**: A (all product rules client-side), E encoding/decoding (the shown `GardenProposalVersion` from the raw `at` Timestamp), I3 (garden-level state from `L` alone; per-tree visuals), I4 (T0–T13 with the version check, the watering batch, confirmed writes, the transaction wrapper), I7, all garden copy localized per M0 (B3 table, CTA titles, after-watering lines, B4 card lines, notices, Home line, journal entries, VoiceOver labels), replay/ceremony/set-aside (by seed key)/legacy-change detection, the server-offset estimate, the device cache, `purgeLocalCaches`, the DEBUG in-memory service with scripted partner actions and a clock offset.
- **Provides**: `final class GardenViewModel` with exactly the I3 API (`plant(_:seen:alsoDelete:)`, `agree(_:seen:)`); `final class FirestoreGardenService: GardenServicing`; `final class InMemoryGardenService: GardenServicing` (`#if DEBUG`, plus `var clockOffset: TimeInterval`, `var delayNextCommit: Bool` and `func simulatePartner(_ action: GardenLabAction)` with `enum GardenLabAction { case water(note: String?), sendSeed(GardenPreset), counterLatestSeed, recreateLatestSeed, askRest(GardenSlot), suggestStartDate(Date), pretendLegacy(Bool), writeStartDateLikeLegacy(Date) }`); `final class GardenConnectivity: GardenConnectivityMonitoring`; `nonisolated enum GardenCopy` (static functions returning localized strings); `static func GardenViewModel.purgeLocalCaches()`.
- **Consumes**: the contract; `FirestoreConfirmedWrite`; `JourneyCalendarDay`; `FutureLetterClock`; `CoupleChatServicing`; `UserSession`; `FirestorePath.timeTreeMeta(coupleId:)`; P4's `FirebaseEmulatorSwitch` (for its own emulator runs only).
- **Done when**: K3 logic cases pass; the lab drives every flow on the in-memory service; on two simulators against the emulators (K0, P4's switch) with P1's rules every action succeeds or fails with the documented `GardenError`; previews guarded per M0.

### P4 — Platform: reminders, push wake, notification settings, purge, compliance

- **Owns**: `Coupley/Features/Garden/Services/GardenReminderScheduler.swift` (new); `Coupley/Core/FirebaseEmulatorSwitch.swift` (new); `Coupley/Features/Widget/Services/WidgetSyncService.swift`; `Coupley/CoupleyApp.swift`; `Coupley/Features/SmartNudge/Services/NotificationService.swift`; `Coupley/Features/SmartNudge/ViewModels/NotificationViewModel.swift`; `Coupley/Features/SmartNudge/Models/NudgeModels.swift`; `Coupley/Features/SmartNudge/Views/NotificationSettingsView.swift`; `Coupley/Features/PartnerConnection/Services/ConnectionService.swift`; `Coupley/Features/Settings/Views/FAQView.swift`; `index.html`; `Coupley/PrivacyInfo.xcprivacy`.
- **Does**: the DEBUG emulator switch (K0) on day 1; H (scheduler with the monotonic guard, chain refactor, latest-watering listener on confirmed waterings, foreground and toggle re-plans, `activeCoupleId`, AppDelegate wake joining the serial chain when bound), the `gardenPushToken` write and clear, `NotificationPreferences.garden` and its mirror, the Garden toggle, garden routing in `handleNudgeTap`/`handleTappedNudge` (coupleId check), the required `timeTreeMeta` purge, leaving-`.ready` cleanup (calls the purge entry points of P3, P5, P9), D6 exact text in the FAQ (the reworded sentences), the privacy page and the manifest (Other User Content now; Precise and Coarse Location at Gate 3, D6).
- **Provides**:
  ```swift
  #if DEBUG
  enum FirebaseEmulatorSwitch {
      static var isRequested: Bool { get }      // the -useFirestoreEmulator launch argument
      static var host: String { get }           // -emulatorHost, default "127.0.0.1"
      static private(set) var isActive = false  // true once configureFirebase() ran
      static func configureFirebase()           // FirebaseOptions (projectID demo-coupley-rules) + Auth 9099 + Firestore 8080
  }
  #endif
  @MainActor final class GardenReminderScheduler: GardenReminderScheduling {
      static func replanFromPush(coupleId: String, wateredAtMs: String, wateringId: String) async
  }
  // WidgetSyncService.shared:
  func gardenRemindersPreferenceChanged()
  func queueGardenReplan(fromPushWateredAtMs ms: Int64, wateringId: String)
  ```
- **Consumes**: the contract; `JourneyFocus.garden(_:)` (P10); `GardenViewModel.purgeLocalCaches()` (P3); `GardenBackdropCache.shared.removeAll()` (P5); `GardenMapSnapshotter.shared.purge()` (P9).
- **Done when**: the switch connects two simulators to the emulators and a Release build contains none of it; K3 reminder-plan and interleaving cases pass; K5.11 re-plan and routing checks pass (lab Reminders viewer); the purge order compiles with the other packages' stubs; FAQ/privacy/manifest text matches D6 word for word.

### P5 — Scenes I: kit, cache, registry and four scenes

- **Owns**: `Coupley/Features/Garden/Views/Scenes/GardenSceneKit.swift`, `Coupley/Features/Garden/Views/Scenes/GardenBackdropCache.swift`, `Coupley/Features/Garden/Views/Scenes/GardenSceneRegistry.swift`, `Coupley/Features/Garden/Views/Scenes/MeadowScene.swift`, `Coupley/Features/Garden/Views/Scenes/SeasideScene.swift`, `Coupley/Features/Garden/Views/Scenes/CityLightsScene.swift`, `Coupley/Features/Garden/Views/Scenes/MountainLakeScene.swift`.
- **Does**: C3 sky life (celestial, stars, clouds) and season particles as kit helpers; C4 scenes 1–4 (all three static layers seeded by `GardenSceneStyle.staticSeed(for:)`, never by the tree; three ambient passes seeded per tree; the watering accent; day and night palettes; seasons); the backdrop cache per C2 (memory tier with `GardenBackdropBudget.memoryCostLimit` set by `configure(band:scale:)`, disk tier `Library/Caches/GardenBackdrops/v<artVersion>/` decoded off the main actor and capped at 48 MB, renders with ImageRenderer at most one per frame and never for `cachedImage(for:)`, `prewarm` one key per run-loop turn, scale ≤ 2, far layer 1.35× wide, front layer bottom 32%, night/day variants only when needed, signposts `garden.backdrop.render`/`.disk`); the registry; swatches.
- **Provides**:
  ```swift
  nonisolated enum GardenSceneKit {
      static func hills(in size: CGSize, base: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat) -> Path
      static func knoll(in size: CGSize, apex: CGPoint, halfWidth: CGFloat) -> Path
      static func catenary(from: CGPoint, to: CGPoint, sag: CGFloat, count: Int) -> [CGPoint]
      static func scatter(count: Int, in rect: CGRect, seed: UInt64) -> [CGPoint]
      static func glints(count: Int, band: CGRect, seed: UInt64, time: TimeInterval?) -> [CGRect]
      static func frontGrass(in size: CGSize, blades: Int, seed: UInt64) -> Path
      static func snowCap(on path: Path, thickness: CGFloat) -> Path
      static func drawCelestial(in context: GraphicsContext, size: CGSize, sky: GardenSkyState, time: TimeInterval?)
      static func drawClouds(in context: GraphicsContext, size: CGSize, sky: GardenSkyState, time: TimeInterval?, seed: UInt64)
      static func drawSeasonParticles(in context: GraphicsContext, size: CGSize, state: GardenAmbientState, maxCount: Int)
      static func color(_ day: UInt32, _ night: UInt32, _ variant: GardenSkyVariant) -> Color
  }
  @MainActor final class GardenBackdropCache: GardenBackdropProviding {
      static let shared: GardenBackdropCache
      // the protocol: image(for:) async, cachedImage(for:), prewarm(_:), configure(band:scale:), swatch(...), removeAll()
      var stats: (memoryBytes: Int, diskBytes: Int, hits: Int, misses: Int, renders: Int) { get }   // the lab's Backdrop viewer
      func clearDisk()                                                                               // the lab
  }
  extension GardenSceneID { nonisolated var painter: any GardenScenePainting }
  nonisolated struct MeadowScene: GardenScenePainting      // + SeasideScene, CityLightsScene, MountainLakeScene
  ```
- **Consumes**: the contract; P6's four painter type names (registry).
- **Done when**: K4 sheets for scenes 1–4 approved; a render ≤ 8 ms and a disk hit ≤ 5 ms off-main on an A12; never more than one render per frame; the memory tier stays within `memoryCostLimit`; no text in any canvas; painters never call `TreeGrowthStage`/`TreeSeason` members.

### P6 — Scenes II: four scenes

- **Owns**: `Coupley/Features/Garden/Views/Scenes/LanternTownScene.swift`, `Coupley/Features/Garden/Views/Scenes/RiceTerracesScene.swift`, `Coupley/Features/Garden/Views/Scenes/CampusScene.swift`, `Coupley/Features/Garden/Views/Scenes/HomePorchScene.swift`.
- **Does**: C4 scenes 5–8 (static layers seeded by `GardenSceneStyle.staticSeed(for:)`, ambient passes, accents, palettes, seasons; Campus's clock hands at the place's time, drawn in the ambient pass so the cached layers stay static).
- **Provides**: `nonisolated struct LanternTownScene: GardenScenePainting`, `RiceTerracesScene`, `CampusScene`, `HomePorchScene` (each `init()`).
- **Consumes**: the contract; `GardenSceneKit` (P5).
- **Done when**: K4 sheets for scenes 5–8 approved; ≤ 30 moving primitives per scene.

### P7 — The tree painter

- **Owns**: `Coupley/Features/TimeTree/Views/RelationshipTreeCanvas.swift`, `Coupley/Features/TimeTree/Views/TreeCanvasSpecies.swift` (new), `Coupley/Features/TimeTree/Views/TreeCanvasVitality.swift` (new).
- **Does**: the I5 API (style, vitality, external clock, note tag, anchors), C5 species, C6 lushness/soil/dew/revival (and the thirst look kept behind `GardenTreeLook`), the sky-aware palette, drooped tap-target geometry; existing call sites and today's look unchanged with default arguments; previews for species and thirst.
- **Isolation**: `TreeCanvasPainter`, the species and vitality code and every helper reading `TreeGrowthStage`/`TreeSeason` members stay **main-actor isolated**, as today (I6); do not mark them `nonisolated`. `RelationshipTreeCanvas.anchors(in:stage:species:)` is main-actor too (its callers are views).
- **Provides**: the `RelationshipTreeCanvas` init and statics in I5.
- **Consumes**: the contract.
- **Done when**: K4 species/thirst sheets approved; `TimeTreeHeader`'s current hero renders pixel-identical with defaults; tree ≤ 2.5 ms per frame on an A12.

### P8 — Watering effects, overlays, ceremony and haptics

- **Owns**: `Coupley/Features/Garden/Views/Effects/WateringEffectPainter.swift`, `Coupley/Features/Garden/Views/Effects/WateringEffects+Pour.swift`, `Coupley/Features/Garden/Views/Effects/WateringEffects+Sky.swift`, `Coupley/Features/Garden/Views/Effects/GardenOverlays.swift`, `Coupley/Features/Garden/Views/Effects/PlantingCeremonyOverlay.swift`, `Coupley/Features/Garden/Services/GardenHaptics.swift`.
- **Does**: C9 (six effects, the golden first drop, analytic particles), the resting cans, rainbow, after-glow and dot ripple overlays, the Reduce Motion drop, C8 ceremony (with its Reduce Motion and VoiceOver versions), haptic patterns.
- **Isolation**: `WateringEffectPainter` and its extensions are `nonisolated` and use only what `GardenEffectFrame` hands them (anchors, sky, size); they never call `TreeGrowthStage`/`TreeSeason` members. The ceremony's time-lapse is a view over `RelationshipTreeCanvas` (main actor).
- **Provides**:
  ```swift
  nonisolated enum WateringEffectPainter: WateringEffectDrawing { }
  struct GardenRestingCansView: View { init(cans: GardenRestingCans, anchors: TreeCanvasAnchors) }
  struct GardenRainbowView: View { init(anchors: TreeCanvasAnchors, size: CGSize, opacity: Double) }
  struct GardenAfterGlowView: View { init(anchors: TreeCanvasAnchors, startTime: TimeInterval) }
  struct GardenDotRipple: View { init(dotCount: Int, startTime: TimeInterval) }
  struct GardenReducedMotionDrop: View { init(anchors: TreeCanvasAnchors) }
  struct PlantingCeremonyOverlay: View {
      init(ceremony: GardenCeremony, partnerName: String, myName: String?, onDone: @escaping () -> Void)
  }
  @MainActor final class GardenHaptics { static let shared: GardenHaptics
      func play(_ effect: GardenEffect, isReplay: Bool); func playPlanting(); func stop() }
  ```
- **Consumes**: the contract; `RelationshipTreeCanvas` (P7, for the ceremony's time-lapse and the shelf-free still frames); `GardenBackdropCache` and `GardenSceneID.painter` (P5) for the ceremony's scene.
- **Done when**: K4 effect frames approved; each effect ≤ 1.5 ms per frame; Reduce Motion versions verified.

### P9 — Places, maps and consent sheets

- **Owns**: `Coupley/Features/Garden/Services/GardenPlaceSearch.swift`, `Coupley/Features/Garden/Services/GardenMapSnapshotter.swift`, `Coupley/Features/Garden/Views/Places/GardenPlacePicker.swift`, `Coupley/Features/Garden/Views/Places/GardenMapView.swift`, `Coupley/Features/Garden/Views/Places/GardenSnapshotImage.swift`, `Coupley/Features/Garden/Views/Sheets/GardenPlantSheet.swift`, `Coupley/Features/Garden/Views/Sheets/GardenSeedSheet.swift`, `Coupley/Features/Garden/Views/Sheets/TreePostcardView.swift`; `Coupley/Features/TimeTree/Views/AnchorSetupSheet.swift`; `Coupley/Features/TimeTree/Views/MilestonePickerSheet.swift`; `Coupley/Features/TimeTree/Views/JourneyTreeGuideSheet.swift`.
- **Does**: D1–D5 (picker, MapKit, POI mapping, snapshotter with cache and attribution, the places map), B5.1 plant sheet/form (look carousel with swatches, species chips, live still preview, the Name field starting at the preset's localized title and sending `GardenDraft.storedTitle`, the `tooManySeeds` hint, every mode disabled offline), B5.2 seed sheet (hold to plant, seed packet, duplicate handling; every carry-out passes `proposal.version` as `seen` and is disabled while it is nil), B5.4 postcard and look picker, B5.7 suggest mode, B6 picker row and guide sections; all copy localized per M0, titles through `displayTitle`.
- **Provides**:
  ```swift
  @MainActor final class GardenMapSnapshotter: GardenMapSnapshotting { static let shared: GardenMapSnapshotter }
  struct GardenSnapshotImage: View { init(place: GardenPlace, scene: GardenSceneID, size: CGSize) }
  struct GardenMapView: View { init(garden: GardenViewModel, onOpenTree: @escaping (GardenSlot) -> Void) }
  struct GardenPlantSheet: View { init(garden: GardenViewModel, mode: GardenDraft.Mode) }
  struct GardenPlantForm: View { init(garden: GardenViewModel, mode: GardenDraft.Mode, onDone: @escaping () -> Void) }
  struct GardenSeedSheet: View { init(garden: GardenViewModel, proposalId: String,
                                      onPlanted: @escaping () -> Void, onOpenTree: @escaping (GardenSlot) -> Void) }
  struct TreePostcardView: View { init(garden: GardenViewModel, slot: GardenSlot, isPushed: Bool) }
  // AnchorSetupSheet:
  enum Mode { case directSave
              case suggest(currentStored: Date, partnerCanAnswer: Bool?, agreedOn: Date?,
                           onSuggest: (Date, String?) async -> Bool, onTellPartner: () -> Void) }
  init(viewModel: TimeTreeViewModel, existing: RelationshipAnchor?, myName: String?, partnerName: String,
       mode: Mode = .directSave)
  // MilestonePickerSheet: new trailing init parameter `onPlantTree: (() -> Void)? = nil`
  ```
- **Consumes**: the contract; `GardenViewModel` (P3, I3 API); `GardenBackdropCache` swatches (P5); `RelationshipTreeCanvas` still frames (P7).
- **Done when**: K5.5/5.6/5.8 pass; no location API is linked (`CLLocationManager`, `MapUserLocationButton`, `UserAnnotation` absent); attribution on every snapshot.

### P10 — Journey hero, garden sheet and app integration

- **Owns**: `Coupley/Features/Garden/Views/Hero/GardenHero.swift`, `Coupley/Features/Garden/Views/Hero/GardenScenePage.swift`, `Coupley/Features/Garden/Views/Hero/GardenRequestsSection.swift`, `Coupley/Features/Garden/Views/Sheets/GardenSheet.swift`, `Coupley/Features/Garden/Views/Sheets/GardenJournalView.swift`, `Coupley/Features/Garden/Views/Sheets/WaterNoteSheet.swift`, `Coupley/Features/Garden/Views/GardenHomeRow.swift`, `Coupley/Features/Garden/Views/Debug/GardenLabView.swift`; `Coupley/Features/TimeTree/Views/TimeTreeView.swift`; `Coupley/Features/TimeTree/Views/TimeTreeHeader.swift`; `Coupley/Features/TimeTree/Models/JourneyLetter.swift`; `Coupley/ContentView.swift`; `Coupley/Features/CoupleSync/Views/CoupleDashboardView.swift`; `Coupley/Core/DesignSystem.swift`; `Coupley/Features/Settings/Views/DebugMenuView.swift`.
- **Does**: B1–B4, B5.5, B5.6, B7; C1/C2 composition (band, overlays, pager, parallax, `GardenMotionGate` fed with `isJourneySheetPresented`, one clock per page, layer stack using P5/P7/P8, the placeholder band from `GardenSceneInfo.groundDay`/`groundNight` while images load, `configure(band:scale:)` once the band's size is known, `prewarm` of the neighbours after the pager settles for 0.3 s, `cachedImage(for:)` only while a swipe is in flight), Reduce Motion/VoiceOver/Dynamic Type for the hero (C10); no hero CTA in loading and unavailable states (`emptyHeroShowsButton`); `TimeTreeView` and `ContentView` integration (I5), `JourneyFocus.garden`, `TimeTreeHeader.showsHero`, `insetsContent`, the Home row, the lab (K6) with its Reminders and Backdrop viewers, the Debug menu link and its emulator status row.
- **Provides**: `JourneyFocus.garden(GardenFocus)` (day 1, P4 consumes); `TimeTreeView.init(..., garden: GardenViewModel, onOpenChat: @escaping () -> Void = {})`; `CoupleDashboardView` parameters `gardenLine: GardenHomeLine? = nil`, `onOpenGarden: ((GardenFocus) -> Void)? = nil`; `BrandCard`/`TierContainer` `insetsContent: Bool = true`.
- **Consumes**: everything above.
- **Done when**: K5 (1–4, 10–15) pass on two simulators against the emulators (K0, P4's switch); the one-filled-CTA resolver is respected in every state, loading and unavailable included; the hero height budget holds at 375×667; K5.14's first-appearance and paging measurements pass; every preview that needs the view model is inside `#if DEBUG` and the Release build is clean.

### M1. Dependency map (who consumes whose day-1 symbols)

```
contract ─► every package
P3 GardenViewModel ─► P9, P10          P5 kit/cache/registry ─► P6, P8, P9, P10
P7 RelationshipTreeCanvas API ─► P8, P9, P10
P8 effects/overlays/ceremony ─► P10    P9 sheets/snapshotter ─► P10, P4 (purge)
P10 JourneyFocus.garden ─► P4          P1 rules ─► P3 emulator checks
P2 functions ─► P4 routing checks (payload keys)
P4 FirebaseEmulatorSwitch (day 1) ─► P3, P10 emulator runs; P10 DebugMenuView status row
P4 GardenReminderScheduler ─► P10 lab Reminders viewer
P5 GardenBackdropCache.stats / clearDisk ─► P10 lab Backdrop viewer
```

### M2. Merge order

1. Gate 0: the contract + all day-1 stubs (one PR per package, stubs only), with P4's `FirebaseEmulatorSwitch` complete (it is small and every Swift package tests with it).
2. Approval 0 (Java 21), then P1 and P2 (independent of Swift) → their gates and approvals.
3. P7 (tree API), P5 (kit, cache, registry), then P6 and P8 in parallel.
4. P3 (VM and service), P4 (platform).
5. P9 (sheets), then P10 (integration) last.

### M3. Reconciliation checklist (lead, after all packages land)

- Field names, doc ids and token values identical across the rules (P1), the codec (P3) and the functions (P2).
- `GardenMoment` (Swift) and `wateringMoment` (JS) agree on the K3/G8 boundary cases.
- Push types and payload keys equal `GardenNotification`; `JourneyFocus` parses every one.
- Every Journey sheet goes through the single `gardenSheet` route and the one-at-a-time rule.
- One filled control per screen in every hero state (resolver table B2), including `loading` and each `unavailable` reason with and without a start date: no disabled hero CTA anywhere.
- Proposal ids, `seed_<uid>_<1–3>`, and the version check agree across the rules (P1), the codec and transactions (P3) and the functions (P2).
- No string in a canvas; every garden string traceable to this spec and built with `String(localized:comment:)` (no concatenated sentences); titles shown through `displayTitle`.
- No nonisolated code calls a `TreeGrowthStage`/`TreeSeason` member; the tree painter is main-actor.
- Zero warnings in Debug **and Release** (`xcodebuild -scheme Coupley -configuration Release -sdk iphonesimulator build`): previews that need the view model are guarded, and the lab, `InMemoryGardenService` and `FirebaseEmulatorSwitch` are absent from Release.
- The privacy page, FAQ and manifest match D6: before Gate 3 the manifest declares Other User Content only; the Gate 3 change adds Precise and Coarse Location with `GardenFeature.isEnabled = true` (the checklist in its doc comment). The approvals in L2 are requested in order, starting with #0.

---

## Appendix: numbers and names at a glance

| Thing | Value |
|---|---|
| Trees | 8 at most: `tree_our`, `tree_p1` … `tree_p7` |
| Open seeds | 3 per person (rules: only the ids `seed_<uid>_1…3`) |
| Seed title / seed note / watering note | 40 / 140 / 100 graphemes (rules: 160 / 560 / 400) |
| One watering per person | every 12 h (rules: after 11 h 50 min) |
| Fresh / ready / thirsty / resting | < 48 h / 48–72 h / 72 h–7 d / ≥ 7 d |
| Dew / wet soil | 6 h / 12 h |
| Watered together / water back | the two partners within 24 h / partner < 24 h ago, me not since |
| The rain returns | ≥ 7 d since the previous watering |
| Note in the hero / Home row | 48 h / 24 h |
| Rainbow, resting cans, "Change it back" | 24 h |
| Reminders | `tt.garden.ready` first 19:00 ≥ +48 h; `tt.garden.rest` first 19:00 ≥ +7 d |
| Garden pushes | ≤ 6 per recipient per UTC day; passive 22:00–06:59 recipient time; only to a garden token device |
| Exact / area place | 4 dp (≈ 11 m) / 2 dp (≈ 1.1 km); area is the default for addresses and pins |
| Band height | 208 / 176 (viewport < 700) / 168 (accessibility sizes) |
| Tree frame | square of 0.86 H (City Lights 0.80 H), ground on the knoll apex |
| Frame budget | ≤ 3.5 ms idle, ≤ 5 ms watering, 30 fps (60 while an effect plays), paused off screen |
| Consent transaction timeout | 10 s; confirmed writes 2.5 s |
| Proposal ids | `seed_our`, `seed_<uid>_<1–3>`, `change_<slot>`, `rest_<slot>`, `startdate` |
| Proposal version | `GardenProposalVersion(rev, at in ms)`, compared by every carry-out |
| Backdrop cache | memory 3 pages × 2 variants (≈ 19–22 MB); disk ≤ 48 MB; ≤ 1 render per frame |
| Emulator switch | DEBUG `-useFirestoreEmulator` (Auth 9099, Firestore 8080, project `demo-coupley-rules`) |
| Push types | `garden_watered`, `garden_proposal`, `garden_agreed` |
| Reminder types | `gardenReady`, `gardenRest` |
| Capability | `users/{uid}.capabilities.garden = 1`; push gate `gardenPushToken == fcmToken` |
| Server-only | `gardenPushClaims`, `gardenPushDaily`, `pushDryRun` (emulator) |
| Functions | `onTimeTreeMetaWritten`, `onCouplePurged`, `cleanupOldData` (updated) |
