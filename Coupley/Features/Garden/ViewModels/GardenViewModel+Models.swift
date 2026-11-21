//
//  GardenViewModel+Models.swift
//  Coupley
//
//  Derived, pure values for the views (spec I3): the hero, the request
//  cards, Home's line, the journal, the one-filled-CTA resolver, notices,
//  ceremony and replay candidates, and the lookups the sheets use.
//  Garden-level values (status, water action, CTA, primary action, Home)
//  come from the latest watering alone, never from the selected page; each
//  page's look comes from GardenTreeVisual.forTree.
//
//  Defensive rules (spec I7) apply here, where the couple is known: a tree
//  counts as planted only with two different members as planters (or as
//  Our tree recorded from a start date), and waterings and proposals count
//  only by a member.
//

import Foundation

extension GardenViewModel {

    // MARK: - Validated data

    private var members: Set<String> { [session.userId, session.partnerId] }

    /// The garden in page order: Our tree first (drawn from the start date
    /// alone until it is recorded), then place trees by planting.
    var plantedTrees: [GardenTree] {
        let couple = members
        let startKnown = anchor.exists || !anchor.isResolved
        var trees = docs.trees.filter { tree in
            switch tree.origin {
            case .together:
                guard tree.plantedBy.count == 2, Set(tree.plantedBy) == couple else { return false }
                return !tree.isOurTree || startKnown
            case .legacy:
                return tree.isOurTree && startKnown
            }
        }
        if anchor.exists, let start = anchor.startDate, !trees.contains(where: { $0.isOurTree }) {
            trees.append(.unrecordedOurTree(startDate: start))
        }
        return trees.sorted { a, b in
            if a.isOurTree != b.isOurTree { return a.isOurTree }
            let at = a.plantedAt ?? .distantFuture, bt = b.plantedAt ?? .distantFuture
            return at != bt ? at < bt : a.slot.rawValue < b.slot.rawValue
        }
    }

    /// My place seeds that exist (seed_<me>_1…3), countered ones included:
    /// exactly what T0 counts before it answers `.tooManySeeds`.
    var myOpenPlaceSeedCount: Int {
        let me = session.userId
        return docs.proposals.filter { GardenDocID.placeSeedParts($0.id)?.creator == me }.count
    }

