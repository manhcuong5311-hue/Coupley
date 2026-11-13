<!--
Sinh ra từ một audit 11 agent trên cây làm việc hiện tại (13/11/2026).
Mỗi phát hiện đã qua một agent phản biện riêng; thứ bị bác bỏ nằm ở mục D kèm lý do.
Số liệu trong đây là số đếm thật trên code, không phải ước lượng.
-->

# Coupley — lỗi còn tồn & việc phải làm trước khi thêm ngôn ngữ

> **Tóm tắt:** 59 phát hiện đã xác minh (16 blocker).
> **16 việc** đắt hơn hẳn nếu làm sau khi tách chuỗi — trong đó **2 việc đang hỏng dữ liệu ngay bây giờ**.
> **~20 lỗi** không liên quan ngôn ngữ, 3 trong số đó khiến nguyên một tính năng âm thầm không chạy.
>
> Mục A = phải làm trước khi thêm ngôn ngữ · Mục B = lỗi thật, độc lập ngôn ngữ
> Mục C = kế hoạch localize kèm khối lượng thật · Mục D = cố ý không làm, kèm lý do

---

# Coupley — what to fix, and what the language deadline actually is

I re-verified every claim against the current working tree. Numbers below are ones I measured myself; where an earlier audit's figure was wrong I give the corrected one. Everything the verifiers rejected is in section D with the reason.

**The headline:** your instinct to ask before adding languages was right. There are **16 things that get dramatically more expensive after you extract strings**, and two of them are already corrupting data today regardless of language. There are also ~20 real bugs unrelated to language, three of which mean entire features silently do nothing.

**Confirmed starting state:** zero localization infrastructure. No `.lproj`, no `.xcstrings`, `knownRegions = (en, Base)` (project.pbxproj:218-221), and **0 uses** of `NSLocalizedString` / `String(localized:)` / `LocalizedStringKey` / `LocalizedStringResource` anywhere in the tree. 2 native targets (not 8 — that earlier figure was wrong): `Coupley` and `CoupleyWidgetExtension`.

---

## A. MUST FIX BEFORE ADDING LANGUAGES

Grouped by fix. The deadline argument is the same shape every time: **after extraction, each of these becomes a key-renaming migration across the catalog plus every translation already paid for, instead of a local code change.**

### A1. Firestore day keys are locale-sensitive — this is corrupting data *now* ⚠️
**Not a language problem. A live data bug.** `DateFormatter()` inherits `Locale.current`, so `dateFormat = "yyyy-MM-dd"` produces `"2568-11-13"` on a Thai-region device, `"0007-11-13"` under the Japanese calendar, `"١٤٤٧-٠٥-٢٢"` on ar_SA.

`SyncScore.date` is both a **document ID** and the range key for `whereField("date", isGreaterThanOrEqualTo:)`. Two partners in different regions write keys neither can read back; the query returns zero rows silently.

Five sites, all verified:
- `Coupley/Features/CoupleStats/Services/SyncService.swift:69` (write), `:88` (query cutoff), `:155` (mock)
- `Coupley/Features/CoupleStats/ViewModels/CoupleStatsViewModel.swift:105` (todayString)
- `Coupley/Features/CoupleStats/Views/CoupleStatsView.swift:436` (parse)

The parser is the nastiest: it does **not** return nil under th_TH — it parses 2025 as a Buddhist year and yields 1482-11-12, so `isDateInToday` is false and the chart labels a weekday from the 15th century. Looks plausible, is wrong.

**Fix (one shared formatter, five call sites):**
```swift
enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
```
Both `.locale` **and** `.calendar` are required — pinning locale alone leaves `f.calendar` on the device calendar. Leave `outputFormatter` at `CoupleStatsView.swift:443` (`"EEE"`) alone; a single-field weekday pattern with the device locale is correct.

**Same edit, free:** `CoupleStatsView.swift:437` returns a hardcoded `"Today"` from a `-> String` function, so it reaches `Text` through the verbatim overload. Make `dayLabel` return `LocalizedStringResource` while you're in there.

