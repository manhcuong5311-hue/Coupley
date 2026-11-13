//
//  WidgetCountdownEngine.swift
//  Coupley
//
//  Pure logic for "days together", "next anniversary", and milestone
//  highlighting. No SwiftUI, no Foundation date pickers — just calendar
//  math so every code path is unit-testable.
//

import Foundation

// MARK: - Highlight

/// What the anniversary block decides to surface on screen. The widget
/// view picks layout + accent color from this enum — never reads the raw
/// date again.
enum WidgetAnniversaryHighlight: Equatable {

    /// User hasn't set any anniversary yet — empty state.
    case empty

    /// A milestone is happening *today* or imminently (within
    /// `MilestoneEngine.imminenceWindow` days). Drives the celebratory
    /// "100 Days Together" / "1 Year Anniversary" hero treatment.
    case milestone(Milestone, daysAway: Int, daysTogether: Int)

    /// A regular anniversary is coming up. Drives the calmer "Next
    /// anniversary in N days" treatment.
    case upcomingAnniversary(title: String, daysAway: Int, daysTogether: Int)

    /// No close milestone, no scheduled anniversary — fall back to the
    /// running total. Always available once `relationshipStart` is set.
    case daysTogether(Int)
}

// MARK: - Milestone

/// A specific landmark on the relationship timeline. We highlight it when
/// the actual *day count* matches one of these values (within the
/// imminence window, both sides).
///
/// The title is a resource, resolved in the reader's language when the
/// widget draws it (`String(localized: milestone.title)`). Each title is its
/// own whole phrase, so a translator can word every landmark freely.
struct Milestone: Equatable, Hashable {
    let dayCount: Int
    let title: LocalizedStringResource
    let isMajor: Bool

    /// `dayCount` identifies a milestone (the resource is not Hashable).
    func hash(into hasher: inout Hasher) {
        hasher.combine(dayCount)
        hasher.combine(isMajor)
    }

    /// All recognised milestones. Ordered ascending so the engine can
    /// binary-search for the next-up landmark.
    static let all: [Milestone] = [
        Milestone(dayCount: 30,
                  title: LocalizedStringResource("1 Month Together", comment: "Widget milestone: 30 days as a couple"),
                  isMajor: false),
        Milestone(dayCount: 100,
                  title: LocalizedStringResource("100 Days Together", comment: "Widget milestone: 100 days as a couple"),
                  isMajor: true),
        Milestone(dayCount: 200,
                  title: LocalizedStringResource("200 Days Together", comment: "Widget milestone: 200 days as a couple"),
                  isMajor: false),
        Milestone(dayCount: 365,
                  title: LocalizedStringResource("1 Year Anniversary", comment: "Widget milestone: first anniversary"),
                  isMajor: true),
        Milestone(dayCount: 500,
                  title: LocalizedStringResource("500 Days of Love", comment: "Widget milestone: 500 days as a couple"),
                  isMajor: true),
        Milestone(dayCount: 730,
                  title: LocalizedStringResource("2 Year Anniversary", comment: "Widget milestone: second anniversary"),
                  isMajor: true),
        Milestone(dayCount: 1000,
                  title: LocalizedStringResource("1000 Days of Love", comment: "Widget milestone: 1000 days as a couple"),
                  isMajor: true),
        Milestone(dayCount: 1095,
                  title: LocalizedStringResource("3 Year Anniversary", comment: "Widget milestone: third anniversary"),
                  isMajor: true),
        Milestone(dayCount: 1460,
                  title: LocalizedStringResource("4 Year Anniversary", comment: "Widget milestone: fourth anniversary"),
                  isMajor: true),
        Milestone(dayCount: 1825,
                  title: LocalizedStringResource("5 Year Anniversary", comment: "Widget milestone: fifth anniversary"),
                  isMajor: true),
        Milestone(dayCount: 2555,
                  title: LocalizedStringResource("7 Year Anniversary", comment: "Widget milestone: seventh anniversary"),
                  isMajor: true),
        Milestone(dayCount: 3650,
                  title: LocalizedStringResource("10 Years of Love", comment: "Widget milestone: tenth anniversary"),
                  isMajor: true),
    ]
}

// MARK: - Countdown Engine

enum WidgetCountdownEngine {

    /// How close (in days) a milestone has to be to "win" over a regular
    /// anniversary. Past-recent ones inside this window also win — so the
    /// "100 Days Together" treatment lingers for a few days after the
    /// actual milestone, which is the warmer behaviour.
    static let imminenceWindow = 7

    // MARK: - Public