    /// Proposals by a member that are not void, oldest first.
    var liveProposals: [GardenProposal] {
        let couple = members
        return docs.proposals
            .filter { couple.contains($0.by) && !isVoid($0) }
            .sorted { ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
    }

    /// Waterings by a member, newest first (my pending one on top, at its
    /// estimated time).
    var liveWaterings: [GardenWatering] {
        let couple = members
        return waterings.waterings
            .filter { couple.contains($0.by) }
            .sorted { ($0.wateredAt ?? .distantFuture) > ($1.wateredAt ?? .distantFuture) }
    }

    /// Who watered last. My own turn document also counts, so a watering
    /// from my other device locks this one too.
    var timeline: GardenWaterTimeline {
        var timeline = GardenWaterTimeline.from(waterings: liveWaterings, me: session.userId)
        if let turn = docs.waterers.first(where: { $0.uid == session.userId })?.lastWateredAt,
           turn > (timeline.mineLastAt ?? .distantPast) {
            timeline.mineLastAt = turn
        }
        return timeline
    }

    /// The GARDEN's state: hours since the latest watering alone (A6).
    var gardenState: GardenWaterState {
        GardenWaterState.garden(lastWateredAt: timeline.latest?.wateredAt, now: now)
    }

    var waterAction: GardenWaterAction {
        GardenWaterAction.resolve(timeline: timeline, state: gardenState, canWrite: availability.allowsWrites,
                                  hasOurTree: anchor.isResolved && anchor.exists, now: now)
    }

    /// A proposal the rules would refuse to carry out: Our tree's seed once
    /// a start date exists, a start date suggested against a date that has
    /// since moved, a request about a tree that is gone. Hidden at once,
    /// deleted by the first client that may (GardenViewModel).
    func isVoid(_ proposal: GardenProposal) -> Bool {
        guard anchor.isResolved else { return false }
        if proposal.id == GardenDocID.seedOurTree { return anchor.exists }
        let recorded = { (slot: GardenSlot) in self.docs.trees.first { $0.slot == slot } }
        switch proposal.kind {
        case .startDate:
            guard anchor.exists, let our = recorded(.our) else { return true }
            return our.key != proposal.key || !GardenCodec.sameInstant(anchor.startDate, proposal.fromStartDay)
        case .change, .rest:
            guard let slot = proposal.targetSlot, let tree = recorded(slot) else { return true }
            return tree.key != proposal.key
        case .plant:
            return false
        }
    }

    private var ourSeedState: GardenOurSeedState {
        guard let seed = liveProposals.first(where: { $0.id == GardenDocID.seedOurTree }) else { return .none }
        return seed.by == session.userId ? .mineWaiting : .partnersWaiting
    }

    /// The partner's latest watering with a note, under 48 h old, that I
    /// have not watered after.
    private var partnerNote: GardenWatering? {
        let timeline = self.timeline
        guard let latest = timeline.partnerLast, latest.note != nil, let at = latest.wateredAt,
              now.timeIntervalSince(at) < GardenCadence.noteInHeroFor,
              (timeline.mineLastAt ?? .distantPast) < at else { return nil }
        return latest
    }

    private func isNoteRead(_ wateringId: String) -> Bool {
        defaults.bool(forKey: GardenDefaultsKey.noticeSeen(session.coupleId, id: Self.noteReadId(wateringId)))
    }

    private func name(of uid: String) -> String {
        uid == session.userId ? GardenCopy.plantedByYou : partnerName
    }

    // MARK: - Derived

    var hero: GardenHeroModel {
        let trees = plantedTrees
        let timeline = self.timeline
        let action = waterAction
        var empty: GardenEmptyHero?
        if anchor.isResolved, !anchor.exists {
            if let seed = liveProposals.first(where: { $0.id == GardenDocID.seedOurTree }), let day = seed.startDay {
                empty = seed.by == session.userId
                    ? .mySeedWaiting(storedStartDay: day, partnerCanAnswer: partner.canGarden)
                    : .partnersSeed(proposalId: seed.id, storedStartDay: day, note: seed.note)
            } else {
                empty = .plantSeed(partnerCanAnswer: partner.canGarden)
            }
        }
        var status: GardenStatusModel?
        if empty == nil, let line = GardenCopy.statusLine(availability: availability, timeline: timeline,
                                                          state: gardenState,
                                                          myWateringPendingTooLong: myWateringPendingTooLong(timeline),
                                                          partnerName: partnerName, now: now) {
            let note = partnerNote.flatMap { watering -> GardenNoteModel? in
                guard let text = watering.note, let at = watering.wateredAt else { return nil }
                return GardenNoteModel(wateringId: watering.id, text: GardenCopy.quoted(text),
                                       attribution: GardenCopy.noteAttribution(name: partnerName, at: at, now: now))
            }
            status = GardenStatusModel(line: line,
                                       isNews: newsWateringId != nil && newsWateringId == timeline.partnerLast?.id,
                                       note: note)
        }
        let waiting = requests.filter { !$0.isMine && !$0.isSnoozed }
        return GardenHeroModel(availability: availability, empty: empty,
                               pages: empty == nil ? trees.map { page(for: $0, timeline: timeline) } : [],
                               selectedSlot: selectedSlot, status: status, waterAction: action,
                               waterTitle: GardenCopy.waterTitle(action, treeCount: trees.count),
                               primary: primaryAction, treeCount: trees.count,
                               requestWaitingForMe: !waiting.isEmpty, partnerCanGarden: partner.canGarden)
    }

    /// My watering has waited for the server longer than 3 s.
    private func myWateringPendingTooLong(_ timeline: GardenWaterTimeline) -> Bool {
        guard let latest = timeline.latest, latest.by == session.userId, latest.hasPendingWrites else { return false }
        let tapped = wateringTaps[latest.id] ?? .distantPast
        return Date().timeIntervalSince(tapped) >= GardenCadence.pendingWateringCopyAfter
    }

    private func page(for tree: GardenTree, timeline: GardenWaterTimeline) -> GardenPageModel {
        let latest = timeline.latest?.wateredAt
        var cans = GardenRestingCans.none
        let mineRecent = timeline.mineLastAt.map { now.timeIntervalSince($0) < GardenCadence.restingCansFor } ?? false
        let theirsRecent = timeline.partnerLastAt.map { now.timeIntervalSince($0) < GardenCadence.restingCansFor } ?? false
        switch (mineRecent, theirsRecent) {
        case (true, true):  cans = .both
        case (true, false): cans = .mine
        case (false, true): cans = .partners
        case (false, false): cans = .none
        }
        var rainbow = false
        if timeline.isTogether, let mine = timeline.mineLastAt, let theirs = timeline.partnerLastAt {
            rainbow = now.timeIntervalSince(max(mine, theirs)) < GardenCadence.rainbowFor
        }
        var tag: TreeNoteTag?
        if tree.slot == selectedSlot, let note = partnerNote, !isNoteRead(note.id) {
            tag = TreeNoteTag(wateringId: note.id)
        }
        var chip: String?
        var chipIsAction = false
        if let place = tree.place {
            chip = tree.isOurTree ? place.name : GardenCopy.placeChip(title: tree.displayTitle, place: place.name)
        } else if availability.allowsWrites,
                  !tree.isOurTree || defaults.bool(forKey: GardenDefaultsKey.inviteDismissed(session.coupleId)) {
            chip = GardenCopy.addAPlace
            chipIsAction = true
        }
        return GardenPageModel(slot: tree.slot, key: tree.key, title: tree.displayTitle, preset: tree.preset,
                               look: tree.look, place: tree.place,
                               environment: .make(scene: tree.look.scene, place: tree.place, treeKey: tree.key, now: now),
                               visual: .forTree(lastWateredAt: latest, plantedAt: tree.plantedAt, now: now),
                               growthStart: tree.isOurTree ? nil : tree.plantedAt,
                               restingCans: cans, showsRainbow: rainbow, noteTag: tag,
                               placeChip: chip, placeChipIsAction: chipIsAction,
                               hasPendingWrites: tree.hasPendingWrites)
    }

    /// For me and mine, ordered (B4): start date, rest, seeds, changes.
    /// Empty unless the garden is ready (cards hide while it loads or is
    /// unavailable).
    var requests: [GardenRequestModel] {
        guard availability == .ready else { return [] }
        func rank(_ kind: GardenProposalKind) -> Int {
            switch kind {
            case .startDate: return 0
            case .rest:      return 1
            case .plant:     return 2
            case .change:    return 3
            }
        }
        return liveProposals
            .sorted { rank($0.kind) != rank($1.kind) ? rank($0.kind) < rank($1.kind)
                                                     : ($0.at ?? .distantFuture) < ($1.at ?? .distantFuture) }
            .compactMap(request(for:))
    }

    private func request(for proposal: GardenProposal) -> GardenRequestModel? {
        let name = partnerName
        let isMine = proposal.by == session.userId
        let title = proposal.displayTitle ?? ""
        let kind: GardenRequestKind
        var heading: String, lines: [String] = [], primary: String, secondary: String?
        switch proposal.kind {
        case .plant where proposal.id == GardenDocID.seedOurTree:
            guard let day = proposal.startDay else { return nil }
            kind = .ourTreeSeed
            if isMine {
                heading = GardenCopy.waitingFor(partnerName: name)
                lines = [GardenCopy.myFirstSeedBody(storedStartDay: day, partnerName: name)]
                primary = GardenCopy.editSeed
                secondary = GardenCopy.takeItBack
            } else {
                heading = GardenCopy.partnerSentSeed(partnerName: name)
                lines = [GardenCopy.partnerFirstSeedBody(storedStartDay: day)]
                primary = GardenCopy.seePartnersSeed(partnerName: name)
            }
        case .plant:
            kind = .seed
            if isMine {
                heading = GardenCopy.waitingSeed(partnerName: name, title: title)
                primary = GardenCopy.editSeed
                secondary = GardenCopy.takeItBack
            } else {
                heading = GardenCopy.seedFromPartnerTitle(partnerName: name)
                lines = [GardenCopy.seedLine(title: title, place: proposal.place.map { $0.locality ?? $0.name })]
                primary = GardenCopy.seeTheSeed
                secondary = GardenCopy.notNow
            }
        case .change:
            guard let slot = proposal.targetSlot, let tree = tree(slot) else { return nil }
            kind = .change
            if isMine {
                heading = GardenCopy.waitingChange(partnerName: name, title: tree.displayTitle)
                primary = GardenCopy.edit
                secondary = GardenCopy.takeItBack
            } else {
                heading = GardenCopy.changeFromPartnerTitle(partnerName: name)
                lines = [GardenCopy.changeLine(title: tree.displayTitle, parts: changedParts(proposal, from: tree))]
                primary = GardenCopy.takeALook
            }
        case .startDate:
            guard let day = proposal.startDay, let current = anchor.startDate else { return nil }
            kind = .startDate
            if isMine {
                heading = GardenCopy.waitingStartDate(partnerName: name, storedDay: day)
                primary = GardenCopy.edit
                secondary = GardenCopy.takeItBack
            } else {
                heading = GardenCopy.startDateFromPartnerTitle(partnerName: name)
                let count = RelationshipAnchor(startDate: day, setBy: proposal.by).daysTogether(now: now)
                lines = [GardenCopy.startDateLine(newStored: day, currentStored: current),
                         GardenCopy.dayCountWouldBe(count)]
                primary = GardenCopy.agree
                secondary = GardenCopy.keepStartDate(currentStored: current)
            }
        case .rest:
            guard let slot = proposal.targetSlot, let tree = tree(slot) else { return nil }
            kind = .rest
            if isMine {
                heading = GardenCopy.waitingRest(partnerName: name, title: tree.displayTitle)
                primary = GardenCopy.takeItBack
            } else {
                heading = GardenCopy.restFromPartnerTitle(partnerName: name)
                lines = [GardenCopy.restLine(title: tree.displayTitle)]
                primary = GardenCopy.letItRest
                secondary = GardenCopy.keepIt
            }
        }
        if !isMine, let note = proposal.note { lines.append(GardenCopy.quoted(note)) }
        return GardenRequestModel(id: proposal.id, kind: kind, isMine: isMine, title: heading, lines: lines,
                                  primaryTitle: primary, secondaryTitle: secondary, seen: proposal.version,
                                  isSnoozed: !isMine && isSnoozed(proposal))
    }

    /// What a change request touches, compared with the tree as it is.
    private func changedParts(_ proposal: GardenProposal, from tree: GardenTree) -> [GardenCopy.ChangePart] {
        var parts: [GardenCopy.ChangePart] = []
        if proposal.title != tree.title || proposal.preset != tree.preset { parts.append(.name) }
        if proposal.place != tree.place { parts.append(.place) }
        let sameDay: Bool
        switch (proposal.momentDay, tree.momentDay) {
        case (nil, nil): sameDay = true
        case let (a?, b?): sameDay = GardenCodec.sameInstant(a, b)
        default: sameDay = false
        }
        if !sameDay { parts.append(.day) }
        if let look = proposal.look, look != tree.look { parts.append(.look) }
        return parts.isEmpty ? [.look] : parts
    }

    private func isSnoozed(_ proposal: GardenProposal) -> Bool {
        guard proposal.kind == .plant else { return false }
        let until = defaults.double(forKey: GardenDefaultsKey.snoozed(session.coupleId, seedKey: proposal.key))
        return until > now.timeIntervalSince1970
    }

    /// Home's one quiet row (B7): a request waiting for me first, then the
    /// partner's watering under 24 h old that this device has not seen.
    var homeLine: GardenHomeLine? {
        guard availability == .ready else { return nil }
        let name = partnerName
        if let waiting = requests.first(where: { !$0.isMine && !$0.isSnoozed }) {
            let isSeed = waiting.kind == .seed || waiting.kind == .ourTreeSeed
            return GardenHomeLine(kind: .request,
                                  title: isSeed ? GardenCopy.homeSeed(partnerName: name) : GardenCopy.homeRequest(partnerName: name),
                                  subtitle: nil, focus: .proposal(id: waiting.id),
                                  spokenLabel: GardenCopy.homeRequestSpoken(partnerName: name, isSeed: isSeed))
        }
        guard let latest = timeline.partnerLast, !latest.hasPendingWrites, let at = latest.wateredAt,
              now.timeIntervalSince(at) < GardenCadence.homeRowFor,
              defaults.string(forKey: GardenDefaultsKey.seenWatering(session.coupleId)) != latest.id else { return nil }
        return GardenHomeLine(kind: .watered,
                              title: GardenCopy.homeWatered(partnerName: name, at: at, now: now),
                              subtitle: latest.note.map(GardenCopy.quoted),
                              focus: .watering(id: latest.id),
                              spokenLabel: GardenCopy.homeWateredSpoken(partnerName: name, at: at, note: latest.note, now: now))
    }

    var primaryAction: GardenPrimaryAction {
        GardenPrimaryAction.resolve(hasStartDate: anchor.isResolved ? anchor.exists : nil, ourSeed: ourSeedState,
                                    water: waterAction, availability: availability)
    }

    var treeCount: Int { plantedTrees.count }

    var canPlantMore: Bool {
        availability.allowsWrites && anchor.exists && treeCount < GardenLimits.maxTrees
    }

    var partnerName: String {
        partner.displayName ?? String(localized: "Partner",
                                      comment: "Stands in for the name of a partner who hasn't set one")
    }

    func tree(_ slot: GardenSlot) -> GardenTree? {
        plantedTrees.first { $0.slot == slot }
    }

    func proposal(id: String) -> GardenProposal? {
        liveProposals.first { $0.id == id }
    }

    /// The live last 60.
    func journalEntries() -> [GardenJournalEntry] {
        journal(liveWaterings)
    }

    /// An older page (pages of 50 by `wateredAt`, from the server), for the
    /// journal's scroll. nil when it could not be loaded (offline, an error,
    /// no garden): never mistaken for the end of the journal.
    func loadJournalPage(before: Date?) async -> [GardenJournalEntry]? {
        let couple = members
        guard isAvailable,
              let page = try? await fetchJournalPage(before: before) else { return nil }
        return journal(page.filter { couple.contains($0.by) })
    }

    /// Two waterings by the two partners within 24 h are a "Together" pair;
    /// pairs never overlap, newest first.
    private func journal(_ list: [GardenWatering]) -> [GardenJournalEntry] {
        var pairStarts = Set<Int>()
        var index = 0
        while index < list.count - 1 {
            let a = list[index], b = list[index + 1]
            if a.by != b.by, let at = a.wateredAt, let bt = b.wateredAt,
               abs(at.timeIntervalSince(bt)) <= GardenCadence.togetherWindow {
                pairStarts.insert(index)
                index += 2
            } else {
                index += 1
            }
        }
        let partnerZone = partner.timeZone
        return list.enumerated().map { offset, watering in
            let byMe = watering.by == session.userId
            var partnerTime: String?
            if let zone = partnerZone, let at = watering.wateredAt,
               zone.secondsFromGMT(for: at) != TimeZone.current.secondsFromGMT(for: at) {
                partnerTime = GardenCopy.partnerLocalTime(at, timeZone: zone, partnerName: partnerName)
            }
            return GardenJournalEntry(id: watering.id, byMe: byMe, name: byMe ? GardenCopy.you : partnerName,
                                      when: GardenCopy.journalWhen(watering.wateredAt, now: now),
                                      partnerLocalTime: partnerTime, note: watering.note.map(GardenCopy.quoted),
                                      pairsWithNext: pairStarts.contains(offset), wateredAt: watering.wateredAt)
        }
    }

    /// Prefilled: the preset's title, the suggested look, the proposal or
    /// tree being edited. Days are LOCAL days for the pickers. A Timeline
    /// memory's day is offered by the plant sheet as a hint, not filled here.
    func draft(for mode: GardenDraft.Mode) -> GardenDraft {
        switch mode {
        case .newPlaceTree:
            let preset = GardenPreset.placePresets[0]
            return GardenDraft(mode: mode, preset: preset, title: preset.localizedDefaultTitle, startDay: nil,
                               momentDay: nil, place: nil,
                               look: .suggested(scene: preset.fallbackScene, forOurTree: false), note: nil)
        case .ourTreeFirstPlanting:
            let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: now) ?? now
            return GardenDraft(mode: mode, preset: .ourTree, title: GardenPreset.ourTree.localizedDefaultTitle,
                               startDay: threeMonthsAgo, momentDay: nil, place: nil, look: .ourTreeDefault, note: nil)
        case .editSeed(let id, _), .counter(let id, _), .editChange(let id, _):
            guard let proposal = proposal(id: id) else { return draft(for: .newPlaceTree) }
            let preset = proposal.preset ?? (proposal.slot == GardenSlot.our.rawValue ? .ourTree : .custom)
            var isCounter = false
            if case .counter = mode { isCounter = true }
            return GardenDraft(mode: mode, preset: preset, title: proposal.displayTitle ?? preset.localizedDefaultTitle,
                               startDay: proposal.startDay.map { JourneyCalendarDay.localDay(ofStored: $0) },
                               momentDay: proposal.momentDay.map { JourneyCalendarDay.localDay(ofStored: $0) },
                               place: proposal.place, look: proposal.look ?? .ourTreeDefault,
                               note: isCounter ? nil : proposal.note)
        case .changeTree(let slot):
            guard let tree = tree(slot) else { return draft(for: .newPlaceTree) }
            var place = tree.place, look = tree.look
            // A first seed voided by a legacy planting comes back here.
            if slot.isOurTree, place == nil, let home = homeDraft() {
                place = home.place
                look = home.look
            }
            return GardenDraft(mode: mode, preset: tree.preset, title: tree.displayTitle, startDay: nil,
                               momentDay: tree.momentDay.map { JourneyCalendarDay.localDay(ofStored: $0) },
                               place: place, look: look, note: nil)
        }
    }