**Why the deadline is real:** this one isn't about the catalog — it's that every day you ship, more unmatchable keys land in Firestore. Fix it first, independent of everything else.
**Effort: 30 minutes**, plus a decision on existing non-Gregorian keys (I'd accept the loss and note it — you have 10-20 users, almost certainly all vi_VN/en).

### A2. Quiz answers are stored and compared as display strings 🔴 *the expensive one*
The option **text is the identity**. `selected: Set<String>` holds rendered option text and is written verbatim to Firestore (`QuizAnswerSheet.swift:363 options: Array(selected)`). Four systems key off it — all verified:

1. `optionHints: [String: String]` is keyed by the option text (`ChatQuizBank.swift:16`), looked up at `QuizAnswerSheet.swift:233`/`:237`, `ChatQuiz+Insight.swift:30`, `QuestionOfTheDayViewModel.swift:105`. Translate an option → every lookup returns nil → the insight paragraph (the feature's whole payoff) silently vanishes. **65 templates carry optionHints.**
2. `QuizOrchestrator.swift:121-122` does `aSet.intersection(bSet)`. A Vietnamese user and an English user never intersect → `isMatch` permanently false → every quiz posts "You see X a little differently".
3. `CoupleChatModels.swift:174 Set(guess) == Set(actual)` → the guess game always scores wrong.
4. `CoupleInsightAggregator.swift:105-111` unions these into `sharedTraits`/`differences` → one user switching language **permanently corrupts the couple profile**.

**Fix:** add `optionIds: [String]` to `ChatQuizTemplate` parallel to `options` (e.g. `["words","time","service","touch","gifts"]`), re-key `optionHints` by id, add `var optionIds: [String]?` to `ChatQuizAnswer`/`ChatQuiz`, write ids at `QuizAnswerSheet.swift:363`, switch all four consumers to ids, keep `options` display-only. Backfill: when `optionIds == nil`, match against the English `options` of the template named by `questionId`.

**Why the deadline is real:** doing this after extraction means touching ~360 hint keys in the catalog *plus* every answer document already in Firestore. Doing it now is one model change and six call sites.
**Effort: 1-2 days.** This is the single biggest A item and the one I'd start on after A1.

### A3. Quiz result summaries are English prose written into Firestore
`QuizOrchestrator.swift:133` builds `"You both value \(shared.lowercased()) \(quiz.topic.emoji)"` and `:138` the mismatch sentence. `CoupleChatService.swift:275`/`:285` persist it into **two** documents (the quiz and a `resultCard` chat message). Read back at `QuizHubView.swift:576`/`:651`, `QuestionOfTheDayCard.swift:247`.

After a second language: the stored string is whoever answered second. A Vietnamese user's summary is read by their English partner. Every result already in the database stays English forever — a catalog cannot reach it, because the text is *data*, not source.

**Fix:** replace `ChatQuizResult.summary: String` with `match: Bool` + `sharedOptionIds: [String]`, render the sentence on the reading device. Keep `summary` decodable as a fallback for existing rows. Same for `ChatMessage.resultCard`.

**Same file, do together with A2** — both touch the quiz data model.
**Effort: half a day** (grouped with A2, call it 2 days for A2+A3 together).

### A4. No AI request carries the user's locale — every reply comes back English
All six request bodies encode context and no language field. Verified: **zero** `Locale` references anywhere in `Coupley/Features/AICoach/` or `Coupley/Features/AISuggestion/`. App-wide there are only 4 uses of `Locale.current`, all in `Core/Currency/`.

- `AICoachService.swift:263` `ReplyRequestBody`, `:272` `GuidedRequestBody`, `:286` `RewriteRequestBody`, `:296` `HealthRequestBody`, `:309` `RecoveryRequestBody`
- `RemoteAISuggestionService.swift:26` `SuggestionRequestBody`
- `functions/index.js` builds prompts at 417-499 and 638 with no output-language instruction

Translate the UI and the entire AI surface — coach chat, guided flows, three rewrites, health summary, recovery plan, mood suggestions — stays English. The headline feature reads as *broken*, not untranslated.

**Fix:** add `let locale: String` (`Locale.preferredLanguages.first ?? "en"`) to the six structs, and one line per system prompt server-side: `Respond entirely in the language with BCP-47 tag ${locale}.` Keep sending enums as `rawValue` — that separation is already correct and is what makes any of this possible.

**Why the deadline is real:** do this *before* `MockAICoachService`'s 169 strings get extracted, or you pay to translate a fallback that a locale-aware backend would rarely hit.
**Effort: 1 hour client + 1 line server.** Best ratio of value to effort in section A.

### A5. ~276 user-facing literals live in `-> String` model properties, invisible to the extractor 🔴 *the big one*
Xcode's extractor only reads `Text` / `LocalizedStringKey` / `NSLocalizedString` / `String(localized:)` positions. It does **not** see `return "Just planted. Tender beginnings."` inside `var caption: String`. Add a catalog, run extraction, and you get something that **looks complete** and an app that is **half English**.

I verified 54 display-role `String` properties in `Features/*/Models/` and `Shared/`. Concentrations: `AICoachModels.swift`, `TimeMemory.swift`, `OnboardingProfile.swift`, `StatsModels.swift`, `CrownMilestone.swift`, `PartnerProfile.swift`, `TreeGrowthStage.swift` (e.g. `:64-72 var caption: String`), `CoupleChatModels.swift`.

**Three sub-classes the original sweep missed — include them in the same pass:**

(a) **All user-facing error copy.** 13 `errorDescription` conformances, every one returning bare literals: `AuthService.swift:38` (3 literals), `PairingService.swift:33` (3), `AccountDeletionService.swift:64` (9), plus `FirebaseIDTokenProvider.swift:20`, `CoupleService.swift:73`, `FirestoreMoodService.swift:145`, `AICoachService.swift:58`, `RemoteAISuggestionService.swift:72`, three storage services, `CoupleChatService.swift:345`, `ConnectionService.swift:41`. Plus 7 `errorMessage = "literal"` assignments and 3 `loadState = .error("…")`. **These are what a user sees when sign-in, pairing, photo upload or account deletion fails.**

(b) **Enum labels manufactured from the English rawValue — there is no literal to extract at all.** `MoodEntry.swift:30` `Mood.label { rawValue.capitalized }` and `:52` `EnergyLevel.label { rawValue.capitalized }` (both verified), plus `PartnerProfile.swift:20`, `AISuggestion.swift:32`. Rendered at `MoodCheckinView.swift:250`/`:337`, `MonthlyMoodInsightView.swift:349`/`:427`. **The mood names on your most-used screen.** Changing the return type does nothing here — each needs an explicit `switch self` added *first*. `.capitalized` is also locale-unsafe (Turkish dotless i) and title-cases every word, wrong for vi sentence case. Storage is fine — `MoodEntry` persists the Codable `rawValue`, not the label — so this is display-only and safe.

(c) **`CoupleChallenge.statusLine` has four branches, not one.** `:216 "Completed 🎉"`, `:218 "Starts \(relative)"`, `:222 "Day \(n) of \(target)"`, `:223 "Week \(n) of \(target)"`. Fix the whole property in one move, not just the `Starts` line.

**Fix:** change the return type to `LocalizedStringResource` (iOS 16+), which **is** an extraction site. Most call sites compile unchanged, because `Text` has a `LocalizedStringResource` initializer.
**Effort: 2-3 days.** File-by-file. Start with the eight heaviest models (roughly half the literals).

### A6. `Text(String)` is the verbatim overload — and your own design system funnels literals into it
The `LocalizedStringKey` overload is `@_disfavoredOverload`, so a `String` variable always picks the verbatim path. I measured **314** `Text(<identifier>)` sites. Many are correctly user content (`message.text`, `memory.title`, `profile.displayName`) or emoji — leave those. But ~96 pass app copy, and worse, **the tier components declare their parameters as `String`:**

- `DesignSystem.swift:117` `Eyebrow { let text: String }` → `:121 Text(text)`
- `DesignSystem.swift:143` `PrimaryButton { let title: String }` → `:161 Text(title)`
- `DesignSystem.swift:193` `GhostButton { let title: String }`
- `DesignSystem.swift:449` `BrandCTA { let title: String }` — **zero call sites, currently unused**, so changing it is free

Plus, same pattern, **unreported until now**: `CoupleDashboardView.swift:785` `activityCard(title: String)` → `:803`, `CoupleDashboardView.swift:620` `statsLine(label:)` (its three labels "streak"/"sync"/"check-ins"), `TogetherTodayHero.swift:217` `statTile(title: String)`, `AICoachHomeView.swift:355` `toolRow(title:subtitle:)`, `AICoachComponents.swift:69` `CoachSectionTitle`.

Call sites look extractable to both Xcode and to you grepping for a quoted string — `GhostButton(title: "Back")`, `PrimaryButton(title: "Start Quiz")` — yet never reach the catalog. **Every "Back" and "Save changes" button in the app stays English.**

**Fix:** change those 8 parameters to `LocalizedStringKey`. Literals coerce, so **no call-site edits**. Then sweep the ~96 app-copy `Text(variable)` sites — where the variable comes from a model display property, A5 fixes it for free.

**Why the deadline is real:** this is one mechanical sweep now and a cross-file migration after extraction. It is the cheapest high-leverage item in A.
**Effort: half a day to 1 day.**

### A7. Notification copy can never be localized — and freezes at *schedule* time
`UNMutableNotificationContent.title`/`.body` are `String`, so every assignment is invisible to the catalog. Verified 12 direct assignments and **zero** uses of `localizedUserNotificationString`:
`TogetherNotificationScheduler.swift:101,102,145,146,179,180` · `TimeTreeNotificationScheduler.swift:55,56,94` · `AnniversaryNotificationScheduler.swift:74` (+ the `notificationBody` switch at ~141-145) · `MicroActionReminderScheduler.swift:33` · `NotificationService.swift:276`

**The part no catalog fixes:** these are scheduled ahead and fire while the app isn't running. `TimeTreeNotificationScheduler.swift:82-99` registers `UNCalendarNotificationTrigger`s for milestones **years** in the future. A user who switches to Vietnamese keeps getting English notifications until every pending request is rescheduled.

**Fix:** `content.title = NSString.localizedUserNotificationString(forKey: "notif.capsule_ready.title", arguments: nil)` — that API stores the *key* and resolves at delivery. Interpolated bodies pass arguments. Also `TogetherNotificationScheduler.swift:146` hardcodes `"\(pct)%"` — use `pct.formatted(.percent)`.

**Plus the remote half** (missed by every dimension): `functions/index.js:89-116` holds 12 hardcoded `{title, body}` pairs, sent at `:846`. Nothing in the client ever writes a locale to the user document, so after full client localization **every server push still arrives in English**. Fix: write `locale: Locale.preferredLanguages.first` onto the user doc where the FCM token is registered, then key the pools by language server-side.
**Effort: 3-4 hours local + 2 hours remote plumbing.**

### A8. Plural ternaries — 5 of 14 produce a key with the noun stripped out
Honest correction to the earlier audits: **only 5 are catalog-invisible.** A ternary of two literals *does* resolve to `LocalizedStringKey` and extracts as two keys.

**The 5 genuinely broken** (noun interpolated as `%@`, so the key is `"%lld %@"` — a translator sees a key with no noun in it):
`TimeTreeView.swift:282` `Text("\(count) \(count == 1 ? "memory" : "memories")")` · `AICoachHomeView.swift:192` · `MonthlyMoodInsightView.swift:145` · `TimeTreeHeader.swift:165` · `CoupleProfileView.swift:181`

**The other 9** are translatable but carry a two-form plural model — fine for Vietnamese (one form), wrong for Polish/Russian (3-4 forms): `CoupleStatsView.swift:123`, `TimeTreeHeader.swift:90`/`:126`, `MemoryCard.swift:216`, `MemoryDetailSheet.swift:197`, plus plain-`String` returns at `CrownMilestone.swift:46`, `WidgetCountdownEngine.swift:237/239/241`.

Also `TimeTreeView.swift:338-342 mastheadStandfirst` hand-branches `count == 0 / == 1 / else` into three English sentences and needs **two** independent plural arguments in one key.

**Fix:** one String Catalog plural entry per phrase, whole sentence as the key, count as the only interpolation. `Text("^[\(count) memory](inflect: true)")` or an explicit plural variation. Vietnamese then supplies only `other`.

**Two corrections to the brief, both verified:** the `"memor" + (count == 1 ? "y" : "ies")` suffix-splice is **gone** (it's now the line-282 form), and `StatsPreviewCard.swift:58` is a plain `Text("day streak")` with no ternary. Both already fixed.
**Effort: half a day.**

### A9. Four hardcoded display `dateFormat` patterns
I verified 27 `DateFormatter`/`RelativeDateTimeFormatter` instances and **zero** set `.locale` (the brief's "exactly one" was counting `CurrencyFormatting.swift:29`, which is a `NumberFormatter`). That's mostly *fine* — a nil locale means `Locale.current`, which is what you want for display. The problem is the 4 hardcoded patterns, which override the locale's conventions even with a correct locale:

| Site | Pattern | Breaks as |
|---|---|---|
| `NotificationSettingsView.swift:318` | `"h:00 a"` | de_DE "3:00 PM" (English markers in German), vi_VN "3:00 CH" — **this is the reminder-hour picker**, so the user misreads when nudges fire |
| `MonthlyMoodInsightView.swift:563` | `"LLLL yyyy"` | vi "Tháng 11 2025" (needs "tháng 11 **năm** 2025"), ja "11月 2025" (needs "2025年11月") |
| `MonthlyMoodInsightView.swift:569` | `"MMM d · h:mm a"` | vi inverts day/month; carries both faults |
| `CoupleDashboardView.swift:1262` | `"EEEEE"` | de "M D M D F S S" — four ambiguous labels; vi "T2…CN" is 2-3 chars, not the 1 the cell was sized for |

**Fix:** use templates, which reorder and re-mark per locale. **You already have the reference implementation** at `CoupleDashboardView.swift:322` (`setLocalizedDateFormatFromTemplate("EEEEdMMMM")`). → `"jmm"` (`j` picks 12/24-hour per locale), `"yMMMM"`, `"MMMdjmm"`, and `"EEE"` for the weekday strip. `NotificationSettingsView.swift:318` also allocates a formatter per row per render (24 rows) — hoist to a `static let`.
**Effort: 30 minutes.** Leave the 5 `yyyy-MM-dd` storage formatters alone — they need the *opposite* fix (A1). `DebugMenuView.swift:321` is debug-only; leave it.

### A10. English prose assembled at runtime, in word orders no translator can change
Sentences built by interpolating a fragment into an English frame, inside plain `String`s that never pass through a catalog:

- `CoupleDashboardView.swift:1095` `"Last seen " + formatter.localizedString(...)` → a Vietnamese user sees **"Last seen 5 phút trước"**
- `CoupleChallenge.swift:218` `"Starts \(relative)"`
- `Shared/WidgetRelativeTime.swift:26` returns `"Just now"` then correctly defers to `RelativeDateTimeFormatter` — one English literal mixed with one localized string
- `TogetherCoachEngine.swift:188` `"You're on a \(n)-day \(category.label.lowercased()) streak"` — vi needs "chuỗi {category} {n} ngày", which **reverses the order**
- `MockAICoachService.swift:67,68,90,100,101,313,447,455` splice `label.lowercased()` mid-paragraph
- `WidgetCountdownEngine.swift:209-216`, `:264`

**Also drop every `.lowercased()` in these frames.** Once the label is translated, lowercasing a German noun is a grammar error, and Turkish "I" maps to "i" instead of "ı". Sites: `TogetherCoachEngine.swift:188`/`:261`, `SuggestionView.swift:100`, the 8 Mock sites. (Symmetric uppercase: `PartnerAndMeProfileView.swift:115`, `QuizHubView.swift:428`, `AICoachRecoveryPlanView.swift:182`.)

All four `RelativeDateTimeFormatter`s localize correctly on their own — the defect is the English words concatenated **around** them.

**Fix:** positional format strings so the translator controls order: `String(localized: "Last seen %@")`, `String(localized: "You're on a %1$lld-day %2$@ streak")`.
**Effort: half a day to 1 day.**

### A11. The widget extension has its own English copy and no catalog
`knownRegions` is project-wide, so localizing the app target still leaves the **home-screen widget** in English — your most visible surface.

- `WidgetCountdownEngine.swift:48-59` bakes 12 milestone titles into `let title: String` ("1 Year Anniversary", "500 Days of Love", …)
- Assembled in English frames at `:209-216` and `:264`, hand-plurals at `:237-241`
- `CoupleyHomeWidget.swift:26-27` sets `configurationDisplayName`/`description` — the **system widget gallery** entry

**Fix:** it's **one target membership**, not seven (there are 2 targets). Put `Localizable.xcstrings` in a shared location, add it to both targets, pass an explicit bundle from `Shared/` code. Replace `Milestone.title: String` with a stable `titleKey` + `LocalizedStringResource` at render. `CoupleyHomeWidget.swift:26-27` already take `LocalizedStringResource`, so they localize for free once the catalog is in the target.
**Effort: 3-4 hours.**

### A12. Three `Text("…" + "…")` sites that will pass any grep *and* the extractor
`"a " + "b"` is a `String` **expression**, not a literal, so `Text` takes the verbatim overload. All three verified:
- `DeleteAccountView.swift:224` — the billing warning: *"Deleting your account will not cancel your subscription…"*
- `DeleteAccountView.swift:508` — the post-deletion confirmation
- `AccountDeletionService.swift:75` — same shape in a plain `String` return

These read as `Text("…` and will survive every audit, yet stay English forever. **The first one tells a user their subscription keeps charging** — arguably the two highest-stakes strings in the app for a non-English user.

**Fix:** collapse into one literal (a `"""` multi-line literal keeps it readable). For the service, `String(localized:)` with `provider` as an argument. Then keep `grep -rn '" *+ *$'` as a standing lint — it currently returns exactly these three lines.
**Effort: 10 minutes.** Do this today.

### A13. A hardcoded `\n` baked into a masthead key
`MoodCheckinView.swift:120` `Text("How are you\nfeeling today?")`. Because the initializer takes `LocalizedStringKey`, **the literal newline becomes part of the extracted key**. A translator gets an English line break welded into the middle of a sentence whose grammar divides differently. Once that key is in the catalog, removing the `\n` changes the key and invalidates every translation of it.

It also has **neither** `.lineLimit` **nor** `.minimumScaleFactor` — only `.lineSpacing(2)` — so there's no ceiling at all. Its sibling at `CoupleDashboardView.swift:230-234` carries both.

**Fix:** drop the newline, add `.lineLimit(2)` and `.minimumScaleFactor(0.72)` to match Home. Keep `.lineSpacing(2)`.
**Effort: 5 minutes.** Pure deadline item — trivial now, annoying later.

### A14. Currency names hardcoded in English, and a search that can't match them
`CurrencyCatalog.swift:35-39` carries ~40 names as literals ("US Dollar", "Vietnamese Dong"). **Foundation already ships every one of these in every locale** — a Vietnamese user should read "Đô la Mỹ".

**Fix:** delete the `name` literals, derive it: `var name: String { Locale.current.localizedString(forCurrencyCode: code) ?? code }`. Removes ~40 rows from the catalog before they're ever added.

**Paired, and required by that fix:** `CurrencyPickerSheet.swift:85-89` matches with `$0.name.lowercased().contains(needle)`. The moment names localize, a user typing "do la" won't match "Đô la Mỹ" — `lowercased()` doesn't fold diacritics. Fix: `localizedStandardContains(trimmed)` on code, name and symbol (case- *and* diacritic-insensitive).

Everything else in currency is correct and should not be touched: `code` is the ISO source of truth on documents, `CurrencyFormatting.swift:29` sets `locale = Locale.current`, and the per-currency `quickBaseUnit` chips are already region-aware.
**Effort: 30 minutes.**

### A15. `InfoPlist.xcstrings` — two system-presented strings a `Localizable.xcstrings` can never reach
- `NSUserTrackingUsageDescription` (`Coupley-Info.plist`) — the **ATT consent prompt**, the first sentence a new user reads, and it's your ad revenue
- `INFOPLIST_KEY_CFBundleDisplayName` (project.pbxproj:293/325 CoupleyWidget, :479/515 CoupleyAI)

Info.plist values need their own `InfoPlist.xcstrings` **per target**. Without it you ship an English permission dialog inside a translated app.
**Effort: 30 minutes.** Easy to forget entirely, which is why it's here.

### A16. DailyPhoto stores rendered prose instead of an index
`DailyPhoto.swift:18 let prompt: String` with no index field; `DailyPhotoService.swift:85-92` resolves the prompt on whichever device opens the app first that day and writes **the sentence**. A Vietnamese user whose partner materialised the day gets an English prompt.

**Correction to the earlier audit — this is not data loss.** `DailyPhoto.swift:73-83` derives the prompt by FNV-1a over `coupleId` plus `sequence % 24`, and the doc id is `potd-{sequence}`, so the index is **recomputable** from data already in the schema. It's a read-side fix plus an optional `promptIndex` field, not a migration.

**Fix:** add `let promptIndex: Int` (decode as optional so existing docs fall back to the stored `prompt`), render `DailyPhotoPrompts.all[photo.promptIndex]` locally. Same pattern for QotD: prefer `ChatQuizBank.byId(quiz.questionId)` over the stored `question`/`subtitle`/`options` — `QuestionOfTheDayService.swift:135-137` denormalizes them **but does keep `questionId`**, so it's re-resolvable.
**Effort: 1 hour.**

---

### Realistic total for A
**7-9 focused working days; budget two calendar weeks** with testing, for a solo dev.

The distribution is lopsided: **A2+A3 (quiz data model, ~2 days) and A5 (model display properties, 2-3 days) are two thirds of it.** Everything else adds up to about 2 days.

**Suggested order:**
1. **Today, ~1 hour:** A1 (day keys — stop corrupting data), A12 (three concatenations), A13 (masthead `\n`), A4 (AI locale)
2. **This week, ~2 days:** A6 (`LocalizedStringKey` sweep), A9 (date patterns), A14 (currency), A15 (InfoPlist), A8 (plurals)
3. **Then, ~5 days:** A2+A3 (quiz model), A5 (model properties), A7 (notifications), A10 (runtime prose), A11 (widget), A16 (DailyPhoto)
4. **Only then** create the catalog and extract.

---

## B. REAL BUGS, INDEPENDENT OF LANGUAGE

Ranked by user impact.

### B1. Every stats number is permanently 0 🔴
`updateStreak`, `saveSyncScore` and `calculateDailyScore` have **zero call sites.** I grepped all Swift plus `functions/index.js`: they appear only as protocol declarations and implementations in `StreakService.swift` (:15/:50/:142) and `SyncService.swift` (:14/:16/:63/:105/:147/:176). Nothing ever calls them. No Cloud Function writes these fields either.

The only writer anywhere is `PairingService.swift:126-127`, seeding `currentStreak: 0, longestStreak: 0` at pair time — so `fetchStreak`'s guard passes and returns `StreakData(0,0,nil)` **forever**.

A couple checks in together every day for a week. The Home stat tile, `StatsPreviewCard` and the Our Stats sheet all still read "0 day streak". Longest is hidden (guarded `> 0`), the weekly chart is empty, `syncLevel` is always `.outOfSync`, `trend` always `.stable`. **Nothing the user does can ever move these numbers.**

**Fix:** in `CoupleStatsViewModel.loadStats()`, call `updateStreak` before the fetches, and compute+save today's score when both partners' moods exist. **Before wiring it up**, wrap `StreakService.updateStreak` in `db.runTransaction` — as written it's a non-transactional read-modify-write on `/couples/{id}.currentStreak`, and both partners' devices run it concurrently, so it will double-count. The pattern already exists at `PremiumService.swift:124` and `CoupleChatService.swift:181`.

*(This also subsumes the identical `else if`/`else` branches at `StreakService.swift:84-90` — you'll be rewriting that method anyway.)*
**Effort: hours.** Highest-impact bug in the app: an entire feature that has never worked.

### B2. The AI suggestion sheet runs on the mock while real quota is spent 🔴
`SuggestionView.swift:20` declares `suggestionService: AISuggestionService = MockAISuggestionService()`. The **only** production call site is `CoupleDashboardView.swift:110`:
```swift
SuggestionView(moodContext: context, partnerProfile: .samplePartner)
```
No service argument → the mock default is used. And `.samplePartner` is a hardcoded fixture, so it isn't even about the real partner.

The button says "5 left today", `premiumStore.recordUsage(for: .aiMoodSuggestions)` decrements it, and the sheet shows **canned mock copy**. The daily allowance is consumed to display fixtures. `HybridAISuggestionService` (the real path) is constructed at `ContentView.swift:47` but handed only to `CoupleViewModel`, which never surfaces its result.

**Fix:** pass the real service at `CoupleDashboardView.swift:110` and **delete the `= MockAISuggestionService()` default** so the next call site can't silently fall back.
**Effort: 10 minutes.** Best effort-to-impact ratio in section B.

### B3. Three non-awaited `setData` calls — writes can vanish silently
`try` with no `await` resolves to the **synchronous** Codable overload, so the call returns as soon as the write is queued in the local cache. If the server later rejects it (rules change, quota, a stale `coupleId`), Firestore silently drops the document.

All three verified:
- `CoupleChatService.swift:329` `try ref.setData(from: msg)` — used by `sendText`, `postSystemMessage` **and** `sendPhoto`. `sendDraft` has already cleared `draftText` and its catch block never ran, so **the message is unrecoverable**, and the "Sending… → Sent" indicator just never advances.
- `FirestoreMoodService.swift:125` — this makes the **entire `MoodQueueStore` retry mechanism dead** for the network failures it was built for.
- `SyncService.swift:109`

**Fix:** add the missing `await` at all three. The async overloads already exist; only then do the surrounding catch/enqueue blocks mean anything.
**Effort: 15 minutes.** Do it with B2.

### B4. Silent failures: two view models write errors that no view reads
I verified `grep -rn errorMessage` across the Views of every feature. **Only two surfaces render an error anywhere in the app:** `TimeTreeView.swift:66` and `DailyPhotoCard.swift:99`. Everything else is silent.

- **`TogetherViewModel.swift:37`** — 14 references, written at 13 sites. Zero reads in `Features/Together/Views/`. Every goal/challenge/dream create/update/delete and all three listener error callbacks fail invisibly. A Together tab that can't read its own data renders as simply **empty**.
- **`ChatViewModel.swift:29`** — 10 references, zero reads in `Features/CoupleChat/Views/`. On a failed send, `:239` puts the text back in the composer and sets `errorMessage` — nothing displays it, so the user's message **reappears in the box for no stated reason**. A failed photo upload is worse: the spinner stops and nothing happens.
- Same unfixed in `QuestionOfTheDayViewModel.swift:24`, `AnniversaryViewModel.swift:18`, `CoupleProfileViewModel.swift:17`.

**The fix is bigger than one error strip — this is the part the earlier audits got wrong.** Most Together mutations start from **modal sheets** presented over the tab (the three editors' save paths, `ChallengeDetailSheet.swift:159`, the goal-contribute path). A strip rendered behind a `.large`-detent sheet **is not on screen.**

And the editors actively lie:
- `GoalEditorSheet.swift:550-554` `if !success && !canExceed { showLimitAlert = true } else { dismiss() }` — `createGoal` returns false for **both** a cap rejection and a Firestore throw (`TogetherViewModel.swift:188-194`). So a **premium** user whose write fails hits the `else` and **the sheet dismisses as if the goal were created**; a free user under the cap whose write fails is told "limit reached", the wrong reason.
- `ChallengeEditorSheet.swift:385-389` — byte-for-byte the same bug.
- `DreamEditorSheet.swift:470` `if success { dismiss() }` — failed write leaves the sheet open with no message.
- `GoalEditorSheet.swift:564-565` and `DreamEditorSheet.swift:479-480` — `updateGoal`/`updateDream` return `Void`, so **a failed edit always closes as if saved**.

**Fix:** (1) have the three create functions distinguish cap-rejection from write-failure (return an enum, or check the cap *before* the write). (2) Surface the error **inside each sheet** and suppress the dismiss on failure. (3) Add the `TimeTreeView.swift:66` strip to the Together and Chat bodies for the non-modal paths, with a `clearError()` since the Chat property is `private(set)`. The alert pattern at `AICoachChatView.swift:66-71` is also already in-repo.
**Effort: 1 day** for the whole family.

### B5. Anniversary cover upload: full-resolution encode, then the error is swallowed
Two bugs that combine into one user-visible failure, and the second masks the first.

**The trigger (missed by the audits):** `AnniversaryStorageService.swift:25` still does `image.jpegData(compressionQuality: 0.80)` on the picker's **full-resolution** image. Its TimeTree sibling was already fixed in this very tree — `TimeTreeStorageService.swift:33` now calls `ChatPhotoStorageService.downscaledJPEG(image)`, with a comment explaining that a phone shot "at several MB that way … can exceed the 10 MB ceiling in storage.rules and be rejected outright." The Anniversary path was never updated, so **normal-sized photos are rejected server-side**.

**The swallow:** `AnniversaryViewModel.swift:109` and `:151` use `try? await storageService.uploadCover(...)`. `imageURL` stays nil, the anniversary writes without its image, and the sheet dismisses **looking like a success**. This is the exact bug fixed at `TimeTreeViewModel.swift:200-205`, whose comment reads: *"Was `try?`. A failed upload left photoURL nil and the memory saved silently without its picture."*

**Editing is worse:** the failure leaves `updated.imageURL` nil, so the write **silently removes a cover that was already there**.

**Fix:** `guard let data = ChatPhotoStorageService.downscaledJPEG(image)` at `AnniversaryStorageService.swift:25`; replace both `try?` with do/catch setting `errorMessage`; in the update path preserve `anniversary.imageURL` on failure rather than nil. Then render `errorMessage` (part of B4).
**Effort: 30 minutes.**

### B6. An unpaired user's mood is reported as "will sync when online" and queued forever
A solo (authenticated, unpaired) user submits a mood. `writeToFirestore` throws `.notPaired` (`FirestoreMoodService.swift:117-119`), `save`'s **blanket** catch (`:35-45`) enqueues it and rethrows `.queuedForRetry`, whose `isQueued` is true — so the user is told **"Saved locally — will sync when online."**

Connectivity is not the problem and more connectivity will never fix it: every `flushQueue` retry hits the same guard and `break`s on the first entry (`:99-111`). `todayCheckinCount` is still incremented, so **the user burns their 3/day allowance on writes that cannot land.** `MoodWriteError.notPaired` and its correct copy ("Connect a partner before saving moods.") are unreachable. Nothing reads `pendingCount`, so the stuck queue is invisible.

**Fix:** rethrow non-retryable errors without queueing — `catch let e as MoodWriteError where !e.isQueued { throw e }` before the existing catch, or guard at the top of `save`. Add a `.notPaired` branch in `MoodViewModel` that shows the real message and does **not** increment the counter.
**Effort: 30 minutes.**

### B7. The whole view tree re-renders every 60 seconds, and the widget burns its refresh budget
`SessionStore.swift:274`/`:281` assign `self.appState = .ready(...)` / `.needsPairing(...)` **unconditionally** — verified, no equality check, unlike `handleSignedOutState` which does guard.

With the app foregrounded, the 60s presence heartbeat (`NotificationViewModel.swift:123-134`) writes `/users/{uid}`; the listener reassigns `appState`; `@Published` republishes **even though the value is unchanged**. `WidgetSyncCoordinator` re-applies and calls `bind` (→ `reloadTimelines`) or, for a solo user, `unbind` — which writes the placeholder snapshot, clears the couple photo and reloads timelines **with no debounce at all** (`WidgetSyncService.swift:104-111`). Each heartbeat produces two republishes (local write + server ack), so **~2 widget reloads a minute.** iOS throttles after a few dozen a day, after which the widget **stops updating entirely** — the opposite of what the sync service is for.

`CoupleDashboardView.swift:46-48` already documents the symptom: *"the partner's 60-second presence heartbeat guarantees those [re-renders]"*.

**Fix:** build `let next: AppState = ...` then `if appState != next { appState = next }`. `AppState` already has a custom `==` at `SessionStore.swift:45`. **One change fixes both the widget budget and the 60-second full-tree re-render** the dashboard comment works around.
**Effort: 15 minutes.** Best effort-to-impact after B2.

### B8. A failed Time Tree photo upload is reported, then wiped before it can be seen
`TimeTreeViewModel.swift:187` clears `errorMessage` with the comment *"Cleared here, not between the upload and the write: a photo failure reported below must survive until the user has seen it."* Line ~204 then sets the upload error. **Line ~228 clears it again** immediately before the Firestore write, which succeeds. The memory saves with no picture and the strip never appears — exactly the failure the comment says was fixed.

Belt and braces: `handleRemoteMemoriesUpdate` (:321) also clears it, and the local write fires that listener immediately, so even without :228 the message is wiped within the same frame.

**Fix:** delete the second `errorMessage = nil` at :228 (:187 already covers the reset), and gate the :321 clear on a `lastErrorWasRemote` flag so a snapshot arriving after a photo failure doesn't swallow it.
**Effort: 15 minutes.**

### B9. Together paywall: the hero promotes a locked challenge and hands free users a working check-in
`TogetherView.swift:372-373` — verified, `viewModel.activeChallenges.max(by:)` scans the **whole** array with no entitlement scoping, while `ActiveChallengesSection` locks everything at `index >= freeLimit`.

A premium partner creates a second challenge → the free partner's older, streak-bearing challenge sits behind `PremiumLockOverlay` in the list, **yet the hero renders a tappable stat tile for it**, and tapping presents `ChallengeDetailSheet`, which offers "Check in for today" at `:161`. I verified `ChallengeDetailSheet` has **zero** entitlement gating — its single `premium` match is a comment on line 7. Paywall bypass via the most prominent object on the tab.

**Fix:** scope the hero's selector to the entitled prefix, **and independently** add the `premiumStore.hasAccess(to: .togetherChallengesUnlimited)` gate inside `ChallengeDetailSheet` before the check-in button, so no future entry point can reopen the hole.
**Effort: 30 minutes.**

### B10. Free-tier locking is positional over arrays whose order changes — **three** instances
`isLocked = !isPremium && index >= freeLimit` indexes arrays fed by `createdAt` **descending** listeners, so **index 0 is the NEWEST item.** All verified:

- `TogetherActiveSection.swift:61` (goals) and `:276` (challenges) — `activeChallenges` is `challenges.filter { !$0.isComplete }` with **no sort** (`TogetherViewModel.swift:371-373`), fed by `.order(by: "createdAt", descending: true)`. **Creating a challenge locks the user's existing one** — the one carrying the streak.
- `activeGoals` (`TogetherViewModel.swift:363`) re-sorts by `progress` **descending**, so which goals are free **flips as progress changes**, locking and unlocking rows under the user.
- **The Dream Board is the third instance, and the earlier fix omitted it.** `TogetherDreamBoardSection.swift:91`/`:103` lock on `absoluteIndex >= freeFullyVisible` over `viewModel.dreams` passed **raw** — the listener array, `createdAt` descending, with **no filter at all**. Unlike goals and challenges there's no `activeDreams`, so **completed dreams also consume the one free slot** and can push the only live dream behind the paywall.

**Fix:** make entitlement a property of the **item**, not its row position. Either sort all three by `createdAt` **ascending** so the oldest are the entitled ones and the set is stable, or (better) persist a `grandfathered: Bool` at create time and test that instead of the index.
**Effort: half a day.** Make sure the fix covers dreams.

### B11. Four uncapped creation entry points — the editor rejects you only after you've filled it in
The three toolbar `Menu` buttons at `TogetherView.swift:228-241` set `presentedSheet = .createGoal/.createChallenge/.createDream` **directly, with no entitlement test** (verified). A free user at the limit taps + → "New challenge", picks a category, a colorway, a cadence, a target and a start date, taps Save — and *only then* gets bounced to the paywall (`ChallengeEditorSheet.swift:369`).

The section's own + button does the right thing (`TogetherActiveSection.swift:96-103` → `onShowPaywall()` immediately). **Two entry points for the same action with opposite behaviour.**

**Plus a fourth, unreported:** `TogetherView.swift:355-360` `handleInsightAction` routes `.createGoal/.createChallenge/.createDream` suggestions straight to `presentedSheet` with no test either. Only reachable while `hasCoach`, so not a live hole today — but the fix must cover it or the inconsistency reopens the moment an entitlement lapses mid-session.

The caps themselves are duplicated in **five** places: `TogetherActiveSection.swift:27` (2) and `:242` (1), `TogetherDreamBoardSection.swift:28` (1), `TogetherViewModel.swift:169` and `:249`.

**Fix:** one source of truth — `enum TogetherFreeLimits { static let goals = 2; static let challenges = 1; static let dreams = 1 }` — plus `createGoalOrPaywall()`-style helpers routing **all seven** entry points (3 menu + 3 insight + the section buttons).
**Effort: hours.**

### B12. Journey is a permanent spinner whenever the listener errors
`TimeTreeView.swift:75` `} else if viewModel.isListening && !viewModel.hasReceivedFirstUpdate {` — **no error term.** `hasReceivedFirstUpdate` only flips on a remote snapshot or a **non-empty** cache (guarded `!items.isEmpty`). If the listener reports an error instead — permission denied, or a brand-new paired couple with zero memories and no network — the branch is true **forever**: "Loading your timeline…" with no retry and no way out, and the error strip stacked **on top of** it rather than replacing it. `timelineLoadingState` is a bare `ProgressView` with no retry control.

**Fix:** add `&& viewModel.errorMessage == nil` to the condition so the strip replaces the spinner, and add a `Button("Try again") { viewModel.stopListening(); viewModel.startListening() }` to `errorStrip(_:)`.
**Effort: minutes.**

### B13. Chat has no empty state — a brand-new couple's first screen claims older history exists
`ChatViewModel.swift:33` initialises `hasMoreOlder = true`. `loadOlder()` (verified at `:192-193`) returns at `guard let oldest = messages.first else { return }` **without ever clearing the flag**, so it stays true forever. `ChatView.swift:266` renders `loadOlderIndicator` on it.

A freshly paired couple opens Chat and the entire screen above the composer is one 11pt line saying **"Pull up to see older messages"** — on a thread that has never had a message. No empty-thread view exists anywhere in the file.

**Fix (three one-liners):** `guard let oldest = messages.first else { hasMoreOlder = false; return }`; `if viewModel.hasMoreOlder && !viewModel.messages.isEmpty {`; and add a real `emptyThreadNote` ("Say the first thing" + a standfirst) instead of the false sentinel.
**Effort: minutes.**

### B14. `needsAttention` has a dead `&&` term, so low energy never counts
`CoupleModels.swift:76-78` — verified:
```swift
var needsAttention: Bool { isLowMood || (isLowMood && isLowEnergy) }
```
Algebraically just `isLowMood`. The second clause **can never change the result**, and the expression's shape shows energy was meant to participate. A partner logging tired/neutral mood with low energy is never flagged: `partnerNeedsAttention` stays false, the "Get Suggestions" button isn't rendered (gated on `entry.needsAttention` at `CoupleDashboardView.swift:954`), no prefetch fires.

**Fix:** decide the rule and write it once — `isLowMood || isLowEnergy`, or `isLowMood || (moodValue == .neutral && isLowEnergy)` if energy should only escalate a borderline mood.
**Effort: minutes** — but it's a product decision, so make it deliberately.

### B15. Two quiz-suggestion bugs that mask each other ⚠️ *fix together or you'll make it worse*
**(a)** `ChatViewModel.swift:83-88` `start()` attaches the quiz listener and **immediately** launches `maybeSuggestQuiz`, passing `recentQuizzes: quizzes` — still **empty**, because the first snapshot hasn't arrived. Both orchestrator guards (`QuizOrchestrator.swift:42 hasPending`, `:46 askedIds`) operate on an empty array, so the app can post a second quiz on top of an unanswered one, or re-ask a completed question.

**(b)** And once the array *does* hold real data, it's **polluted by Question-of-the-Day quizzes**. I verified `QuestionOfTheDayService.swift:151` writes the daily question into `FirestorePath.chatQuizzes` with `status: .pending`, and `CoupleChatService.swift:124` listens to that whole collection with **no `kind` filter**. `hasPending` is `recentQuizzes.contains { $0.status != .complete }` → an unanswered daily question is the normal state, so **chat quiz suggestion is suppressed permanently.** `QuizHubView.swift:312` already filters `!$0.isQuestionOfTheDay` with a comment explaining exactly this collection-sharing problem; the orchestrator was never updated.

**Why together:** fixing (a) alone converts a rare wrong suggestion into **zero suggestions ever.**

**Fix:** in `maybeSuggestQuiz`, fetch one-shot via the existing `fetchQuizProgress` (or move the call into the listener's first `onUpdate` behind a flag), **and** pass `quizzes.filter { !$0.isQuestionOfTheDay }`.
**Effort: hours.**

### B16. Auto-prefetch spends server AI quota uncounted and throws the result away
`CoupleViewModel.swift:184-215` `triggerAISuggestionIfNeeded` calls `generateSuggestions` with **no `hasAccess` check and no `recordUsage`**, through the real `HybridAISuggestionService` (injected at `ContentView.swift:47`). `functions/index.js:243` consumes one of the 5/day `suggestion` units per call.

The partner can log 3 moods a day, so the user can reach the "Get Suggestions" button — which says **5 left** — with 3 units already gone server-side; the server then returns `quota_exceeded` while the UI claims allowance remains. And `prefetchedSuggestions` (`:208`) **appears nowhere else in the codebase**, so the spend buys nothing. `isPrefetchingSuggestions` is never rendered either.

**Fix:** delete the prefetch (lines 196-214 plus both properties) — nothing consumes it, and deleting restores local/server counter agreement. Only gate-and-record it instead if you plan to have `SuggestionView` seed from it.
**Effort: minutes.**

### B17. Notification preferences: `try?` save, and a read failure overwrites real settings
Verified `NotificationViewModel.swift:111` `try? await notificationService.savePreferences(...)` — a rejected or offline write leaves the toggle showing its new value with **nothing persisted and no error** (this view model has no `errorMessage` at all).

Worse, `:117-118`:
```swift
preferences = (try? await notificationService.loadPreferences(...)) ?? NotificationPreferences()
```
A **transient read failure** silently replaces the user's stored preferences with framework defaults in memory — then the next toggle tap calls `savePreferences` and **writes those defaults back over the real document.**

**Fix:** surface save failures, and distinguish "document absent" from "read failed" — on a read failure leave `preferences` untouched and block saving until a successful load.
**Effort: 30 minutes.**

### B18. The rest — real, small, half a day together
- **QotD answer sheet gets stuck.** `QuestionOfTheDayViewModel.swift:231` — on a failed `submitAnswer` transaction, `quizBeingAnswered` is never cleared (the assignment at `:216` is inside the `do` block after the throw), so the sheet stays up with no message. Retapping re-runs the same failing transaction. Fix: move the clear into a `defer`.
- **Quiz history silently caps at 20 while the hero counts all.** `CoupleChatService.swift:126 .limit(to: 20)` (verified) feeds `QuizHistorySheet`, but `fetchQuizProgress` (`:157-160`) uses `getDocuments()` with no limit. A couple with 60 quizzes sees 20 rows, no pagination, no indication anything's missing — next to a hero saying "from 60 guesses". **Two numbers on one screen disagree.** Fix: give the sheet its own `fetchAllQuizzes` (ordered desc, `limit(to: 200)`) and leave the feed's 20 — or, for now, just change the subtitle at `QuizHubView.swift:222` to "Your last 20 quizzes" so the UI stops overclaiming.
- **QotD and DailyPhoto listeners are never stopped.** `CoupleDashboardView.swift:201-202` start them; `:210` is `.onDisappear { viewModel.stopListening() }` with no matching stops. They poll while the user is on other tabs, and neither registers with `registerTeardown` (only `CoupleyApp.swift:188`/`:192` do), so on sign-out they survive past `signOut()` and produce the "Missing or insufficient permissions" burst the teardown registry exists to prevent. Both `stop()` methods already exist.
- **`MicroAction.isGenerating` can never be observed.** Verified `MicroActionViewModel.swift:104-113` sets it true with a `defer`, and the body has **no suspension point** — `ActionGeneratorService.generate` is synchronous (`:13`). Both `@Published` writes land in one main-actor turn and SwiftUI coalesces them, so `MicroActionCard.swift:23-24`'s `loadingView` is **dead code** and the first generation shows `emptyView`. Fix: drop `isGenerating` and the branch. *(Also: `:112 guard !fresh.isEmpty else { return }` returns without setting `lastContextKey`, so an empty generation re-runs on every refresh.)*
- **The Quiz Hub's only quiz row is a dead end.** `QuizHubView.swift:321-325` — the "Most recent" row calls `dismiss()` and nothing else, dropping the user into the thread to hunt for the card. `presentQuizForAnswering(quizId:)` already exists and is already called from `ChatView.swift:242`. Fix needs a ~0.35s delay after dismiss, because the sibling sheet swallows an item set before the hub finishes dismissing.
- **Account deletion swallows every Firestore step.** `AccountDeletionService.swift:313, 324, 333, 338, 343` are all `try?` with no logging, then `:357` deletes the Auth user **unconditionally** and reports success. If step 5 fails, the user doc survives with `displayName`, `timezone`, `fcmToken`, `lastActive` and presence data, owned by a uid that no longer exists — **no client can ever read or retry it**, and the user was told their account was deleted. Fix: collect failures into a `var failures: [String]`, log them, and write a `pendingDeletion: true` marker before step 7 so a scheduled function can finish. Keep step 7 unconditional — that ordering is right for the App Store requirement.
- **One identical paywall row per locked item.** The lock overlay is **inside** the `ForEach` (`TogetherActiveSection.swift:60-81`, `:275-296`, `TogetherDreamBoardSection.swift:91`/`:103`), so a couple whose premium lapsed with 9 goals scrolls **7 byte-identical** lock cards. Fix: render only the entitled prefix, then one counted lock row outside the loop ("7 more goals on Premium").

### Realistic total for B
**4-5 working days.**

But the shape matters more than the total: **B2, B3 and B7 are about 40 minutes combined** and fix a quota leak, vanishing messages, and the widget refresh budget. **B1 is hours** and resurrects a dead feature. **B4 is the one real day.** Everything else is a long tail of 15-30 minute fixes.

**Do B2 + B3 + B7 + B8 today — under an hour and a half for four real user-facing defects.**

---

## C. THE LOCALIZATION WORK ITSELF

### What the string surface actually is

Measured on the current tree:

| Category | Count | Migration |
|---|---|---|
| `Text("literal…")` incl. interpolated | **394** | **Free.** Already takes `LocalizedStringKey`; extracts automatically |
| `Text(<identifier>)` | **314** | ~36 emoji (leave), ~100 genuine user content (leave — translating `memory.title` would be a bug), **~96 app copy needs A5/A6 first** |
| Display-role `-> String` model properties | **54 properties, ~276 literals** | **Refactor first (A5).** Invisible to the extractor |
| `errorDescription` conformances | **13**, all bare literals | **Refactor first (A5a)** |
| Enum labels from `rawValue.capitalized` | **4** | **Needs a `switch` written first (A5b)** — there is no literal to extract |
| Notification title/body assignments | **12** local + **12** server pairs | **Needs `localizedUserNotificationString` (A7)** |
| `Text("a" + "b")` | **3** | **Collapse first (A12)** |
| Plural ternaries | **14** (5 invisible, 9 two-form) | **Rewrite as plural keys (A8)** |
| Content banks | **~1,500 literals** | **Separate strategy — see below** |

Content bank volume, measured (literals ≥12 chars containing a space):
- `ChatQuizBank.swift` — **1,172** across 72 templates in 1,415 lines
- `MockAICoachService.swift` — **169**
- `ActionGeneratorService.swift` — **104** (53 `Template` entries, each `text` + `rationale`)
- `AICoachModels.swift` — **66**
- Plus `Dream.swift` ~55, `TimeMemory.swift` ~52, `CoupleChallenge.swift` ~50, `QuizQuestion.swift` ~50, `TogetherGoal.swift` ~48, `OnboardingProfile.swift` ~46, `DailyPhotoPrompts` 24

*(An earlier audit put the app-wide total at 4,303 literals / 64,000 words. That does not reproduce — the real figure is closer to 2,800 / 24,000. The per-file numbers above are solid; use those for planning.)*

### The plan, honestly sized

**Part 1 — Prepare (section A). ~7-9 days. NOT a weekend.**
Everything in A, in the order given. This is the part that has a deadline, and it's two thirds of the total localization effort. The temptation is to skip it and extract now; the cost of that is a catalog that looks complete over an app that is half English, plus a key-renaming migration across every translation you've paid for.

**Part 2 — Create the catalog and extract. Genuinely a weekend.**
Add `Localizable.xcstrings`, add `vi` to `knownRegions`, build, let Xcode extract. If Part 1 is done, this pulls in the 394 `Text` literals, the ~96 converted `Text(variable)` sites, and the ~290 converted model/error properties — roughly **700-800 chrome strings**, essentially for free. Add `InfoPlist.xcstrings` per target (A15) and the shared catalog membership for the widget (A11).

**Part 3 — Translate the chrome. ~700-800 strings.**
This is a real translation job but a bounded one. A weekend of your own time if you're writing the Vietnamese yourself; a week of calendar time if you're commissioning it. Review matters more than volume here — these are the words users read every day.

**Part 4 — The content banks. ~1,500 strings. NOT a weekend. Make a deliberate decision.**
This is where I'd push back on the obvious approach. Flattening `ChatQuizBank` into 1,172 catalog rows **loses the unit**: a template is question + subtitle + ~5 options + ~5 hints, and the hints are keyed by the options. A translator seeing the rows separately will translate an option one way and its hint key another, and **the hint silently stops resolving.** (A2 fixes the mechanical half of this by introducing ids; the organisational half remains.) 1,172 unordered rows is also unreviewable, and a catalog falls back **per row**, so a half-translated quiz renders **half English** — you cannot ship it partially.

**My recommendation: split chrome from content.** Keep the ~700-800 chrome strings in `Localizable.xcstrings`. Move the banks out of Swift into bundled per-locale JSON keyed by the ids A2 introduces — `Resources/quizbank.en.json`, `quizbank.vi.json` keyed by `questionId` + `optionIds`, `prompts.{lang}.json` by index, `actions.{lang}.json` by bucket+index — loaded by a small `ContentBank` that resolves `Locale.preferredLanguages` with a **whole-template** fallback to `en`.

That buys you three things a flat catalog can't: an untranslated quiz renders **consistently English** rather than half-translated; you can translate the 72 templates **in priority order** and ship as you go; and a bank can ship **without an App Store release**.

Do the A2 id work **before** the move — the JSON schema needs those ids.

**Honest sizing for Part 4: 1-2 weeks of translation work**, whether you do it or commission it, and it is the part you should be willing to ship incrementally. With 10-20 daily users you do not need all 72 quiz templates in Vietnamese on day one. Ship 15 good ones and the fallback.

### Total, start to a Vietnamese build you'd ship
**Part 1 (2 weeks) + Parts 2-3 (1 week) = 3 weeks to a localized app with English content banks.** Part 4 runs after that, incrementally, and never blocks a release.

**The honest answer to "is this a weekend?":** Part 2 is. Part 3 almost is. Parts 1 and 4 are not, and Part 1 is the one you cannot defer — it's the whole reason the sequencing matters.

---

## D. DELIBERATELY NOT DOING

**Rejected on consequence, though the code claims check out:**

1. **Locked premium rows clipping at 24pt vs the card's 22/20pt.** `TogetherActiveSection.swift:81`/`:296` and `TogetherComponents.swift:215`/`:222`/`:242` do hardcode `cornerRadius: 24, style: .continuous`, and `Brand.cardCornerRadius` is 22/20. But the stated consequence doesn't follow: **a larger clip is a no-op on an already-rounded child** — nothing can bleed past its own corners into a bigger clip. And `PremiumLockOverlay` is a full-bleed frosted panel that **covers** the card, so the user sees the overlay's corners, not the card's. What's left is a 2pt radius difference on one panel in one theme: a token-consistency preference. *(One real scrap: `TogetherComponents.swift:53 var cornerRadius: CGFloat = 24` is genuinely dead — the body builds its shape from `Brand.cardCornerRadius` and all ten call sites pass only `tint:`/`padding:`. Delete it whenever you're next in the file. Also note the same literal appears at six more sites nobody listed — `TogetherView.swift:410`/`:413`, `TogetherCoachSection.swift:226`/`:229`, `DreamDetailSheet.swift:138`/`:140` — so even as a tidy-up the original scope was wrong.)*

2. **Percent sign glued to the number** (12 sites: `TogetherActiveSection.swift:188/210/370/412`, `TogetherTodayHero.swift:118/203`, `TogetherCoachSection.swift:121`, `GoalDetailSheet.swift:99`, `QuizHubView.swift:158`, `CoupleProfileView.swift:113`, `StatsPreviewCard.swift:73`, `CoupleDashboardView.swift:581`). **Vietnamese writes "50%" exactly as English does**, so nothing breaks on the language you're adding. Worse, the proposed fix introduces a regression: `.percent` **rounds** while `Int(goal.progress * 100)` **truncates**, so a goal at 0.996 would display "100%" while `isComplete` is still false — a visible lie at the completion boundary, at 12 sites, to buy nothing for vi. And three of those sites hold values already on a 0-100 scale, where `.percent` needs a `/100` nobody accounted for. **Revisit only if fr/tr/de-CH is ever on the roadmap**, and then as `(x.rounded(.down)/100).formatted(.percent)`.

3. **`StreakService`'s identical `else if` / `else` branches** (`:84-90`). Accurate, but `updateStreak` has **zero callers**, so nothing is broken and nothing will break. Subsumed by B1, whose fix requires rewriting the method anyway.

4. **The content-bank JSON migration as a *bug*.** It's an architecture recommendation, not a defect. Its one mechanical breakage claim (hints keyed by option text) is the same root cause as A2. It belongs in section C as a strategy choice — which is where I put it.

**Deferred with a trigger, not fixed:**

5. **Amount entry parsed with `Double(String)`** — `GoalDetailSheet.swift:232`/`:376`, `GoalEditorSheet.swift:456`/`:527`. The paired `.keyboardType(.numberPad)` emits ASCII digits with no separator key on a Latin keyboard, so **Vietnamese and German users are not affected.** It fails only on a keyboard emitting Arabic-Indic or Devanagari digits (parse → nil → amount 0 → the Contribute button stays permanently disabled with no error) or on pasting "1.234,50". **Fix when a non-Latin-digit locale is on the roadmap:** `try? Double(text, format: .number)`.

**Verified as already correct — do not touch:**

6. **`CurrencyFormatting.swift`** — currency pinned to the stored ISO code, only separators from `Locale.current`. The suspected `maximumFractionDigits = 0` clash isn't one: `NumberFormatter` clamps the minimum down. **The "US$325 / US$1.000" you saw on the Together tab is correct output** — a USD goal on a Vietnam-region device; the "US$" disambiguator and "." grouping are both what that locale asks for.
7. **The 8 `dateStyle`/`timeStyle` display formatters** (`Anniversary.swift:130`, `TimeMemory.swift:256`, `MemoryCard.swift:276`, `MemoryDetailSheet.swift:296`, `TimeTreeHeader.swift:280`, `AnchorSetupSheet.swift:181`, `ManageSharedDataView.swift:163`, `MicroActionCard.swift:252`) **must NOT have `.locale` added.** A nil locale means `Locale.current`, which follows the app's chosen language once a catalog exists. "Every DateFormatter should set `.locale`" is the wrong rule — **only storage-key formatters should** (A1).
8. **`MicroAction.swift:106`** uses `ISO8601DateFormatter` — locale-independent by construction. The correct pattern, and the direct contrast with A1.
9. **`MonthlyMoodInsightView.swift:224-246`** is the reference-correct calendar grid (`firstWeekday`, symbol rotation, leading blanks). *(The `ChallengeDetailSheet.swift:188-228` heatmap should copy it — its weekday labels are off by one on six days in seven because `startOfRange` is `today - 34 days`, whose weekday rotates daily. Real but cosmetic and language-independent; it's B-tier tail work, not A.)*
10. **No diacritic collation bug anywhere.** All ~30 `.sorted` sites order by `Date`, `Int` or `Double`, never by user-visible text. Plain `<` *does* break Vietnamese ordering, but nothing does it.
11. **Diacritic clipping is not a real risk** at your sizes. SF Rounded Bold 34pt: ascender 32.87pt, descender -7.17pt, line height 40.04pt; Vietnamese double-diacritic ink tops out 1.68pt **inside** the ascender. All 64 `.lineSpacing` sites are safe.
12. **Enum `rawValue`s on the wire** — `ChatQuizStatus`, `QuizTopic`, `LoveLanguage`, `AttachmentStyle`, `StressResponse`, `CoachIssueType` all travel to Firestore and the AI backend as `rawValue`, never as a display label. **That separation is what makes localizing the display layer possible at all — it must not be collapsed.**
13. **The `"DELETE"` confirmation phrase** (`DeleteAccountView.swift:58`) is one constant used for both the instruction and the comparison, so localizing it to "XÓA" keeps the gate consistent automatically. Already the right shape.
14. **The design tier system itself** — `SurfaceTier`, `BrandType`, `TierContainer`, `BrandCard`, `wellBackground`, `Brand.Space` carry no user-facing copy, and `Eyebrow` uses `.textCase(.uppercase)` (the locale-aware form) rather than `.uppercased()`. Only the `String`-typed parameters are a problem (A6), not the design. *(Context, not a defect: the Together tab uses the tier system zero times — it got a token pass only, which is why it's the one tab still on its own chassis.)*
15. **Zero `Text(verbatim:)` misuse**, and all four `String(format:)` uses are `"%02x"` hex digests, not user-facing text. No homegrown format layer to untangle.

**Also confirmed already fixed, so don't go looking:** the Mood tab's five prior blockers; the Home MicroAction dead states; the Home dateline (`CoupleDashboardView.swift:322`, already template-driven and the in-repo reference for A9); the avatar-row re-centring; TimeTree's `errorMessage` clearing *and* rendering; the Together hero's coach-insight paywall leak (`:139`); the Quiz Hub promoting the QotD (`:316`); the `"memor" + "y"/"ies"` splice; and `StatsPreviewCard.swift:58`'s identical-branch ternary.

---

## The one-paragraph version

Fix **A1** (locale-sensitive Firestore day keys — corrupting data now), **A12**, **A13** and **A4** today; that's about 90 minutes. In the same sitting do **B2**, **B3**, **B7** and **B8** — another 90 minutes for a quota leak, vanishing chat messages, a throttled widget and a swallowed photo error. Then take two weeks for the rest of section A before you create the catalog, with **A2+A3** (quiz identity, ~2 days) and **A5** (276 literals hiding in `-> String` model properties, 2-3 days) as the real work. **B1** — the streak and sync score that nothing has ever written — deserves a day of its own whenever you want the stats screen to stop lying. Only after A is done should you add `Localizable.xcstrings`; that part genuinely is a weekend. The content banks are 1,500 strings and should go to per-locale JSON keyed by the ids A2 introduces, translated incrementally — never blocking a release.