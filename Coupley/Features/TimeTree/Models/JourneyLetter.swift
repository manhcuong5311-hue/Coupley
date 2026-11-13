//
//  JourneyLetter.swift
//  Coupley
//
//  The shared contract for the Journey tab (read-only for every package).
//
//  Journey shows future letters from BOTH partners in three places: the
//  Letters section, the Timeline and the tree. It never observes
//  FutureLetterViewModel. ContentView, which owns that view model and already
//  re-renders on every letters update, builds one `JourneyLetterFeed` value
//  in its body (`lettersViewModel.journeyFeed(partnerName:)`) and hands it to
//  TimeTreeView with closures: tapping a letter calls back to
//  `FutureLetterViewModel.show(_:)`, writing one to `compose(seed:opensAt:)`.
//
//  Envelopes only: nothing here can carry what a letter says. The body stays
//  time-locked on the server and only the reader fetches it, on tap.
//
//  Also here, because several packages need the same answer:
//    JourneyCalendarDay   start dates and capsule unlocks as calendar days
//    JourneyFocus         what a tapped Journey reminder should open
//    JourneyNotification  the userInfo keys those reminders carry
//    JourneyStyle         capsule gold that is readable as text
//    JourneyFont          BrandType's rungs as Dynamic Type text styles
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Direction

nonisolated enum JourneyLetterDirection: Equatable, CaseIterable {
    /// Written by the partner, for this user.
    case toMe
    /// Written by this user, for the partner.
    case fromMe
}

// MARK: - Letter

/// One envelope as Journey shows it.
struct JourneyLetter: Identifiable, Equatable {

    enum Stage: Equatable {
        /// Before `opensAt`: a future moment with a countdown.
        case sealed
        /// `opensAt` has passed and nobody has opened it yet.
        case ready
        /// Opened by its recipient: a keepsake.
        case opened
    }

    /// Hand it back through TimeTreeView's `onOpenLetter`, which calls
    /// `FutureLetterViewModel.show(_:)`.
    let envelope: FutureLetter
    /// From `FutureLetterViewModel.phase(of:)`, whose clock moves only at
    /// boundaries, so Journey and Home always agree on a letter's phase.
    let phase: FutureLetterPhase
    /// The seal is still a local write that has not reached the server.
    let isPending: Bool

    var id: String { envelope.id }

    var direction: JourneyLetterDirection {
        switch phase {
        case .sealedForMe, .readyForMe, .openedByMe:            return .toMe
        case .sealedByMe, .waitingForPartner, .openedByPartner: return .fromMe
        }
    }

    var stage: Stage {
        switch phase {
        case .sealedForMe, .sealedByMe:       return .sealed
        case .readyForMe, .waitingForPartner: return .ready
        case .openedByMe, .openedByPartner:   return .opened
        }
    }

    var opensAt: Date { envelope.opensAt }
    var openedAt: Date? { envelope.openedAt }
    var sealedAt: Date { envelope.sealedMoment }

    /// Where the letter sits in time: its opening moment while unopened, the
    /// moment it was opened once it is a keepsake.
    var timelineDate: Date { stage == .opened ? (openedAt ?? opensAt) : opensAt }

    // MARK: Copy (pass a TimelineView's date as `now` so text moves each minute)

    /// "Letter from Sam" or "Your letter to Sam".
    func title(partnerName: String) -> String {
        direction == .toMe ? "Letter from \(partnerName)" : "Your letter to \(partnerName)"
    }

    /// "Opens Thu, Dec 25 at 9:00 AM", "Ready to open",
    /// "Ready — Sam hasn't opened it yet", "Opened Nov 13", "Sam opened it Nov 13",
    /// or "Sending…" while the seal is still queued on this phone.
    func status(partnerName: String, now: Date) -> String {
        switch stage {
        case .sealed:
            if isPending { return "Sending…" }
            return "Opens \(FutureLetterClock.moment(opensAt, now: now))"
        case .ready:
            if direction == .toMe { return "Ready to open" }
            return isPending ? "Sending…" : "Ready — \(partnerName) hasn't opened it yet"
        case .opened:
            let day = FutureLetterClock.shortDate(openedAt ?? opensAt, now: now)
            return direction == .toMe ? "Opened \(day)" : "\(partnerName) opened it \(day)"
        }
    }

    /// "12 days", "5 hr", "42 min" while sealed; nil otherwise.
    func countdown(now: Date) -> String? {
        stage == .sealed ? FutureLetterClock.shortCountdown(to: opensAt, now: now) : nil
    }

