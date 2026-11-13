//
//  DailyPhoto.swift
//  Coupley
//
//  A daily prompt both partners answer with a photo. Neither sees the other's
//  until both have sent one — the same blind-then-reveal shape as the quiz,
//  which is the mechanic the app is already built around.
//
//  Scheduling copies `QuestionOfTheDayService` rather than keying on a
//  calendar date, for the same reason: two partners in different timezones
//  would compute different keys and end up answering different prompts. The
//  couple document owns a sequence counter instead.
//

import Foundation
import FirebaseFirestore

struct DailyPhoto: Identifiable, Codable, Equatable {

    @DocumentID var firestoreId: String?
    let id: String

    /// The rendered prompt, in the language of the device that happened to
    /// create the document. Both partners read the same couple document, so
    /// this one string decided the prompt's language for both of them.
    ///
    /// Kept because every document written before `promptId` carries only
    /// this, and because a build already shipped reads it. Draw `promptText`
    /// instead.
    let prompt: String

    /// Stable id into `DailyPhotoPrompts`. Optional, and it must stay
    /// optional: both reads here are `try? data(as:)`, so a required field
    /// would make every existing document fail to decode. That failure is
    /// silent — the listener yields no photo and the home card simply
    /// disappears, and `previous` becomes nil in `ensureCurrentPrompt`, which
    /// fails the `!previous.photos.isEmpty` test and so holds every prompt to
    /// the 72h stale interval instead of refreshing it at 20h.
    var promptId: String? = nil

    let createdAt: Date
    /// userId → download URL.
    var photos: [String: String]

    /// The prompt to DRAW for this reader.
    ///
    /// Prefers the id; failing that, maps the stored base-language text back
    /// to a prompt — which works for every document already written, because
    /// `developmentRegion = en` keeps those exact strings in source as the
    /// catalog's base values. Only a prompt since removed from the bank falls
    /// through to the stored text, and that still goes through the Content
    /// catalog, which may keep a translation the bank no longer does.
    var promptText: String {
        if let promptId, let known = DailyPhotoPrompts.byId(promptId) {
            return known.displayText
        }
        if let known = DailyPhotoPrompts.byText(prompt) {
            return known.displayText
        }
        return ContentL10n.text(prompt)
    }

    func photoURL(for userId: String) -> String? { photos[userId] }
    func hasSubmitted(_ userId: String) -> Bool { photos[userId] != nil }

    /// Both sides in — the images may be shown.
    func isRevealed(_ userA: String, _ userB: String) -> Bool {
        hasSubmitted(userA) && hasSubmitted(userB)
    }
}

// MARK: - Prompt bank

/// One daily prompt. `id` is the identity and never changes.
struct DailyPhotoPrompt: Equatable {
    let id: String

    /// BASE-LANGUAGE text. What gets stored on the document, and the key
    /// `byText` matches when resolving a document written before ids existed.
    /// Never translated — draw `displayText`.
    let text: String

    /// What to draw: the prompt in the reader's language when the Content
    /// catalog has it, otherwise `text` unchanged. `text` itself never moves.
    var displayText: String { ContentL10n.text(text) }

    init(_ id: String, _ text: String) {
        self.id = id
        self.text = text
    }
}

enum DailyPhotoPrompts {

    /// Deliberately about the ordinary and the immediate. A prompt you can
    /// only answer from where you are right now is the one that actually
    /// shows your partner your day; "post a nice photo" gets a camera roll
    /// pick from last summer.
    ///
    /// APPEND ONLY, and never reorder: `prompt(coupleId:sequence:)` bakes
    /// `all.count` into its arithmetic, so adding an entry reshuffles which
    /// prompt every couple gets next. Stored ids are unaffected — that is the
    /// point of having them — but a removed entry makes old documents fall
    /// back to their stored English text.
    static let all: [DailyPhotoPrompt] = [
        .init("whats_in_front_of_you", "What's directly in front of you right now?"),
        .init("show_them_your_view", "Show them your view."),
        .init("what_did_you_eat_today", "What did you eat today?"),
        .init("something_that_made_you_smile", "Something that made you smile today."),
        .init("messiest_corner_near_you", "The messiest corner near you."),
        .init("whats_on_your_feet", "What's on your feet?"),
        .init("something_blue_within_reach", "Something blue within arm's reach."),
        .init("your_drink_right_now", "Your drink right now."),
        .init("sky_where_you_are", "The sky where you are."),
        .init("something_had_for_years", "Something you've had for years."),
        .init("whats_on_your_screen", "What's on your screen?"),
        .init("where_youre_sitting", "Where you're sitting."),
        .init("something_youd_buy_if_free", "Something you'd buy if it were free."),
        .init("last_thing_you_touched", "The last thing you touched before this."),
        .init("something_that_smells_good", "Something that smells good right now."),
        .init("your_hands_as_they_are", "Your hands, as they are."),
        .init("something_you_mean_to_fix", "Something you keep meaning to fix."),
        .init("a_colour_youre_wearing", "A colour you're wearing."),
        .init("nearest_window", "The nearest window."),
        .init("something_that_reminds_you_of_them", "Something that reminds you of them."),
        .init("whats_in_your_bag_or_pockets", "What's in your bag or pockets."),
        .init("somewhere_you_walked_past", "Somewhere you walked past today."),
        .init("light_in_the_room", "The light in the room right now."),
        .init("something_small_you_own_and_love", "Something small you own and love."),
    ]

    private static let byIdIndex: [String: DailyPhotoPrompt] = Dictionary(
        all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
    )

    /// Indexed by the base-language text, so a document written before ids
    /// existed can still be resolved — and therefore translated.
    private static let byTextIndex: [String: DailyPhotoPrompt] = Dictionary(
        all.map { ($0.text, $0) }, uniquingKeysWith: { first, _ in first }
    )

    static func byId(_ id: String) -> DailyPhotoPrompt? { byIdIndex[id] }

    static func byText(_ text: String) -> DailyPhotoPrompt? { byTextIndex[text] }

    /// Same FNV-1a rotation as the question bank: stable across devices and
    /// launches, and it walks the whole list before repeating.
    static func prompt(coupleId: String, sequence: Int) -> DailyPhotoPrompt? {
        guard !all.isEmpty else { return nil }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in coupleId.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let offset = Int(hash % UInt64(all.count))
        let step = ((sequence % all.count) + all.count) % all.count
        return all[(step + offset) % all.count]
    }
}

#if DEBUG
extension DailyPhotoPrompts {
    /// Every base string the UI shows through ContentL10n (to build the Content catalog).
    static var l10nContentStrings: [String] { all.map(\.text) }
}
#endif