    // MARK: - Notices, ceremony, replay

    /// One-time notices, in the order the quiet zone shows them one at a time;
    /// the home invitation (a card of its own) last.
    func noticeList() -> [GardenNotice] {
        guard availability == .ready else { return [] }
        let name = partnerName, coupleId = session.coupleId
        var list: [GardenNotice] = []

        for (key, record) in openSeedRecords().sorted(by: { $0.key < $1.key }) where record.setAside {
            let title = record.preset.displayTitle(stored: record.title)
            list.append(GardenNotice(id: "aside." + key, kind: .seedSetAside(title: title),
                                     text: GardenCopy.seedSetAside(partnerName: name, title: title),
                                     actionTitle: nil, dismissTitle: GardenCopy.ok))
        }

        // Shown until this device has seen it (OK stores the start date as seen).
        if let since = startDateMismatchSince, Date().timeIntervalSince(since) >= 2, let start = anchor.startDate {
            let id = "startdate." + String(Int64((start.timeIntervalSince1970 * 1000).rounded()))
            list.append(GardenNotice(id: id, kind: .startDateChangedElsewhere(storedDay: start),
                                     text: GardenCopy.startDateChangedElsewhere(storedDay: start),
                                     actionTitle: GardenCopy.ok, dismissTitle: nil))
        }

        for tree in plantedTrees {
            guard let by = tree.lookBy, by == session.partnerId, let at = tree.lookAt, tree.previousLook != nil,
                  now.timeIntervalSince(at) < GardenCadence.lookUndoFor, !lookChangeIsSuperseded(tree) else { continue }
            let id = "look." + tree.key + "." + String(Int64((at.timeIntervalSince1970 * 1000).rounded()))
            guard !defaults.bool(forKey: GardenDefaultsKey.noticeSeen(coupleId, id: id)) else { continue }
            list.append(GardenNotice(id: id, kind: .lookChanged(slot: tree.slot, treeTitle: tree.displayTitle),
                                     text: GardenCopy.lookChanged(partnerName: name, title: tree.displayTitle),
                                     actionTitle: GardenCopy.changeItBack, dismissTitle: GardenCopy.ok))
        }

        for refused in refusedWaterings {
            list.append(GardenNotice(id: "refused." + refused.id, kind: .wateringRefused(at: refused.at),
                                     text: GardenCopy.wateringRefused(at: refused.at),
                                     actionTitle: GardenCopy.waterAgain, dismissTitle: GardenCopy.ok))
        }

        if anchor.exists, let our = tree(.our), our.place == nil,
           !defaults.bool(forKey: GardenDefaultsKey.inviteDismissed(coupleId)),
           !liveProposals.contains(where: { $0.id == GardenDocID.change(.our) }) {
            list.append(GardenNotice(id: "invite", kind: .homeInvite, text: GardenCopy.homeInviteBody,
                                     actionTitle: GardenCopy.chooseAPlace, dismissTitle: GardenCopy.notNow,
                                     title: GardenCopy.homeInviteTitle))
        }
        return list
    }