    /// Computes the headline highlight from a snapshot. `now` is parameterised
    /// for testability and so the timeline provider can pre-compute future
    /// entries.
    static func highlight(
        from snapshot: AnniversarySnapshot?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetAnniversaryHighlight {

        guard let snapshot, let start = snapshot.relationshipStart else {
            return .empty
        }

        let daysTogether = days(from: start, to: now, calendar: calendar)

        // 1. Imminent milestone wins (future or just-passed within window).
        if let imminent = nearestMilestone(forDays: daysTogether) {
            return .milestone(
                imminent.milestone,
                daysAway: imminent.daysAway,
                daysTogether: max(0, daysTogether)
            )
        }

        // 2. Otherwise look for the next named anniversary the user added.
        if let next = nextAnniversary(in: snapshot.upcoming, now: now, calendar: calendar) {
            return .upcomingAnniversary(
                title: next.title,
                daysAway: next.daysAway,
                daysTogether: max(0, daysTogether)
            )
        }

        // 3. Fallback — running total.
        return .daysTogether(max(0, daysTogether))
    }

    // MARK: - Days Together

    /// Number of full calendar days from `start` up to and including `now`.
    /// Negative when the relationship-start date is in the future (treat as 0
    /// at the call site).
    static func days(
        from start: Date,
        to now: Date,
        calendar: Calendar = .current
    ) -> Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: s, to: e).day ?? 0
    }

    /// Days between `now` and `target`. Positive = future, negative = past.
    static func daysBetween(
        now: Date,
        target: Date,
        calendar: Calendar = .current
    ) -> Int {
        let n = calendar.startOfDay(for: now)
        let t = calendar.startOfDay(for: target)
        return calendar.dateComponents([.day], from: n, to: t).day ?? 0
    }

    // MARK: - Milestone Lookup

    private struct ImminentMilestone {
        let milestone: Milestone
        let daysAway: Int
    }

    /// Returns the milestone that should hijack the display, if any.
    /// Picks the nearest milestone whose absolute distance from
    /// `daysTogether` is within `imminenceWindow`. Future imminence is
    /// preferred over past-recent — "5 days to 100 Days Together" outranks
    /// "yesterday was 30 days".
    private static func nearestMilestone(forDays daysTogether: Int) -> ImminentMilestone? {
        guard daysTogether >= 0 else { return nil }

        var bestFuture: ImminentMilestone?
        var bestPast: ImminentMilestone?

        for m in Milestone.all {
            let distance = m.dayCount - daysTogether
            guard abs(distance) <= imminenceWindow else { continue }

            if distance >= 0 {
                if bestFuture == nil || distance < bestFuture!.daysAway {
                    bestFuture = ImminentMilestone(milestone: m, daysAway: distance)
                }
            } else {
                if bestPast == nil || (-distance) < (-bestPast!.daysAway) {
                    bestPast = ImminentMilestone(milestone: m, daysAway: distance)
                }
            }
        }

        return bestFuture ?? bestPast
    }

    // MARK: - Next Named Anniversary

    private struct NextAnniversary {
        let title: String
        let daysAway: Int
    }

    private static func nextAnniversary(
        in upcoming: [UpcomingAnniversary],
        now: Date,
        calendar: Calendar
    ) -> NextAnniversary? {
        // Pick the soonest future-or-today entry.
        let candidates = upcoming
            .map { (item: $0, daysAway: daysBetween(now: now, target: $0.date, calendar: calendar)) }
            .filter { $0.daysAway >= 0 }
            .sorted { $0.daysAway < $1.daysAway }

        guard let first = candidates.first else { return nil }
        return NextAnniversary(title: first.item.title, daysAway: first.daysAway)
    }
}

// MARK: - Display Helpers
//
// Every string here is resolved with String(localized:) in whichever process
// draws it (the widget extension, normally); both targets carry the same
// catalog. Anniversary titles arrive already in the user's language: the app
// localizes them when it writes the snapshot, or the user typed them.

extension WidgetAnniversaryHighlight {

