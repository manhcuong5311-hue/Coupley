# Coupley translation brief

## The app
Coupley is an iOS app for couples (two partners connected to each other). Tabs:
**Home** (today's photo prompt, question of the day, partner presence, ping, pinned future
letters), **Mood** (daily mood check-in, monthly insights), **Together** (shared goals,
challenges, dreams), **Journey** (a tree that grows with the days together, memories,
memory capsules, future letters, anniversaries and "crown" milestones), **Chat** (messages,
quizzes about each other). Also an AI relationship coach, settings, a paywall to remove ads.
Users are couples of all ages; the tone is warm, intimate, playful but never cheesy, short
and clear like good app copy. Write the way a native product designer in your language would
write this app, not a literal translation.

## Two kinds of text
- **Interface strings** (`Shared/Localizable.xcstrings`): each key has a developer comment and
  is used in one or more places in the Swift code. Read the comment and the code around it to
  tell what the string is: a button, a title, a tab name, a VoiceOver label (spoken: write it for
  the ear), an error message, a placeholder, or a phrase joined with others by " · ".
- **Content strings** (`Coupley/Core/Localization/Content.xcstrings`): the built-in quizzes
  (question, a subtitle under it, short answer options, and for each option an *insight*: 1–3
  sentences addressed to the person who picked it), daily photo prompts, small action ideas with
  a one-line reason, and Together suggestions. They never contain placeholders. Keep option labels
  short and parallel with their siblings.

## Rules
1. Placeholders: keep every format specifier (`%@`, `%lld`, `%d`, `%1$@`, `%2$lld` …) exactly,
   with the same type. You may move them. If the source has two or more placeholders and your
   word order differs, use positional forms (`%2$@ … %1$@`). Never translate or drop them.
   `%@` is usually a name, a date or time, or another translated phrase; read the snippet.
   Never add a `%` specifier that the source lacks. A percent sign that stands alone in a
   string without placeholders ("% avg") is written as it is; inside a string with
   placeholders it is doubled (`%%`), as in the source.
2. Plurals: an interface entry with `"ints": 1` gets a JSON object with one form per plural
   category of your language (the categories are given to you), for example Russian
   `{"one": "%lld день", "few": "%lld дня", "many": "%lld дней", "other": "%lld дня"}`. Every
   form keeps the number specifier, except a `zero`, `one` or `two` form may spell the number
   out ("ذكرى واحدة"). Languages with only `other` return a plain string. Entries with
   `"ints"` of 0 or 2+ always get a plain string. An English source like "1 day" (no
   placeholder) is the singular case only.
3. Keep unchanged: the brand "Coupley", emoji, SF Symbol names, URLs, "AI" (or your language's
   usual abbreviation if clearly more natural), line breaks (`\n`), the middle dot separator
   " · ". Adapt quote marks, spacing and sentence punctuation to your language's norms.
   Arabic, Persian and Pashto write the separator as a spaced en dash (" – "): the zero of
   their digits is a dot, so a middle dot beside a number reads as a digit.
4. Length: tab titles and short buttons must stay short (tab titles ideally ≤ 10 characters).
   Use the shortest natural wording for labels; full sentences can be as long as they need.
5. Consistency: use the glossary `docs/l10n/glossary/<lang>.json` for every term in it.
6. Gender: the user and partner can be any gender. Prefer neutral phrasing; never assume.
7. Don't add or remove information, don't add quotes the source doesn't have, don't
   translate placeholders' contents. Keep the meaning of the English; don't summarise.
8. Digits: a number written out in a translation uses the digits the app formats numbers
   with in that language, so it matches the counts and dates beside it: the language's own
   digits in Arabic, Persian, Pashto, Assamese and Nepali, Latin digits (0–9) everywhere
   else, Bengali, Hindi, Thai and Burmese included. A code such as "ABC123" stays as it is.
9. Right-to-left languages: a line whose first letter outside the placeholders is Latin
   ("Coupley …", "AI …", "%@ Premium …") must begin with a right-to-left mark (U+200F), or
   iOS lays it out left-to-right and it reads backwards. So must a line made only of
   placeholders and punctuation ("%1$@ – %2$@", "«%@»"): its two parts would swap places.
10. Percentages: write a number with its percent sign the way iOS formats it in your
   language ("32 %", "%32", "٣٢٪"), the same way in every string.

## Terminology
Use the language's file in `glossary/` for every term in it, and follow its `_style` notes.