    /// Title, status and countdown read as sentences, for one VoiceOver element.
    func spokenLabel(partnerName: String, now: Date) -> String {
        let sealedTitle = stage == .sealed && direction == .toMe
            ? "Sealed letter from \(partnerName)"
            : title(partnerName: partnerName)
        var parts = [sealedTitle, status(partnerName: partnerName, now: now)]
        if let countdown = countdown(now: now) { parts.append(countdown) }
        return parts
            .map { $0.hasSuffix(".") || $0.hasSuffix("…") ? $0 : $0 + "." }
            .joined(separator: " ")
    }

    /// The same glyphs as `FutureLetterRowContent`, so a letter looks the
    /// same on Home, in the hub and on Journey.
    var symbolName: String {
        switch stage {
        case .sealed: return "lock.fill"
        case .ready:  return "envelope.fill"
        case .opened: return "envelope.open.fill"
        }
    }

    /// Icon tint only, never text: gold sealed, amber when ready for me,
    /// the house green once opened.
    var tint: Color {
        switch phase {
        case .sealedForMe, .sealedByMe, .waitingForPartner: return FutureLetterStyle.gold
        case .readyForMe:                                   return FutureLetterStyle.accent
        case .openedByMe, .openedByPartner:                 return FutureLetterStyle.opened
        }
    }
}

// MARK: - Feed

/// Every letter between the two of you, both directions, as one value.
struct JourneyLetterFeed: Equatable {
    /// Sorted by `opensAt`, earliest first.
    var letters: [JourneyLetter]
    var partnerName: String
    /// False when unpaired (or on the demo session): every letter surface on
    /// Journey hides, and nothing offers to write one.
    var isAvailable: Bool
    /// False until the letters listener has answered once.
    var hasLoaded: Bool

    static func unavailable(partnerName: String = "your partner") -> JourneyLetterFeed {
        JourneyLetterFeed(letters: [], partnerName: partnerName, isAvailable: false, hasLoaded: true)
    }

    func letter(id: String) -> JourneyLetter? { letters.first { $0.id == id } }

    func letters(_ direction: JourneyLetterDirection) -> [JourneyLetter] {
        letters.filter { $0.direction == direction }
    }

    /// Not opened yet, both directions: ready for me, then waiting for the
    /// partner, then sealed, each group soonest first.
    var unopened: [JourneyLetter] {
        let ready = letters.filter { $0.stage == .ready }
        return ready.filter { $0.direction == .toMe }
            + ready.filter { $0.direction == .fromMe }
            + letters.filter { $0.stage == .sealed }
    }

    /// Opened letters, most recently opened first.
    var keepsakes: [JourneyLetter] {
        letters
            .filter { $0.stage == .opened }
            .sorted { ($0.openedAt ?? $0.opensAt) > ($1.openedAt ?? $1.opensAt) }
    }

    /// The one letter a direction's summary shows: the earliest ready one,
    /// else the soonest sealed, else the most recently opened.
    func headline(_ direction: JourneyLetterDirection) -> JourneyLetter? {
        let mine = letters(direction)
        if let ready = mine.first(where: { $0.stage == .ready }) { return ready }
        if let sealed = mine.first(where: { $0.stage == .sealed }) { return sealed }
        return keepsakes.first { $0.direction == direction }
    }

    /// Start-of-day dates on which a still-sealed letter opens, for one
    /// direction. Journey's anniversary row uses them for "Your letter opens
    /// that day" and "A letter for you opens that day".
    func sealedOpeningDays(_ direction: JourneyLetterDirection,
                           calendar: Calendar = .current) -> Set<Date> {
        Set(letters(direction)
            .filter { $0.stage == .sealed }
            .map { calendar.startOfDay(for: $0.opensAt) })
    }

    /// What the tree draws: unopened letters as envelopes (ready first, then
    /// soonest), at most `maxEnvelopesPerSide` per direction, and the most
    /// recently opened letters as blossoms, at most `maxBlossoms`.
    func treeOrnaments(maxEnvelopesPerSide: Int = 3, maxBlossoms: Int = 8) -> [JourneyTreeOrnament] {
        var result: [JourneyTreeOrnament] = []
        for direction in JourneyLetterDirection.allCases {
            let hanging = letters(direction)
                .filter { $0.stage != .opened }
                .sorted { ($0.stage == .ready ? 0 : 1, $0.opensAt) < ($1.stage == .ready ? 0 : 1, $1.opensAt) }
                .prefix(max(0, maxEnvelopesPerSide))
            result += hanging.map { letter in
                JourneyTreeOrnament(id: letter.id,
                                    kind: letter.stage == .ready ? .readyEnvelope : .sealedEnvelope,
                                    direction: direction,
                                    seed: JourneyTreeOrnament.stableSeed(letter.id))
            }
        }
        result += keepsakes.prefix(max(0, maxBlossoms)).map { letter in
            JourneyTreeOrnament(id: letter.id,
                                kind: .blossom,
                                direction: letter.direction,
                                seed: JourneyTreeOrnament.stableSeed(letter.id))
        }
        return result
    }
}