    /// A direct look change that an agreement has come after (a change
    /// request carries its own look): its notice and "Change it back" would
    /// revert what both agreed since.
    func lookChangeIsSuperseded(_ tree: GardenTree) -> Bool {
        guard let lookAt = tree.lookAt, let agreedAt = tree.agreementAt else { return false }
        return agreedAt > lookAt
    }

    /// A planting this device has not celebrated: the proposer's, the next
    /// time Journey is visible within 7 days, or the planter's whose
    /// transaction timed out but committed.
    func dueCeremony() -> GardenCeremony? {
        let me = session.userId, coupleId = session.coupleId
        let tree = plantedTrees.first { tree in
            guard tree.plantedBy.contains(me), !tree.hasPendingWrites, let at = tree.plantedAt else { return false }
            let age = now.timeIntervalSince(at)
            return age > -GardenCadence.maxServerOffset && age < GardenCadence.ceremonyWithin
                && !defaults.bool(forKey: GardenDefaultsKey.ceremonySeen(coupleId, key: tree.key))
        }
        return tree.map { tree in
            GardenCeremony(slot: tree.slot, key: tree.key, title: tree.displayTitle, place: tree.place, look: tree.look,
                           growthStart: tree.isOurTree ? (tree.agreedStartDay ?? anchor.startDate) : nil,
                           momentDay: tree.isOurTree ? nil : tree.momentDay,
                           plantedAt: tree.plantedAt, plantedByNames: tree.plantedBy.map(name(of:)),
                           isOurTree: tree.isOurTree)
        }
    }