    /// Compact one-line caption for a small widget surface.
    var compactCaption: String {
        switch self {
        case .empty:
            return String(localized: "Start your love journey",
                          comment: "Widget: shown before the couple has set the date they got together")
        case .milestone(let m, let daysAway, _):
            let title = String(localized: m.title)
            if daysAway == 0 { return title }
            if daysAway > 0 {
                return String(localized: "\(daysAway)d to \(title)",
                              comment: "Compact widget caption: days left until a milestone, e.g. '5d to 100 Days Together'. 'd' abbreviates days.")
            }
            return String(localized: "\(title) · \(-daysAway)d ago",
                          comment: "Compact widget caption: a milestone a few days ago, e.g. '100 Days Together · 2d ago'. 'd' abbreviates days.")
        case .upcomingAnniversary(let title, let daysAway, _):
            if daysAway == 0 {
                return String(localized: "\(title) — today",
                              comment: "Compact widget caption: an anniversary (its title) is today")
            }
            if daysAway == 1 {
                return String(localized: "\(title) tomorrow",
                              comment: "Compact widget caption: an anniversary (its title) is tomorrow")
            }
            return String(localized: "\(title) in \(daysAway)d",
                          comment: "Compact widget caption: an anniversary (its title) in N days. 'd' abbreviates days.")
        case .daysTogether(let days):
            return String(localized: "Together \(days) Days",
                          comment: "Compact widget caption: how many days the couple has been together")
        }
    }

    /// Hero number used in the widget. Returns the number itself; it is
    /// drawn as part of `heroPhrase`.
    var heroNumber: Int {
        switch self {
        case .empty:                                return 0
        case .milestone(_, let daysAway, _):        return abs(daysAway)
        case .upcomingAnniversary(_, let daysAway, _): return daysAway
        case .daysTogether(let days):               return days
        }
    }

    /// The hero line as ONE localized phrase ("12 Days", "12 天", "12 дней"),
    /// so the unit agrees with the number in every language and the
    /// translator decides the word order. The number's run carries a
    /// `replacementIndex` attribute; the view draws that run large and the
    /// rest as the unit. Empty for `.empty`, which shows no hero line.
    var heroPhrase: AttributedString {
        if case .empty = self { return AttributedString() }
        var options = AttributedString.LocalizationOptions()
        options.applyReplacementIndexAttribute = true
        let n = heroNumber
        return n == 1
            ? AttributedString(localized: "\(n) Day", options: options,
                               comment: "Widget hero line: one day (a countdown or days together). The number is drawn large, the word small.")
            : AttributedString(localized: "\(n) Days", options: options,
                               comment: "Widget hero line: a number of days (a countdown or days together). The number is drawn large, the word small.")
    }

    /// The line above the hero number (the view shows it in capitals).
    var topline: String {
        switch self {
        case .empty:
            return String(localized: "Together", comment: "Widget: label above the day count before a start date is set")
        case .milestone(_, let daysAway, _):
            if daysAway == 0 {
                return String(localized: "Today", comment: "Widget: label above the day count, a milestone is today")
            }
            if daysAway > 0 {
                return String(localized: "Coming up", comment: "Widget: label above a countdown to a milestone")
            }
            return String(localized: "Just celebrated", comment: "Widget: label above the days since a milestone that just passed")
        case .upcomingAnniversary:
            return String(localized: "Next Anniversary", comment: "Widget: label above a countdown to the next anniversary")
        case .daysTogether:
            return String(localized: "Together For", comment: "Widget: label above the number of days together, e.g. TOGETHER FOR / 358 Days / of love")
        }
    }

    /// The line below the hero number.
    var subline: String {
        switch self {
        case .empty:
            return String(localized: "Set your start date ❤️",
                          comment: "Widget: asks the couple to set the date they got together, in the app")
        case .milestone(let m, let daysAway, _):
            let title = String(localized: m.title)
            if daysAway == 0 {
                return String(localized: "\(title) 🎉",
                              comment: "Widget: a milestone's title on the day itself, with a party emoji")
            }
            return title
        case .upcomingAnniversary(let title, _, _):
            return title
        case .daysTogether:
            return String(localized: "of love",
                          comment: "Widget: words under the days-together count, e.g. TOGETHER FOR / 358 Days / of love")
        }
    }

    /// Drives the warm vs. neutral accent in the view layer.
    var isCelebratory: Bool {
        switch self {
        case .milestone(let m, let daysAway, _):
            return m.isMajor && abs(daysAway) <= WidgetCountdownEngine.imminenceWindow
        default:
            return false
        }
    }
}

// MARK: - Refresh Cadence

extension WidgetCountdownEngine {

    /// When should the widget timeline reload after rendering at `now`?
    /// We aim for the next significant boundary (next midnight) so the
    /// "days together" number rolls over naturally — but no later than
    /// 6 hours from now so we eventually pick up new mood/nudge data
    /// even when the main app isn't relaunched.
    static func nextRefreshDate(after now: Date, calendar: Calendar = .current) -> Date {
        let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60 * 60 * 6)

        let cap = now.addingTimeInterval(60 * 60 * 6)
        return min(nextMidnight, cap)
    }
}
