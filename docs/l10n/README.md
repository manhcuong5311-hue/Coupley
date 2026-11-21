# Coupley localization

Coupley ships in English plus 99 languages.

- The first 30: vi, es, pt-BR, fr, de, it, ja, ko, zh-Hans, zh-Hant, ru, uk,
  pl, tr, id, ms, th, hi, ar, nl, sv, da, nb, fi, cs, ro, el, hu, he, fil.
- Europe: pt-PT, ca, hr, sk, sl, sr (Cyrillic), bs (Latin), mk, bg, lt, lv,
  et, is, ga, cy, eu, gl, sq, mt, be, lb.
- Middle East, Caucasus and Central Asia: fa, ur, ps, ku (Kurmanji, Latin),
  az, ka, hy, kk, uz, ky, tg, tk, mn.
- South Asia: bn, ta, te, mr, gu, kn, ml, pa, or, as, ne, si.
- South-East and East Asia: my, km, lo, jv, su, ceb, zh-HK.
- Africa: sw, am, yo, ig, ha, zu, xh, af, so, rw, mg, om, ti, sn, ny.
- Pacific: mi.

Every translation was written and reviewed by AI; no native speaker has read
them yet. Of the 69 languages added after the first 30, the smaller ones (for
example om, ti, sn, ny, rw, tg) are the likeliest to need a native pass.

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
  for the Arabic and Hebrew scripts, the Indic scripts (Devanagari, Bengali,
  Gurmukhi, Gujarati, Odia, Tamil, Telugu, Kannada, Malayalam, Sinhala), Thai,
  Lao, Khmer, Burmese, CJK and Hangul, where tracking breaks the script.
- **Punctuation-only keys** (`%@.`, `%@, %@`, `“%@”`, `%lld%%`, `%@ · %@`,
  `%` and their variants) carry each language's own full stop, list comma,
  quote marks, percent form and separator (`%@։` in Armenian, `«%@»` in
  Persian, `%% %lld` in Basque).
- **The " · " separator** is a spaced en dash in Arabic, Persian and Pashto,
  in their translations and in code (`ScriptSpacing.factSeparator`,
  `factMark`): the zero of their digits is a dot, so "1 ·" reads as 10.
- **Digits written in a translation** are the digits the app formats numbers
  with in that language: its own digits in ar, fa, ps, as and ne, Latin
  digits everywhere else (bn, hi, th and my included).
- **Burmese numbers use Latin digits** (`FormattingLocale`, applied first
  thing at launch in the app and the widget): the rounded bold system font
  draws the Burmese digits ၂ and ၅ broken.
- **A language needs calendar names in iOS.** Haitian Creole was translated
  and then replaced by Cebuano: iOS 26 has no month or weekday names for it,
  so every date read "M11 21, Sat", and an app cannot lend a language another
  one's names (iOS always puts the app's language into the current locale).
  Check a candidate in the simulator before translating it.
- **Line spacing**: Khmer, Burmese and Telugu get extra room between lines
  (`ScriptSpacing.extraLineSpacing`, set on the root view), or the marks under
  one line collide with those over the next. A view that needs its own
  spacing uses `scriptAwareLineSpacing(_:)`, never `lineSpacing(_:)`.
- **Right-to-left** (ar, he, fa, ur, ps): layouts mirror automatically; directional SF
  Symbols use `flipsForRightToLeftLayoutDirection(true)`; formatted amounts are
  wrapped in Unicode isolates so "US$" is not reordered. A translation whose
  first letter outside the placeholders is Latin ("Coupley …", "AI …"), or
  that is only placeholders and punctuation ("%1$@ – %2$@"), begins with a
  right-to-left mark (U+200F): without it the line is laid out left-to-right
  and reads backwards. A progress ring drawn with `trim` takes
  `ringStartsAtTop()`, or its quarter turn runs the other way and it starts
  at six o'clock.
- **A number with its percent sign** is written the way iOS formats it in
  each language ("32 %", "%32", "٣٢٪"), the same in every string of that
  language as in its `%lld%%` key.
- **Relative times** ("5 min. ago") come from `RelativeDateTimeFormatter
  .compactString(for:)`. iOS has no relative wording for ku, su, yo, ig, xh,
  rw, mg, sn, ny, mi and ceb and answers "-3 d": `RelativeTimeWording` shows
  the date there instead. Mongolian, Amharic and Zulu use the full style,
  where the short one is wrong ("1 weeks ago").
- **Several items in one field** (the quiz's free-text answers) are split on
  every script's comma, not only the Latin one (`QuizListText`).

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
  `-coupleyOpen gardenLab` opens the Garden lab and `gardenJourney` its
  Journey page: an in-memory garden that never writes Firestore.
- `-coupleyNoAds` hides ads and skips the consent and tracking prompts, for
  clean screenshots.
- `-coupleyDemoData` draws a localized demo couple instead of the signed-in
  test couple's own data: two first names, a short chat, goal and challenge
  titles and the Home stats (`Coupley/Core/Debug/DemoContent.swift`). Display
  only; nothing is written to Firestore or the local caches.
- `-coupleyDumpContentStrings` prints every content-bank base string as JSON,
  the source for `Content.xcstrings`.
- `-NSAccentuateLocalizedStrings YES` (Apple's pseudo-localization) accents
  every localized string, so any unaccented interface text is a string that
  missed localization.
