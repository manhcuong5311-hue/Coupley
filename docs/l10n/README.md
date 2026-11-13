# Coupley localization

Coupley ships in English plus 30 languages: vi, es, pt-BR, fr, de, it, ja, ko,
zh-Hans, zh-Hant, ru, uk, pl, tr, id, ms, th, hi, ar, nl, sv, da, nb, fi, cs,
ro, el, hu, he, fil.

## Where the text lives

| Catalog | What it holds |
| --- | --- |
| `Shared/Localizable.xcstrings` | Every interface string of the app and the widget (both targets compile it). Keys are extracted from the Swift code by Xcode. |
| `Coupley/Core/Localization/Content.xcstrings` | The built-in content banks: quiz questions, options and insights, daily photo prompts, micro-action ideas, Together suggestions. Looked up at runtime by their English base text through `ContentL10n.text(_:)`; a missing entry falls back to English. Every entry is `manual`. |
| `Coupley/InfoPlist.xcstrings` | The App Tracking Transparency prompt. |

`STRING_CATALOG_GENERATE_SYMBOLS` is off: the manual content keys would turn
into thousands of Swift symbols, and some of them collide ("Hip-hop" and
"Hip-Hop").

## Rules the code follows

- **Stored data stays English.** Firestore fields, ids, rawValues, quiz
  answers, result summaries and chat system lines are written in the base
  language and only drawn localized (`baseLabel` / `displayLabel`,
  `ChatSystemLine`, `QuizResultCopy.baseSentence`).
- **Notifications stay English**, local and server pushes alike, by product
  decision. The in-app notification list shows them as sent.
- **Whole sentences, never concatenation.** Several placeholders use
  positional specifiers so translators can reorder them.
- **Plurals** use String Catalog plural variations (CLDR categories; English
  has one/other too).
- **A caption beside a number that is drawn on its own** ("292" over "days
  together", "5" before "check-ins", the big letter countdown) is localized as
  a plural key that carries the count, and `CountedCaption.removingCount(from:)`
  removes the number on screen. The catalog compiler rejects plural forms that
  never reference the number, so translations keep `%lld`.
- **Numbers, percents, dates, currencies and lists** go through Foundation
  formatters (`.formatted()`, `.percent`, `.list(type: .and)`), so digits and
  separators follow the locale (Arabic-Indic digits in Arabic).
- **Letter-spacing** (`scriptAwareTracking` / `scriptAwareKerning`) is skipped
  for Arabic, Hebrew, Devanagari, Thai, CJK and Hangul, where tracking breaks
  the script.
- **Right-to-left** (ar, he): layouts mirror automatically; directional SF
  Symbols use `flipsForRightToLeftLayoutDirection(true)`; formatted amounts are
  wrapped in Unicode isolates so "US$" is not reordered.

## Adding or changing a string

1. Write it with `String(localized:comment:)`, `Text("...", comment:)` or a
   `LocalizedStringResource`, as a whole sentence, with a comment that says
   where it appears and what each placeholder is.
2. Build in Xcode: the key appears in `Shared/Localizable.xcstrings` as new
   in every language. Until it is translated, it shows in English.
3. Translate it into every language, following `TRANSLATOR_BRIEF.md` and the
   language's file in `glossary/` (terminology, voice, quote marks, plural
   categories). Plural keys need every category the language uses.

## Adding a language

Add it to the project's localizations, translate both catalogs and the
InfoPlist catalog, and write its glossary first so the terms stay consistent.

## Debug launch arguments (Debug builds only)

- `-coupleyStartTab home|mood|together|journey|chat` opens on that tab.
- `-coupleyOpen coach|letters|compose` opens that screen from Home.
- `-coupleyNoAds` hides ads and skips the consent and tracking prompts, for
  clean screenshots.
- `-coupleyDumpContentStrings` prints every content-bank base string as JSON,
  the source for `Content.xcstrings`.
- `-NSAccentuateLocalizedStrings YES` (Apple's pseudo-localization) accents
  every localized string, so any unaccented interface text is a string that
  missed localization.