    /// The planter's ceremony, from the seed just planted (its tree reaches
    /// the listener a moment later; "just now" until then).
    func plantingCeremony(for seed: GardenProposal, slot: GardenSlot) -> GardenCeremony {
        GardenCeremony(slot: slot, key: seed.key, title: seed.displayTitle ?? GardenPreset.ourTree.localizedDefaultTitle,
                       place: seed.place, look: seed.look ?? .ourTreeDefault,
                       growthStart: slot.isOurTree ? seed.startDay : nil,
                       momentDay: slot.isOurTree ? nil : seed.momentDay, plantedAt: nil,
                       plantedByNames: [name(of: seed.by), GardenCopy.plantedByYou], isOurTree: slot.isOurTree)
    }

    /// The partner's watering to replay: the one a push asked for, else the
    /// newest if it is the partner's, confirmed, under 48 h old and not yet
    /// seen here. Each plays once per launch.
    func replayCandidate(requested: String?) -> GardenWatering? {
        let all = liveWaterings
        func playable(_ watering: GardenWatering) -> Bool {
            watering.by != session.userId && !watering.hasPendingWrites && !hasReplayed(watering.id)
        }
        if let requested, let watering = all.first(where: { $0.id == requested }), playable(watering) {
            return watering
        }
        guard let newest = all.first, playable(newest), let at = newest.wateredAt,
              now.timeIntervalSince(at) < GardenCadence.noteInHeroFor,
              defaults.string(forKey: GardenDefaultsKey.seenWatering(session.coupleId)) != newest.id else { return nil }
        return newest
    }

