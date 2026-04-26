//
//  TimeMemory.swift
//  Coupley
//
//  A single moment in the relationship's Time Tree. Memories live in
//  Firestore at couples/{coupleId}/memories/{id} and are shared between
//  both partners. Capsule memories are written now but locked until a
//  future unlock date — only the existence + unlock countdown is visible
//  before then; the body and photo are revealed together once the date
//  arrives. This is the emotional engine of the Time Tree.
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

    /// User-facing name shown in the milestone picker and on memory cards.
    var displayName: String {
        switch self {
        case .firstDate:        return "First Date"
        case .firstKiss:        return "First Kiss"
        case .firstTrip:        return "First Trip"
        case .firstGift:        return "First Gift"
        case .firstAnniversary: return "First Anniversary"
        case .firstFightSolved: return "First Fight Solved"
        case .movingTogether:   return "Moving Together"
        case .proposal:         return "Proposal"
        case .wedding:          return "Wedding"
        case .babyMilestone:    return "Baby Milestone"
        case .custom:           return "Custom Moment"
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
        case .firstDate:        return "What made it feel like the start of something?"
        case .firstKiss:        return "Where were you, and how did it feel?"
        case .firstTrip:        return "The place you'll always associate with each other."
        case .firstGift:        return "The gift that meant more than its size."
        case .firstAnniversary: return "How did you mark the year?"
        case .firstFightSolved: return "What you both learned coming back together."
        case .movingTogether:   return "The first place you called \"ours.\""
        case .proposal:         return "The yes you'll never forget."
        case .wedding:          return "The day you chose each other in front of the world."
        case .babyMilestone:    return "The moment your family grew."
        case .custom:           return "Tell the story of this moment."
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

    var displayName: String {
        switch self {
        case .happy:        return "Happy"
        case .nervous:      return "Nervous"
        case .excited:      return "Excited"
        case .loved:        return "Loved"
        case .grateful:     return "Grateful"
        case .hopeful:      return "Hopeful"
        case .peaceful:     return "Peaceful"
        case .joyful:       return "Joyful"
        case .adventurous:  return "Adventurous"
        case .tender:       return "Tender"
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
/// the body/photo of this memory is hidden from BOTH partners until the
/// unlock date passes. Once unlocked, the memory becomes a normal entry
/// in the timeline. The capsule countdown itself is always visible.
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
