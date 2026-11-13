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
   Never add a `%` specifier that the source lacks (write "percent" in words or `％` if needed).
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
4. Length: tab titles and short buttons must stay short (tab titles ideally ≤ 10 characters).
   Use the shortest natural wording for labels; full sentences can be as long as they need.
5. Consistency: use the glossary `docs/l10n/glossary/<lang>.json` for every term in it.
6. Gender: the user and partner can be any gender. Prefer neutral phrasing; never assume.
7. Don't add or remove information, don't add quotes the source doesn't have, don't
   translate placeholders' contents. Keep the meaning of the English; don't summarise.

## Terminology
Use the language's file in `glossary/` for every term in it, and follow its `_style` notes.