    /// Every future moment the garden's copy, controls or overlays change.
    func nextBoundaries() -> [Date] {
        let timeline = self.timeline
        var dates: [Date] = []
        if let latest = timeline.latest?.wateredAt {
            dates += [GardenCadence.readyAfter, GardenCadence.thirstyAfter, GardenCadence.restingAfter,
                      GardenCadence.noteInHeroFor].map(latest.addingTimeInterval)
        }
        if let mine = timeline.mineLastAt {
            dates += [GardenCadence.cooldown, GardenCadence.restingCansFor].map(mine.addingTimeInterval)
        }
        if let theirs = timeline.partnerLastAt {
            dates += [GardenCadence.waterBackWindow, GardenCadence.homeRowFor, GardenCadence.noteInHeroFor]
                .map(theirs.addingTimeInterval)
        }
        if timeline.isTogether, let mine = timeline.mineLastAt, let theirs = timeline.partnerLastAt {
            let later = max(mine, theirs)
            dates += [GardenCadence.rainbowFor, GardenCadence.noteInHeroFor].map(later.addingTimeInterval)
        }
        if let latest = timeline.latest, latest.hasPendingWrites, let tapped = wateringTaps[latest.id] {
            dates.append(serverNow().addingTimeInterval(tapped.addingTimeInterval(GardenCadence.pendingWateringCopyAfter)
                .timeIntervalSince(Date())))
        }
        for tree in plantedTrees {
            if let at = tree.lookAt { dates.append(at.addingTimeInterval(GardenCadence.lookUndoFor)) }
        }
        for proposal in docs.proposals where proposal.kind == .plant {
            let until = defaults.double(forKey: GardenDefaultsKey.snoozed(session.coupleId, seedKey: proposal.key))
            if until > 0 { dates.append(Date(timeIntervalSince1970: until)) }
        }
        if let since = startDateMismatchSince {
            dates.append(serverNow().addingTimeInterval(since.addingTimeInterval(2).timeIntervalSince(Date())))
        }
        return dates
    }
}
