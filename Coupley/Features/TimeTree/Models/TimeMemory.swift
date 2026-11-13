//
//  TimeMemory.swift
//  Coupley
//
//  A single moment in the relationship's Time Tree. Memories live in
//  Firestore at couples/{coupleId}/memories/{id} and are shared between
//  both partners. Capsule memories are written now but sealed until a
//  future unlock day, for both of you — only the existence + unlock
//  countdown is visible before then; the body and photo are revealed
//  together once the day arrives. This is the emotional engine of the
//  Time Tree.
//
//  A capsule is only kept out of sight IN THE APP: the document itself is
//  readable by both partners' clients. While it is sealed, only its author
//  may edit it (TimeTreeViewModel.canEdit), and the device cache stores it
//  without its note, emotions, attribution or photo. A letter that is truly
//  time-locked on the server is a Future Letter.
//

import Foundation
import FirebaseFirestore

// MARK: - Memory Kind

/// What category a memory belongs to. Drives icon, accent, and tree-bloom
/// behavior. Custom is the open-ended slot for "everything else."
enum MemoryKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case firstDate
    case firstKiss
    case firstTrip
    case firstGift
    case firstAnniversary
    case firstFightSolved
    case movingTogether
    case proposal
    case wedding
    case babyMilestone
    case custom

    var id: String { rawValue }

    /// User-facing name shown in the milestone picker and on memory cards, in
    /// the user's language. Display only: Firestore stores `rawValue`. A new
    /// memory's title starts as this name, and once saved it is the user's
    /// own text, in whatever language it was written.
    var displayName: String {
        switch self {
        case .firstDate:
            return String(localized: "First Date", comment: "Memory kind: the couple's first romantic date")
        case .firstKiss:
            return String(localized: "First Kiss", comment: "Memory kind")
        case .firstTrip:
            return String(localized: "First Trip", comment: "Memory kind: the first trip together")
        case .firstGift:
            return String(localized: "First Gift", comment: "Memory kind")
        case .firstAnniversary:
            return String(localized: "First Anniversary", comment: "Memory kind")
        case .firstFightSolved:
            return String(localized: "First Fight Solved", comment: "Memory kind: the first argument the couple resolved")
        case .movingTogether:
            return String(localized: "Moving Together", comment: "Memory kind: moving in together")
        case .proposal:
            return String(localized: "Proposal", comment: "Memory kind: marriage proposal")
        case .wedding:
            return String(localized: "Wedding", comment: "Memory kind")
        case .babyMilestone:
            return String(localized: "Baby Milestone", comment: "Memory kind: a milestone with a baby")
        case .custom:
            return String(localized: "Custom Moment", comment: "Memory kind: any other moment the couple names themselves")
        }
    }

    var emoji: String {
        switch self {
        case .firstDate:        return "💖"
        case .firstKiss:        return "💋"
        case .firstTrip:        return "✈️"
        case .firstGift:        return "🎁"
        case .firstAnniversary: return "🎂"
        case .firstFightSolved: return "🤝"
        case .movingTogether:   return "🏠"
        case .proposal:         return "💍"
        case .wedding:          return "👰"
        case .babyMilestone:    return "👶"
        case .custom:           return "✨"
        }
    }

    /// Short prompt that suggests how the user might describe this memory.
    /// Surfaced as a placeholder in the editor, not a hard requirement.
    var notePrompt: String {
        switch self {
        case .firstDate:
            return String(localized: "What made it feel like the start of something?",
                          comment: "Placeholder for the note of a First Date memory")
        case .firstKiss:
            return String(localized: "Where were you, and how did it feel?",
                          comment: "Placeholder for the note of a First Kiss memory")
        case .firstTrip:
            return String(localized: "The place you'll always associate with each other.",
                          comment: "Placeholder for the note of a First Trip memory")
        case .firstGift:
            return String(localized: "The gift that meant more than its size.",
                          comment: "Placeholder for the note of a First Gift memory")
        case .firstAnniversary:
            return String(localized: "How did you mark the year?",
                          comment: "Placeholder for the note of a First Anniversary memory")
        case .firstFightSolved:
            return String(localized: "What you both learned coming back together.",
                          comment: "Placeholder for the note of a First Fight Solved memory")
        case .movingTogether:
            return String(localized: "The first place you called \"ours.\"",
                          comment: "Placeholder for the note of a Moving Together memory")
        case .proposal:
            return String(localized: "The yes you'll never forget.",
                          comment: "Placeholder for the note of a Proposal memory")
        case .wedding:
            return String(localized: "The day you chose each other in front of the world.",
                          comment: "Placeholder for the note of a Wedding memory")
        case .babyMilestone:
            return String(localized: "The moment your family grew.",
                          comment: "Placeholder for the note of a Baby Milestone memory")
        case .custom:
            return String(localized: "Tell the story of this moment.",
                          comment: "Placeholder for the note of a custom memory")
        }
    }

    /// Default emotion tags we suggest when the user picks this preset.
    /// They can override these in the editor.
    var suggestedEmotions: [MemoryEmotion] {
        switch self {
        case .firstDate:        return [.nervous, .excited, .happy]
        case .firstKiss:        return [.nervous, .tender, .joyful]
        case .firstTrip:        return [.adventurous, .joyful, .loved]
        case .firstGift:        return [.grateful, .loved, .tender]
        case .firstAnniversary: return [.grateful, .happy, .hopeful]
        case .firstFightSolved: return [.grateful, .peaceful, .hopeful]
        case .movingTogether:   return [.hopeful, .peaceful, .loved]
        case .proposal:         return [.joyful, .hopeful, .loved]
        case .wedding:          return [.joyful, .loved, .grateful]
        case .babyMilestone:    return [.joyful, .grateful, .hopeful]
        case .custom:           return []
        }
    }

    /// Sort order in the milestone picker — chronological-ish, the order
    /// most couples experience these things in.
    var pickerOrder: Int {
        switch self {
        case .firstDate:        return 0
        case .firstKiss:        return 1
        case .firstGift:        return 2
        case .firstTrip:        return 3
        case .firstFightSolved: return 4
        case .firstAnniversary: return 5
        case .movingTogether:   return 6
        case .proposal:         return 7
        case .wedding:          return 8
        case .babyMilestone:    return 9
        case .custom:           return 10
        }
    }
}

