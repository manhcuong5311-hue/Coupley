//
//  GardenCopy.swift
//  Coupley
//
//  Every garden status line, CTA title, after-watering line, request and
//  notice line, journal entry, Home line and VoiceOver label (spec B3, B4,
//  B7, B8). Pure and nonisolated: it reads only the contract's values. The
//  few functions that format a moment ("today at 9:14 PM") are main-actor
//  isolated, because FutureLetterClock, the app's moment formatter, is.
//
//  Localization: every sentence is String(localized:comment:), a whole
//  sentence or one format with placeholders, never joined from fragments.
//  Titles are shown through GardenTree.displayTitle /
//  GardenPreset.displayTitle(stored:), never the stored base-language text,
//  so callers pass display titles in.
//

import Foundation

nonisolated enum GardenCopy {

    // MARK: - Days

    /// "12 March 2023" in the reader's locale, for a stored calendar day
    /// (read through JourneyCalendarDay, never from the raw instant).
    static func longDay(stored: Date) -> String {
        JourneyCalendarDay.localDay(ofStored: stored)
            .formatted(.dateTime.day().month(.wide).year())
    }

    /// "26 Jan 2026" in the reader's locale, for a stored calendar day.
    static func shortDay(stored: Date) -> String {
        JourneyCalendarDay.localDay(ofStored: stored)
            .formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "12 March", for "Keep 12 March".
    static func dayAndMonth(stored: Date) -> String {
        JourneyCalendarDay.localDay(ofStored: stored)
            .formatted(.dateTime.day().month(.wide))
    }

    /// "14 Nov 2026" for a server instant (a planting, an agreement).
    static func shortDate(_ instant: Date) -> String {
        instant.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "9:14 PM".
    static func time(_ instant: Date, in timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return instant.formatted(style)
    }

    // MARK: - Hero status (B3 row 2)

    /// The status well's line. Garden-level: every input is the garden's,
    /// none is the selected page's, so swiping never changes it. Rows are
    /// tried top to bottom as in the B3 table. nil only where the garden
    /// shows no status at all (unpaired, the pre-garden Journey).
    @MainActor
    static func statusLine(availability: GardenAvailability, timeline: GardenWaterTimeline,
                           state: GardenWaterState, myWateringPendingTooLong: Bool,
                           partnerName: String, now: Date) -> String? {
        switch availability {
        case .unpaired, .disabledRemotely:
            return nil
        case .loading:
            return String(localized: "Checking the garden…",
                          comment: "Garden status while the garden is loading")
        case .unavailable(.neverOnline):
            return String(localized: "Connect once to start your garden.",
                          comment: "Garden status on a first launch that has never been online")
        case .unavailable:
            return String(localized: "The garden isn't available right now. Your trees are fine.",
                          comment: "Garden status when the garden can't be reached")
        case .ready:
            break
        }
        guard let latest = timeline.latest?.wateredAt else {
            return String(localized: "Not watered yet", comment: "Garden status before the first watering")
        }
        if myWateringPendingTooLong {
            return String(localized: "Watering… it reaches \(partnerName) when you're back online",
                          comment: "Garden status while your watering waits for a connection; the placeholder is the partner's name")
        }
        let mine = timeline.mineLastAt, theirs = timeline.partnerLastAt
        if timeline.isTogether, let mine, let theirs {
            let later = max(mine, theirs)
            if now.timeIntervalSince(later) < GardenCadence.noteInHeroFor {
                let moment = FutureLetterClock.moment(later, now: now)
                return String(localized: "Watered together · \(moment)",
                              comment: "Garden status after both partners watered within a day; the placeholder is like 'today at 11:02 PM'")
            }
        }
        if let mine, now.timeIntervalSince(mine) < GardenCadence.cooldown, (theirs ?? .distantPast) < mine {
            let moment = FutureLetterClock.moment(mine, now: now)
            return String(localized: "You watered \(moment)",
                          comment: "Garden status after you watered; the placeholder is like 'today at 9:14 PM'")
        }
        if let theirs, now.timeIntervalSince(theirs) < GardenCadence.waterBackWindow, (mine ?? .distantPast) < theirs {
            let moment = FutureLetterClock.moment(theirs, now: now)
            return String(localized: "\(partnerName) watered \(moment)",
                          comment: "Garden status after the partner watered; placeholders: the partner's name, then a moment like 'today at 9:14 PM'")
        }
        let moment = FutureLetterClock.moment(latest, now: now)
        switch state {
        case .fresh, .neverWatered:
            if let partnerLast = timeline.partnerLast, partnerLast.id == timeline.latest?.id {
                return String(localized: "Watered by \(partnerName) · \(moment)",
                              comment: "Garden status: watered recently by the partner; placeholders: the partner's name, then a moment like 'Wed, Nov 12 at 9:14 PM'")
            }
            return String(localized: "Watered by you · \(moment)",
                          comment: "Garden status: watered recently by you; the placeholder is a moment like 'Wed, Nov 12 at 9:14 PM'")
        case .ready:
            return String(localized: "Ready for water · last drink \(moment)",
                          comment: "Garden status two days after the last watering; the placeholder is a moment like 'Tue at 9:14 PM'")
        case .thirsty:
            return String(localized: "A little thirsty · last drink \(moment)",
                          comment: "Garden status three days after the last watering; the placeholder is a moment like 'Sun at 9:14 PM'")
        case .resting:
            return String(localized: "Resting · a little water wakes it up",
                          comment: "Garden status a week after the last watering")
        }
    }

    /// "Sam · today at 9:14 PM", under the partner's note in the status well.
    @MainActor
    static func noteAttribution(name: String, at: Date, now: Date) -> String {
        let moment = FutureLetterClock.moment(at, now: now)
        return String(localized: "\(name) · \(moment)",
                      comment: "Who left a watering note and when; placeholders: a name, then a moment like 'today at 9:14 PM'")
    }

    /// A note shown in quotes.
    static func quoted(_ text: String) -> String {
        String(localized: "“\(text)”", comment: "A watering or seed note shown in quotes; the placeholder is the note")
    }

    // MARK: - Water control (B3 row 3)

    /// The water control's label; nil when no control shows.
    static func waterTitle(_ action: GardenWaterAction, treeCount: Int) -> String? {
        switch action {
        case .none, .locked:
            return nil
        case .firstWater:
            return String(localized: "Give it its first water", comment: "Garden button for the garden's very first watering")
        case .waterBack:
            return String(localized: "Water back", comment: "Garden button after the partner watered and you have not yet")
        case .waterDue:
            if treeCount <= 1 {
                return String(localized: "Water your tree", comment: "Garden button when the one tree needs water")
            }
            return String(localized: "Water all \(treeCount) trees",
                          comment: "Garden button when the garden needs water; the placeholder is the number of trees (2 to 8)")
        case .waterOptional:
            return String(localized: "Water now", comment: "Garden button to water before it is needed")
        }
    }

    /// The line that replaces the water control for 4 seconds after a tap.
    /// Never says a push was sent; a partner on a legacy build is not
    /// promised to see it.
    static func afterWatering(treeCount: Int, partnerName: String, partnerCanGarden: Bool?) -> String {
        let partnerSees = partnerCanGarden != false
        switch (treeCount <= 1, partnerSees) {
        case (true, true):
            return String(localized: "Watered. \(partnerName) will see it on Journey.",
                          comment: "Shown after watering the one tree; the placeholder is the partner's name")
        case (false, true):
            return String(localized: "Watered all \(treeCount) trees. \(partnerName) will see it on Journey.",
                          comment: "Shown after watering; placeholders: the number of trees, then the partner's name")
        case (true, false):
            return String(localized: "Watered.", comment: "Shown after watering the one tree when the partner's app is out of date")
        case (false, false):
            return String(localized: "Watered all \(treeCount) trees.",
                          comment: "Shown after watering when the partner's app is out of date; the placeholder is the number of trees")
        }
    }

    static var addNote: String {
        String(localized: "Add a note", comment: "Garden: the pencil button beside the water control")
    }

    // MARK: - Hero meta (B3 row 4) and the planting hero (B3.2–B3.5)

    /// "Since 26 Jan 2026"; the Edit link sits beside it.
    static func since(storedStartDay: Date) -> String {
        let day = shortDay(stored: storedStartDay)
        return String(localized: "Since \(day)", comment: "Journey hero: when the start date is; the placeholder is a day like 26 Jan 2026")
    }

    static var editStartDate: String {
        String(localized: "Edit", comment: "Journey hero: link beside 'Since 26 Jan 2026' to suggest a new start date")
    }

    static var newDateSuggested: String {
        String(localized: "New date suggested",
               comment: "Journey hero: link beside 'Since 26 Jan 2026' while a suggested start date waits, yours or the partner's; it opens the suggestion")
    }

    /// "Planted together 14 Nov 2026"; the Details link sits beside it.
    static func plantedTogether(at instant: Date) -> String {
        let day = shortDate(instant)
        return String(localized: "Planted together \(day)", comment: "Garden: when a place tree was planted; the placeholder is a day like 14 Nov 2026")
    }

    static var details: String {
        String(localized: "Details", comment: "Garden: link to a tree's postcard")
    }

    /// The title line of a tree with a moment's day: "Our first trip · 12 March 2023".
    static func titleWithMoment(title: String, storedMomentDay: Date) -> String {
        let day = longDay(stored: storedMomentDay)
        return String(localized: "\(title) · \(day)", comment: "Garden: a tree's title and the day it remembers; placeholders: the title, then a day like 12 March 2023")
    }

    static var plantFirstTreeTitle: String {
        String(localized: "Plant your first tree together", comment: "Journey hero title for a couple without a start date")
    }

    static func plantFirstTreeBody(partnerName: String) -> String {
        String(localized: "Choose the day your story began, and if you like, the place. \(partnerName) plants it with you.",
               comment: "Journey hero body for a couple without a start date; the placeholder is the partner's name")
    }

    static var plantASeed: String {
        String(localized: "Plant a seed", comment: "Journey hero button to send the seed of the couple's first tree")
    }

    static var plantingUnavailable: String {
        String(localized: "Planting together isn't available right now. Try again later.",
               comment: "Journey hero line when the garden can't be reached and there is no start date")
    }

    static var startDateChangeUnavailable: String {
        String(localized: "Changing the start date isn't available right now.",
               comment: "Shown when Edit is tapped while the garden can't be reached")
    }

    static func waitingFor(partnerName: String) -> String {
        String(localized: "Waiting for \(partnerName)", comment: "Journey hero title while your first seed waits; the placeholder is the partner's name")
    }

    static func waitingToPlant(partnerName: String) -> String {
        String(localized: "Waiting for \(partnerName) to plant your tree",
               comment: "Journey subtitle while your first seed waits; the placeholder is the partner's name")
    }

    static func myFirstSeedBody(storedStartDay: Date, partnerName: String) -> String {
        let day = longDay(stored: storedStartDay)
        return String(localized: "Your seed for \(day) is with \(partnerName). It's planted when \(partnerName) says yes.",
                      comment: "Journey hero body while your first seed waits; placeholders: a day like 12 March 2023, then the partner's name twice")
    }

    static func partnerSentSeed(partnerName: String) -> String {
        String(localized: "\(partnerName) sent you a seed", comment: "Journey hero title and subtitle when the partner's first seed waits; the placeholder is the partner's name")
    }

    static func partnerFirstSeedBody(storedStartDay: Date) -> String {
        let day = longDay(stored: storedStartDay)
        return String(localized: "For the day your story began: \(day).",
                      comment: "Journey hero body for the partner's first seed; the placeholder is a day like 12 March 2023")
    }

    static func seePartnersSeed(partnerName: String) -> String {
        String(localized: "See \(partnerName)'s seed", comment: "Journey hero button to open the partner's first seed; the placeholder is the partner's name")
    }

    static var editSeed: String {
        String(localized: "Edit seed", comment: "Garden: button to edit your own seed")
    }

    static var takeItBack: String {
        String(localized: "Take it back", comment: "Garden: button to withdraw your own seed or request")
    }

    // MARK: - A partner on a legacy build

    static func partnerNeedsUpdateToPlant(partnerName: String) -> String {
        String(localized: "\(partnerName) needs the latest Coupley to plant together.",
               comment: "Garden: the partner's app is too old to answer seeds; the placeholder is the partner's name")
    }

    static func partnerNeedsUpdateToAnswer(partnerName: String) -> String {
        String(localized: "\(partnerName) needs the latest Coupley to answer",
               comment: "Garden quiet row: the partner's app is too old to answer; the Tell button sits beside it; the placeholder is the partner's name")
    }

    static func tellPartner(partnerName: String) -> String {
        String(localized: "Tell \(partnerName)", comment: "Garden: button to message the partner about updating; the placeholder is the partner's name")
    }

    /// Sent to Chat as the user's own message, only after they confirm it.
    static var tellPartnerMessage: String {
        String(localized: "🌱 I'd love to plant a tree with you on Journey. Update Coupley to see it.",
               comment: "A chat message the user sends to a partner whose app is out of date; shown for confirmation before sending")
    }

    // MARK: - Requests (B4)

    static func seedFromPartnerTitle(partnerName: String) -> String {
        String(localized: "A seed from \(partnerName)", comment: "Garden request card title; the placeholder is the partner's name")
    }

    /// "“Our first trip” · Đà Lạt", or "“Our first trip”" without a place.
    static func seedLine(title: String, place: String?) -> String {
        guard let place, !place.isEmpty else {
            return String(localized: "“\(title)”", comment: "Garden request card line: the proposed tree's title in quotes")
        }
        return String(localized: "“\(title)” · \(place)",
                      comment: "Garden request card line: the proposed tree's title in quotes, then its place")
    }

    static var seeTheSeed: String {
        String(localized: "See the seed", comment: "Garden request card button to open a seed")
    }

    static var notNow: String {
        String(localized: "Not now", comment: "Garden: button to put a seed or an invitation aside")
    }

    static func changeFromPartnerTitle(partnerName: String) -> String {
        String(localized: "\(partnerName) suggested a change", comment: "Garden request card title; the placeholder is the partner's name")
    }

    /// One part of a tree a change request touches.
    nonisolated enum ChangePart: CaseIterable, Sendable {
        case name, place, day, look

        var phrase: String {
            switch self {
            case .name:  return String(localized: "the name", comment: "Garden: a part of a tree a change touches, listed as in 'To “Our first trip”: the name and the place.'")
            case .place: return String(localized: "the place", comment: "Garden: a part of a tree a change touches, listed as in 'To “Our first trip”: the place and the day.'")
            case .day:   return String(localized: "the day", comment: "Garden: a part of a tree a change touches, listed as in 'To “Our first trip”: the place and the day.'")
            case .look:  return String(localized: "the look", comment: "Garden: a part of a tree a change touches, listed as in 'To “Our tree”: the look.'")
            }
        }
    }

    /// "To “Our first trip”: the place and the day." The parts are joined
    /// by the locale's list format.
    static func changeLine(title: String, parts: [ChangePart]) -> String {
        let list = parts.map(\.phrase).formatted(.list(type: .and))
        return String(localized: "To “\(title)”: \(list).",
                      comment: "Garden request card line: what a change touches; placeholders: the tree's title, then a list like 'the place and the day'")
    }

    static var takeALook: String {
        String(localized: "Take a look", comment: "Garden request card button to open a change request")
    }

    static func startDateFromPartnerTitle(partnerName: String) -> String {
        String(localized: "\(partnerName) suggested a new start date", comment: "Garden request card title; the placeholder is the partner's name")
    }

    static func startDateLine(newStored: Date, currentStored: Date) -> String {
        let new = longDay(stored: newStored), current = longDay(stored: currentStored)
        return String(localized: "\(new) instead of \(current).",
                      comment: "Garden request card line for a new start date; placeholders: the suggested day, then the current day, like 10 March 2023")
    }

    static func dayCountWouldBe(_ count: Int) -> String {
        let number = count.formatted()
        return String(localized: "Your day count would be \(number).",
                      comment: "Garden request card line for a new start date; the placeholder is a number of days like 1,344")
    }

    static var agree: String {
        String(localized: "Agree", comment: "Garden: button to agree to the partner's request")
    }

    static func keepStartDate(currentStored: Date) -> String {
        let day = dayAndMonth(stored: currentStored)
        return String(localized: "Keep \(day)", comment: "Garden: button to keep the current start date; the placeholder is a day and month like 12 March")
    }

    static func restFromPartnerTitle(partnerName: String) -> String {
        String(localized: "\(partnerName) would like to let a tree rest", comment: "Garden request card title; the placeholder is the partner's name")
    }

    static func restLine(title: String) -> String {
        String(localized: "“\(title)” leaves your garden if you agree. Its waterings stay in the journal.",
               comment: "Garden request card line for letting a tree rest; the placeholder is the tree's title")
    }

    static var letItRest: String {
        String(localized: "Let it rest", comment: "Garden: button to agree to let a tree rest")
    }

    static var keepIt: String {
        String(localized: "Keep it", comment: "Garden: button to keep a tree the partner asked to let rest")
    }

    /// In place of a tree's postcard, or of a request about the tree, once it
    /// was let rest while that was open.
    static var treeResting: String {
        String(localized: "This tree is resting now.",
               comment: "Garden: replaces a tree's postcard, or a request about the tree, when the tree is let rest while it is open")
    }

    static var edit: String {
        String(localized: "Edit", comment: "Garden: button to edit your own request")
    }

    /// Quiet row: "Waiting for Sam · your seed for “Our first trip”".
    static func waitingSeed(partnerName: String, title: String) -> String {
        String(localized: "Waiting for \(partnerName) · your seed for “\(title)”",
               comment: "Garden quiet row; placeholders: the partner's name, then the seed's title")
    }

    /// Quiet row for several of my seeds: "Waiting for Sam · 2 seeds".
    static func waitingSeeds(partnerName: String, count: Int) -> String {
        String(localized: "Waiting for \(partnerName) · \(count) seeds",
               comment: "Garden quiet row for several of your seeds; placeholders: the partner's name, then the number of seeds (2 or 3)")
    }

    static func waitingStartDate(partnerName: String, storedDay: Date) -> String {
        let day = longDay(stored: storedDay)
        return String(localized: "Waiting for \(partnerName) · new start date \(day)",
                      comment: "Garden quiet row; placeholders: the partner's name, then a day like 10 March 2023")
    }

    static func waitingChange(partnerName: String, title: String) -> String {
        String(localized: "Waiting for \(partnerName) · your change to “\(title)”",
               comment: "Garden quiet row for your change request; placeholders: the partner's name, then the tree's title")
    }

    static func waitingRest(partnerName: String, title: String) -> String {
        String(localized: "Waiting for \(partnerName) · to let “\(title)” rest",
               comment: "Garden quiet row for your request to let a tree rest; placeholders: the partner's name, then the tree's title")
    }

    /// Snoozed seeds collapse into one quiet row: "1 seed from Sam · See".
    static func snoozedSeeds(count: Int, partnerName: String) -> String {
        String(localized: "\(count) seed from \(partnerName) · See",
               comment: "Garden quiet row for seeds put aside with Not now; placeholders: the number of seeds, then the partner's name")
    }

    /// "1 more request" / "2 more requests" under the request cards.
    static func moreRequests(_ count: Int) -> String {
        String(localized: "\(count) more request", comment: "Garden: button under the request cards; the placeholder is the number of requests not shown")
    }

    /// The garden chip's VoiceOver label: "Your garden, 4 trees, 1 request waiting".
    static func gardenChipLabel(treeCount: Int, requestsWaiting: Int) -> String {
        if requestsWaiting > 0 {
            return String(localized: "Your garden, \(treeCount) trees, \(requestsWaiting) request waiting",
                          comment: "VoiceOver label of the garden chip; placeholders: the number of trees, then of requests waiting for you")
        }
        return String(localized: "Your garden, \(treeCount) trees",
                      comment: "VoiceOver label of the garden chip; the placeholder is the number of trees")
    }

    // MARK: - Place chip

    /// "Where we first met · Café Giảng" (a place tree's chip).
    static func placeChip(title: String, place: String) -> String {
        String(localized: "\(title) · \(place)", comment: "Garden place chip: a tree's title, then its place's name")
    }

    static var addAPlace: String {
        String(localized: "Add a place", comment: "Garden place chip and button for a tree without a place")
    }

    // MARK: - Notices (B4 quiet zone)

    static func seedSetAside(partnerName: String, title: String) -> String {
        String(localized: "\(partnerName) set aside your seed for “\(title)”. You can plant another anytime.",
               comment: "Garden notice: the partner let your seed go; placeholders: the partner's name, then the seed's title")
    }

    static func startDateChangedElsewhere(storedDay: Date) -> String {
        let day = longDay(stored: storedDay)
        return String(localized: "Your start date was changed to \(day) in an older version of Coupley.",
                      comment: "Garden notice: the start date was changed by an app without the garden; the placeholder is a day like 10 March 2023")
    }

    static func lookChanged(partnerName: String, title: String) -> String {
        String(localized: "\(partnerName) gave “\(title)” a new look.",
               comment: "Garden notice: the partner changed a tree's scene or species; placeholders: the partner's name, then the tree's title")
    }

    static func wateringRefused(at instant: Date) -> String {
        let when = time(instant)
        return String(localized: "Your watering at \(when) didn't go through.",
                      comment: "Garden notice: a watering made offline was refused later; the placeholder is a time like 9:14 PM")
    }

    static var homeInviteTitle: String {
        String(localized: "Give your tree a home", comment: "Garden invitation card title")
    }

    static var homeInviteBody: String {
        String(localized: "Your tree can stand somewhere that matters to you both, like the place you first met. You choose it together.",
               comment: "Garden invitation card body")
    }

    static var ok: String {
        String(localized: "OK", comment: "Garden: button that dismisses a notice")
    }

    static var changeItBack: String {
        String(localized: "Change it back", comment: "Garden: button that restores a tree's previous look")
    }

    static var waterAgain: String {
        String(localized: "Water again", comment: "Garden: button to retry a watering that didn't go through")
    }

    static var chooseAPlace: String {
        String(localized: "Choose a place", comment: "Garden invitation card button")
    }

    // MARK: - Errors (B8)

    static var wateringFailed: String {
        String(localized: "Couldn't water the garden. Your trees are fine. Try again in a moment.",
               comment: "Garden error: a watering was refused")
    }

    static var lookFailed: String {
        String(localized: "Couldn't change the look. Try again in a moment.",
               comment: "Garden error: a look change was refused")
    }

    static var answerFailed: String {
        String(localized: "Couldn't save your answer. Try again in a moment.",
               comment: "Garden error: dismissing a request or recording a start date failed")
    }

    // MARK: - Home (B7)

    static func homeSeed(partnerName: String) -> String {
        String(localized: "🌱 \(partnerName) sent you a seed · See it on Journey",
               comment: "Home row when a seed waits for you; the placeholder is the partner's name")
    }

    static func homeRequest(partnerName: String) -> String {
        String(localized: "🌱 \(partnerName) suggested a change · See it on Journey",
               comment: "Home row when a request waits for you; the placeholder is the partner's name")
    }

    @MainActor
    static func homeWatered(partnerName: String, at: Date, now: Date) -> String {
        let moment = FutureLetterClock.moment(at, now: now)
        return String(localized: "💧 \(partnerName) watered your garden · \(moment)",
                      comment: "Home row after the partner watered; placeholders: the partner's name, then a moment like 'today at 9:14 PM'")
    }

    /// VoiceOver for Home's row: complete sentences, joined.
    @MainActor
    static func homeWateredSpoken(partnerName: String, at: Date, note: String?, now: Date) -> String {
        let moment = FutureLetterClock.moment(at, now: now)
        var sentences = [String(localized: "\(partnerName) watered your garden \(moment).",
                                comment: "VoiceOver for Home's garden row; placeholders: the partner's name, then a moment like 'today at 9:14 PM'")]
        if let note {
            sentences.append(String(localized: "Note: \(note).", comment: "VoiceOver for Home's garden row: the watering note"))
        }
        sentences.append(opensJourney)
        return sentences.joined(separator: " ")
    }

    static func homeRequestSpoken(partnerName: String, isSeed: Bool) -> String {
        let sentence = isSeed
            ? String(localized: "\(partnerName) sent you a seed.",
                     comment: "VoiceOver for Home's garden row when a seed waits; the placeholder is the partner's name")
            : String(localized: "\(partnerName) suggested a change.",
                     comment: "VoiceOver for Home's garden row when a request waits; the placeholder is the partner's name")
        return [sentence, opensJourney].joined(separator: " ")
    }

    private static var opensJourney: String {
        String(localized: "Opens Journey.", comment: "VoiceOver hint at the end of Home's garden row")
    }

    // MARK: - Journal (B5.5)

    static var you: String {
        String(localized: "You", comment: "Garden journal: you, as the one who watered")
    }

    /// "11:14 PM for Sam": the partner's local time of a watering.
    static func partnerLocalTime(_ instant: Date, timeZone: TimeZone, partnerName: String) -> String {
        let when = time(instant, in: timeZone)
        return String(localized: "\(when) for \(partnerName)",
                      comment: "Garden journal: the time of a watering in the partner's time zone; placeholders: a time like 11:14 PM, then the partner's name")
    }

    @MainActor
    static func journalWhen(_ instant: Date?, now: Date) -> String {
        guard let instant else {
            return String(localized: "just now", comment: "Garden journal: a watering still on its way to the server")
        }
        return FutureLetterClock.moment(instant, now: now)
    }

    // MARK: - Planting

    /// Stands in for this user in "Planted by …" (the ceremony).
    static var plantedByYou: String {
        String(localized: "you", comment: "The current user in 'Planted by Sam and you'")
    }
}
