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
    let prompt: String
    let createdAt: Date
    /// userId → download URL.
    var photos: [String: String]

    func photoURL(for userId: String) -> String? { photos[userId] }
    func hasSubmitted(_ userId: String) -> Bool { photos[userId] != nil }

    /// Both sides in — the images may be shown.
    func isRevealed(_ userA: String, _ userB: String) -> Bool {
        hasSubmitted(userA) && hasSubmitted(userB)
    }
}

// MARK: - Prompt bank

enum DailyPhotoPrompts {

    /// Deliberately about the ordinary and the immediate. A prompt you can
    /// only answer from where you are right now is the one that actually
    /// shows your partner your day; "post a nice photo" gets a camera roll
    /// pick from last summer.
    static let all: [String] = [
        "What's directly in front of you right now?",
        "Show them your view.",
        "What did you eat today?",
        "Something that made you smile today.",
        "The messiest corner near you.",
        "What's on your feet?",
        "Something blue within arm's reach.",
        "Your drink right now.",
        "The sky where you are.",
        "Something you've had for years.",
        "What's on your screen?",
        "Where you're sitting.",
        "Something you'd buy if it were free.",
        "The last thing you touched before this.",
        "Something that smells good right now.",
        "Your hands, as they are.",
        "Something you keep meaning to fix.",
        "A colour you're wearing.",
        "The nearest window.",
        "Something that reminds you of them.",
        "What's in your bag or pockets.",
        "Somewhere you walked past today.",
        "The light in the room right now.",
        "Something small you own and love.",
    ]

    /// Same FNV-1a rotation as the question bank: stable across devices and
    /// launches, and it walks the whole list before repeating.
    static func prompt(coupleId: String, sequence: Int) -> String? {
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
