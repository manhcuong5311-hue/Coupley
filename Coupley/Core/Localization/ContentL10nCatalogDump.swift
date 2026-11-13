//
//  ContentL10nCatalogDump.swift
//  Coupley
//
//  DEBUG only. Gathers every base string the UI shows through
//  `ContentL10n.text` (each content bank's `l10nContentStrings`), so the
//  "Content" string catalog (Coupley/Core/Localization/Content.xcstrings) is
//  built from exactly what the app can show.
//
//  Launch a Debug build with the `-coupleyDumpContentStrings` argument: the
//  list is printed to stdout as one JSON array on its own line, between a
//  "<<<CONTENT_STRINGS" line and a "CONTENT_STRINGS>>>" line, and the app
//  then starts normally.
//

#if DEBUG
import Foundation

enum ContentL10nCatalogDump {

    /// The launch argument that prints the dump.
    static let launchArgument = "-coupleyDumpContentStrings"

    /// The sorted, de-duplicated union of every content bank's base strings.
    /// Empty strings are left out: `ContentL10n.text` never looks them up.
    static func allStrings() -> [String] {
        let providers: [[String]] = [
            ChatQuizBank.l10nContentStrings,             // chat quizzes and the daily question: topics, questions, subtitles, options, hints
            QuizBank.l10nContentStrings,                 // partner quiz: multiple-choice options
            DailyPhotoPrompts.l10nContentStrings,        // daily photo prompts
            RuleBasedActionGenerator.l10nContentStrings, // micro-action ideas and their rationales
            ChallengeSuggestion.l10nContentStrings,      // Together: challenge suggestions
            DreamSuggestion.l10nContentStrings,          // Together: dream suggestions
            GoalSuggestion.l10nContentStrings,           // Together: goal suggestions
        ]
        return Set(providers.joined()).filter { !$0.isEmpty }.sorted()
    }

    /// Prints `allStrings()` when the process was launched with
    /// `launchArgument`, and does nothing otherwise. Never stops the launch.
    static func printIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains(launchArgument) else { return }
        let strings = allStrings()
        guard let json = try? JSONSerialization.data(withJSONObject: strings,
                                                     options: [.withoutEscapingSlashes]) else {
            print("ContentL10nCatalogDump: could not encode \(strings.count) strings")
            return
        }
        // One unbuffered write, so nothing else printed can land between the
        // markers and nothing is left in a buffer if the app is killed.
        var block = Data("<<<CONTENT_STRINGS\n".utf8)
        block.append(json)
        block.append(Data("\nCONTENT_STRINGS>>>\n".utf8))
        FileHandle.standardOutput.write(block)
    }
}
#endif