// MARK: - Memory Emotion

/// Soft, non-judgmental emotion vocabulary. Limited set on purpose —
/// the design intent is "label this moment with a feeling," not "do a
/// full mood analysis." Ten options keeps the UI clean.
enum MemoryEmotion: String, Codable, CaseIterable, Identifiable, Hashable {
    case happy
    case nervous
    case excited
    case loved
    case grateful
    case hopeful
    case peaceful
    case joyful
    case adventurous
    case tender

    var id: String { rawValue }

    /// The feeling's name in the user's language. Display only: Firestore
    /// stores `rawValue`.
    var displayName: String {
        switch self {
        case .happy:        return String(localized: "Happy", comment: "Feeling tag on a memory")
        case .nervous:      return String(localized: "Nervous", comment: "Feeling tag on a memory")
        case .excited:      return String(localized: "Excited", comment: "Feeling tag on a memory")
        case .loved:        return String(localized: "Loved", comment: "Feeling tag on a memory: feeling loved")
        case .grateful:     return String(localized: "Grateful", comment: "Feeling tag on a memory")
        case .hopeful:      return String(localized: "Hopeful", comment: "Feeling tag on a memory")
        case .peaceful:     return String(localized: "Peaceful", comment: "Feeling tag on a memory")
        case .joyful:       return String(localized: "Joyful", comment: "Feeling tag on a memory")
        case .adventurous:  return String(localized: "Adventurous", comment: "Feeling tag on a memory")
        case .tender:       return String(localized: "Tender", comment: "Feeling tag on a memory: gentle, affectionate")
        }
    }

    var emoji: String {
        switch self {
        case .happy:        return "😊"
        case .nervous:      return "🦋"
        case .excited:      return "✨"
        case .loved:        return "💗"
        case .grateful:     return "🙏"
        case .hopeful:      return "🌅"
        case .peaceful:     return "🕊️"
        case .joyful:       return "🌟"
        case .adventurous:  return "🌍"
        case .tender:       return "🌸"
        }
    }
}

// MARK: - Time Memory

/// A persisted relationship moment. Stored at
/// `couples/{coupleId}/memories/{id}`.
///
/// `unlockDate` is the capsule mechanic: when non-nil and in the future,
/// the app keeps the body/photo of this memory out of sight for BOTH
/// partners until the unlock moment passes (9:00 local time on the chosen
/// day, `JourneyCalendarDay.capsuleUnlockMoment`; capsules sealed by earlier
/// versions open at whatever time of day they stored).
/// Once unlocked, the memory becomes a normal entry in the timeline. The
/// capsule countdown itself is always visible.
struct TimeMemory: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var firestoreId: String?
    var id: String
    var kind: MemoryKind
    var title: String
    var date: Date
    var note: String?
    var photoURL: String?
    var emotions: [MemoryEmotion]
    /// User-supplied attribution: "added by Sam," "from us both," etc.
    /// Free-form so couples can phrase it however they like.
    var attribution: String?
    /// Optional link to an Anniversary document so memories can reference
    /// "the day we met" countdowns. Soft link — survives if the
    /// anniversary is deleted.
    var anniversaryId: String?
    /// Capsule unlock date. nil = not a capsule. In the future = locked.
    /// In the past = unlocked (treated as a normal memory).
    var unlockDate: Date?
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date

    var documentId: String { firestoreId ?? id }

    /// True if this memory was authored as a capsule whose unlock has not
    /// yet arrived. Body and photo should be redacted in this state.
    func isLocked(at now: Date = Date()) -> Bool {
        guard let unlockDate else { return false }
        return unlockDate > now
    }

    /// True for capsule memories that have already become readable.
    /// Useful for drawing the one-time "unlocked" celebration treatment.
    func isUnlockedCapsule(at now: Date = Date()) -> Bool {
        guard let unlockDate else { return false }
        return unlockDate <= now
    }

    init(
        id: String = UUID().uuidString,
        kind: MemoryKind,
        title: String,
        date: Date,
        note: String? = nil,
        photoURL: String? = nil,
        emotions: [MemoryEmotion] = [],
        attribution: String? = nil,
        anniversaryId: String? = nil,
        unlockDate: Date? = nil,
        createdBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.date = date
        self.note = note
        self.photoURL = photoURL
        self.emotions = emotions
        self.attribution = attribution
        self.anniversaryId = anniversaryId
        self.unlockDate = unlockDate
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Date formatting helper

extension TimeMemory {
    func formattedDate(style: DateFormatter.Style = .long) -> String {
        let f = DateFormatter()
        f.dateStyle = style
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Days from unlock to now. Negative once unlocked.
    func daysUntilUnlock(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let unlockDate else { return nil }
        let target = calendar.startOfDay(for: unlockDate)
        let today  = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: target).day
    }
}