extension FutureLetterViewModel {
    /// Journey's whole view of the letters. Call it in ContentView's body.
    func journeyFeed(partnerName: String) -> JourneyLetterFeed {
        guard isAvailable else { return .unavailable(partnerName: partnerName) }
        return JourneyLetterFeed(
            letters: letters.map { JourneyLetter(envelope: $0, phase: phase(of: $0), isPending: isPending($0)) },
            partnerName: partnerName,
            isAvailable: true,
            hasLoaded: hasLoaded
        )
    }
}

// MARK: - Tree ornament

/// A letter as the tree draws it.
nonisolated struct JourneyTreeOrnament: Identifiable, Equatable {

    nonisolated enum Kind: Equatable {
        /// Still sealed: a small wax-sealed envelope hanging from a branch.
        case sealedEnvelope
        /// Its moment has come and nobody has opened it: the same envelope,
        /// softly lit.
        case readyEnvelope
        /// Opened: a blossom on the canopy.
        case blossom
    }

    /// The letter's id. The tree hands it back when the ornament is tapped.
    let id: String
    let kind: Kind
    /// The partner's letters hang on the left of the trunk, this user's on
    /// the right.
    let direction: JourneyLetterDirection
    /// Stable for a given letter across launches and devices, so a new
    /// letter never moves the others. Derive positions from it, never from
    /// an index in the list.
    let seed: UInt64

    /// 64-bit FNV-1a. Not `hashValue`, which changes on every launch.
    static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

// MARK: - Calendar days

/// A start date and a capsule's unlock are days, not instants.
///
/// A start date used to be stored as the exact instant the picker held, and
/// every count took that instant's day in the VIEWER's time zone, so partners
/// far apart counted different days. It is now stored as 10:00 UTC of the
/// picked GREGORIAN year/month/day and read back as that date.
///
/// Why 10:00 UTC: versions 1.1 and 1.2 still read the raw instant's LOCAL
/// day, and 10:00 UTC falls on the picked date from UTC-10 to UTC+13:59, so
/// an old partner reads the same day everywhere except UTC-11 (American
/// Samoa, Niue) and UTC+14 (Kiritimati). Noon UTC would put all of New
/// Zealand, Fiji, Tonga and Samoa a day late.
///
/// Why Gregorian: the phone's calendar can be Buddhist (Thailand), Persian
/// (Iran) or Umm al-Qura (Saudi Arabia). Taking the year from it would store
/// 2569 for a Thai 2026 (see Core/DayKey.swift for the same rule).
///
/// Values written before this change (any other time of day) keep naming
/// the viewer's local day, exactly as they always did.
nonisolated enum JourneyCalendarDay {

    /// 9:00 in the morning: when every Journey reminder fires and when a
    /// capsule opens. Same hour as `FutureLetterSchedule.defaultHour`.
    static let reminderHour = 9

    /// The UTC hour a calendar-day value is stored at.
    private static let storedHourUTC = 10

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Gregorian, in `calendar`'s time zone: a stored day always names a
    /// Gregorian year/month/day, whatever calendar the phone shows. Year
    /// steps (anniversaries, year crowns) use it too: an Umm al-Qura year
    /// is 11 days shorter, so the phone's own calendar would put "1 year"
    /// on a different day than the partner's. Same day boundaries as
    /// `calendar`, so day counts don't change.
    static func gregorian(in calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// What to store for a start date the user picked: 10:00 UTC of that
    /// day's Gregorian year/month/day in `calendar`'s time zone.
    static func storedMoment(forLocalDay day: Date, calendar: Calendar = .current) -> Date {
        let picked = gregorian(in: calendar).dateComponents([.year, .month, .day], from: day)
        var marker = DateComponents()
        marker.year = picked.year
        marker.month = picked.month
        marker.day = picked.day
        marker.hour = storedHourUTC
        return utc.date(from: marker) ?? day
    }

    /// True for a value written by `storedMoment(forLocalDay:)`.
    static func isStoredCalendarDay(_ stored: Date) -> Bool {
        let parts = utc.dateComponents([.hour, .minute, .second, .nanosecond], from: stored)
        return parts.hour == storedHourUTC && parts.minute == 0 && parts.second == 0
            && (parts.nanosecond ?? 0) < 1_000_000
    }

    /// The day a stored start date names, as the start of that day in
    /// `calendar`. Every day count, anniversary and crown is computed from
    /// this, never from the raw stored value.
    static func localDay(ofStored stored: Date, calendar: Calendar = .current) -> Date {
        guard isStoredCalendarDay(stored) else { return calendar.startOfDay(for: stored) }
        let named = utc.dateComponents([.year, .month, .day], from: stored)
        var local = DateComponents()
        local.year = named.year
        local.month = named.month
        local.day = named.day
        guard let date = gregorian(in: calendar).date(from: local) else {
            return calendar.startOfDay(for: stored)
        }
        return calendar.startOfDay(for: date)
    }

    /// When a capsule sealed until `day` opens: 9:00 that morning, the same
    /// moment its reminder fires.
    static func capsuleUnlockMoment(forLocalDay day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: start) ?? start
    }
}

// MARK: - Reminders → Journey

/// The userInfo every Journey reminder carries. TimeTreeNotificationScheduler
/// writes it; NotificationViewModel reads it back through `JourneyFocus`.
nonisolated enum JourneyNotification {
    static let typeKey = "type"
    static let capsuleType = "timeTreeCapsule"
    static let crownType = "timeTreeCrown"
    static let memoryIdKey = "memoryId"
    static let milestoneIdKey = "milestoneId"
    /// Local notifications have no `aps`; NotificationViewModel reads the
    /// text of its in-app list from this key.
    static let bodyKey = "body"
    static let threadIdentifier = "coupley-journey"
}

/// What Journey should open when it is brought forward by a reminder.
/// ContentView owns it as `@State`, selects the Journey tab and passes a
/// Binding to TimeTreeView, which handles it and sets it back to nil.
nonisolated enum JourneyFocus: Equatable {
    /// Just show Journey.
    case overview
    /// Open this memory's detail: a capsule that has just opened.
    case capsule(memoryId: String)
    /// Replay this crown's celebration.
    case crown(milestoneId: String)

    /// Reads a reminder's own userInfo (not NotificationService's wrapper,
    /// which nests it under "userInfo"). Nil for anything that is not a
    /// Journey reminder.
    init?(notificationUserInfo info: [AnyHashable: Any]) {
        guard let type = info[JourneyNotification.typeKey] as? String else { return nil }
        switch type {
        case JourneyNotification.capsuleType:
            if let id = info[JourneyNotification.memoryIdKey] as? String, !id.isEmpty {
                self = .capsule(memoryId: id)
            } else {
                self = .overview
            }
        case JourneyNotification.crownType:
            if let id = info[JourneyNotification.milestoneIdKey] as? String, !id.isEmpty {
                self = .crown(milestoneId: id)
            } else {
                self = .overview
            }
        default:
            return nil
        }
    }
}

// MARK: - Style

enum JourneyStyle {
    /// Capsule gold for TEXT (countdowns, "Capsule opened", capsule labels).
    /// `FutureLetterStyle.gold` stays an icon colour: as text it measures
    /// 1.1–1.4:1 on the Light palettes. This light variant measures at least
    /// 4.7:1 on every Light surface (page, card, chip, hero fill); the dark
    /// one at least 8:1 on every Dark surface.
    static let goldText = Color.adaptive(
        dark: UIColor(red: 1.00, green: 0.78, blue: 0.30, alpha: 1),
        light: UIColor(red: 0.50, green: 0.32, blue: 0.04, alpha: 1)
    )
}

// MARK: - Type

/// BrandType's rungs as Dynamic Type text styles: the same sizes at the
/// default text size, and they grow with the user's setting. Journey uses
/// these instead of BrandType (fixed points) and `.system(size:)`.
enum JourneyFont {
    /// 34, the masthead (BrandType.display).
    static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    /// 34, the hero's day count.
    static let number = Font.system(.largeTitle, design: .rounded, weight: .bold)
    /// 17, section titles and memory titles (BrandType.title).
    static let title = Font.system(.headline, design: .rounded, weight: .semibold)
    /// 13, row titles and buttons (BrandType.label).
    static let label = Font.system(.footnote, design: .rounded, weight: .semibold)
    /// 13, running text (BrandType.body).
    static let body = Font.system(.footnote, design: .rounded)
    /// 12, chips and secondary lines.
    static let caption = Font.system(.caption, design: .rounded, weight: .medium)
    /// 11, dates and footnotes (BrandType.meta).
    static let meta = Font.system(.caption2, design: .rounded, weight: .medium)
}
