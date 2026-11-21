//
//  GardenSeedSheet.swift
//  Coupley
//
//  A seed, a change, a start date or a rest request (B5.2): the partner's to
//  plant or agree to, or my own waiting one. Every carry-out passes the
//  proposal's version as `seen` and is disabled while it is nil.
//
//  The partner's seed is planted with a press and hold (one activation for
//  VoiceOver, Switch Control and Voice Control): the sheet's one fill. Every
//  answer is a transaction, so every answer needs a connection.
//

import Foundation
import SwiftUI
import UIKit

struct GardenSeedSheet: View {

    @ObservedObject var garden: GardenViewModel
    let proposalId: String
    let onPlanted: () -> Void
    let onOpenTree: (GardenSlot) -> Void
    /// Pushed inside another sheet's NavigationStack (the Garden sheet):
    /// no own NavigationStack and no Close.
    let isPushed: Bool

    @Environment(\.dismiss) private var dismiss

    init(garden: GardenViewModel, proposalId: String,
         onPlanted: @escaping () -> Void, onOpenTree: @escaping (GardenSlot) -> Void,
         isPushed: Bool = false) {
        self.garden = garden
        self.proposalId = proposalId
        self.onPlanted = onPlanted
        self.onOpenTree = onOpenTree
        self.isPushed = isPushed
    }

    var body: some View {
        if isPushed {
            GardenProposalView(garden: garden, proposalId: proposalId, isPushed: true,
                               onPlanted: onPlanted, onOpenTree: onOpenTree)
        } else {
            NavigationStack {
                GardenProposalView(garden: garden, proposalId: proposalId, isPushed: false,
                                   onPlanted: onPlanted, onOpenTree: onOpenTree)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismiss()
                            } label: {
                                Text("Close", comment: "Toolbar button: close this sheet")
                            }
                            .foregroundStyle(Brand.textSecondary)
                        }
                    }
            }
        }
    }
}

// MARK: - Content

private struct GardenProposalView: View {

    @ObservedObject var garden: GardenViewModel
    let proposalId: String
    let isPushed: Bool
    let onPlanted: () -> Void
    let onOpenTree: (GardenSlot) -> Void

    @ObservedObject private var reachability = GardenReachability.shared
    @Environment(\.dismiss) private var dismiss

    private enum Pushed: Hashable {
        case form(GardenFormRoute)
        case startDate
    }

    /// GardenDraft.Mode is not Hashable; the routes this view pushes are.
    private enum GardenFormRoute: Hashable {
        case editSeed(GardenProposalVersion)
        case counter(GardenProposalVersion)
        case editChange(GardenProposalVersion)
    }

    @State private var pushed: Pushed?
    @State private var isActing = false
    @State private var showsError = false
    @State private var confirmsLetGo = false
    @State private var confirmsTakeBack = false
    @State private var confirmsStartDate = false
    @State private var confirmsTellPartner = false
    /// An answer succeeded and the view is closing: never flash "gone".
    @State private var isFinished = false
    /// The last version shown: when it disappears, it tells what became of
    /// it (planted, agreed to, set aside, kept as it is, taken back).
    @State private var lastShown: GardenProposal?

    // MARK: Model

    private var proposal: GardenProposal? { garden.proposal(id: proposalId) }

    private var request: GardenRequestModel? { garden.requests.first { $0.id == proposalId } }

    /// Mine: waiting for the partner. Theirs: waiting for me.
    private var isMine: Bool { request?.isMine ?? false }

    private var partnerName: String { garden.partnerName }

    /// My own open seed with the same preset ("You both suggested …").
    private var myDuplicate: GardenProposal? {
        guard let proposal, proposal.kind == .plant, !isMine,
              let preset = proposal.preset, preset != .custom, preset != .ourTree else { return nil }
        return garden.requests
            .filter { $0.isMine && $0.kind == .seed && $0.id != proposalId }
            .compactMap { garden.proposal(id: $0.id) }
            .first { $0.preset == preset }
    }

    private var targetTree: GardenTree? { proposal?.targetSlot.flatMap(garden.tree) }

    private var canAct: Bool {
        reachability.isOnline && proposal?.version != nil && !isActing
    }

    // MARK: Body

    var body: some View {
        Group {
            if let proposal {
                content(proposal)
            } else if !isActing && !isFinished {
                goneView
            }
        }
        .onChange(of: proposal, initial: true) { _, shown in
            if let shown { lastShown = shown }
        }
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushed) { route in
            destination(route)
        }
        .onDisappear {
            if showsError { garden.dismissError() }
        }
    }

    private var navigationTitle: Text {
        guard let proposal else { return Text(verbatim: "") }
        let title = proposal.displayTitle ?? targetTree?.displayTitle ?? ""
        switch (proposal.kind, isMine) {
        case (.plant, false):
            return Text("A seed from \(partnerName)", comment: "Seed sheet title. The placeholder is the partner's name.")
        case (.plant, true):
            return Text("Your seed", comment: "Seed sheet title: my own seed, waiting for the partner")
        case (.change, false):
            return Text("\(partnerName) suggested a change", comment: "Seed sheet title. The placeholder is the partner's name.")
        case (.change, true):
            return Text("You suggested a change", comment: "Seed sheet title: my own suggested change, waiting for the partner")
        case (.startDate, false):
            return Text("\(partnerName) suggested a new start date", comment: "Seed sheet title. The placeholder is the partner's name.")
        case (.startDate, true):
            return Text("You suggested a new start date", comment: "Seed sheet title: my own start date suggestion")
        case (.rest, false):
            return Text("Let “\(targetTree?.displayTitle ?? title)” rest?",
                        comment: "Seed sheet title: the partner asks to let a tree rest. The placeholder is the tree's title.")
        case (.rest, true):
            return Text("You asked to let “\(targetTree?.displayTitle ?? title)” rest",
                        comment: "Seed sheet title: my own request to let a tree rest. The placeholder is the tree's title.")
        }
    }

    private func content(_ proposal: GardenProposal) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch proposal.kind {
                case .plant:
                    seedBody(proposal)
                case .change:
                    changeBody(proposal)
                case .startDate:
                    startDateBody(proposal)
                case .rest:
                    restBody(proposal)
                }
                if isMine {
                    waitingBlock(proposal)
                }
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            controls(proposal)
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.bar)
        }
        .toolbar {
            if proposal.kind == .plant, !isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmsLetGo = true
                        } label: {
                            Label {
                                Text("Let this seed go", comment: "Seed sheet menu: delete the partner's seed without planting it")
                            } icon: {
                                Image(systemName: "wind")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(Text("More", comment: "VoiceOver: the seed sheet's menu button"))
                    }
                }
            }
        }
        .alert(Text("Let this seed go?", comment: "Seed sheet: confirmation title"), isPresented: $confirmsLetGo) {
            Button(role: .destructive) {
                act { await garden.letGo(proposalId) }
            } label: {
                Text("Let it go", comment: "Seed sheet: confirm deleting the partner's seed")
            }
            Button(role: .cancel) {} label: { Text("Cancel", comment: "Cancel a confirmation") }
        } message: {
            Text("\(partnerName) won't be told, and can send it again.",
                 comment: "Seed sheet: letting a seed go. The placeholder is the partner's name.")
        }
        .alert(Text("Take this seed back?", comment: "Seed sheet: confirmation title before withdrawing my seed"),
               isPresented: $confirmsTakeBack) {
            Button(role: .destructive) {
                act { await garden.takeBack(proposalId) }
            } label: {
                Text("Take it back", comment: "Seed sheet: withdraw my seed or request")
            }
            Button(role: .cancel) {} label: { Text("Cancel", comment: "Cancel a confirmation") }
        }
        .alert(startDateConfirmTitle(proposal), isPresented: $confirmsStartDate) {
            Button {
                agree(proposal)
            } label: {
                Text("Change it", comment: "Start date suggestion: confirm agreeing to the new start date")
            }
            Button(role: .cancel) {} label: { Text("Cancel", comment: "Cancel a confirmation") }
        } message: {
            Text("Your tree, anniversaries and crowns will count from that day, for both of you.",
                 comment: "Start date suggestion: what agreeing changes")
        }
        .alert(Text("Send this to \(partnerName) in Chat?",
                    comment: "Confirmation before sending the update invitation. The placeholder is the partner's name."),
               isPresented: $confirmsTellPartner) {
            Button {
                Task { _ = await garden.tellPartnerToUpdate() }
            } label: {
                Text("Send", comment: "Send the update invitation to Chat")
            }
            Button(role: .cancel) {} label: { Text("Cancel", comment: "Cancel a confirmation") }
        } message: {
            Text("🌱 I'd love to plant a tree with you on Journey. Update Coupley to see it.",
                 comment: "Chat message inviting a partner on an older app to update. Sent only after the user taps Send.")
        }
    }

    // MARK: Seeds

    private func seedBody(_ proposal: GardenProposal) -> some View {
        let look = proposal.look ?? .ourTreeDefault
        let isOurTree = proposal.id == GardenDocID.seedOurTree
        let day = isOurTree ? proposal.startDay : proposal.momentDay
        return VStack(alignment: .leading, spacing: 18) {
            GardenSeedPacket(title: proposal.displayTitle ?? "", stampSymbol: look.scene.info.stampSymbol,
                             postmark: day.map(GardenDayText.postmark(stored:)), height: 180)
                .frame(maxWidth: .infinity)

            BrandCard(tier: .card) {
                VStack(alignment: .leading, spacing: 0) {
                    row(LocalizedStringResource("Stands for", comment: "Seed sheet row label: what the tree stands for")) {
                        Text(proposal.displayTitle ?? "")
                    }
                    placeRow(proposal.place, scene: look.scene, tappableSlot: nil)
                    divider
                    row(LocalizedStringResource("Day", comment: "Seed sheet row label: the tree's day")) {
                        if let day {
                            Text(GardenDayText.long(stored: day))
                        } else {
                            Text("From the day you plant it", comment: "Seed sheet: a tree without a moment's day")
                        }
                    }
                    divider
                    lookRow(look)
                    noteRow(proposal.note)
                }
            }

            Text(growthLine(proposal))
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let duplicate = myDuplicate {
                Text("You both suggested “\(duplicate.displayTitle ?? proposal.displayTitle ?? "")”.",
                     comment: "Seed sheet: both partners sent a seed with the same preset. The placeholder is its title.")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Our tree grows from its start date; a place tree from its planting.
    /// One whole sentence per stage: no stage name is set inside another
    /// sentence, so each language can word its own.
    private func growthLine(_ proposal: GardenProposal) -> String {
        let startsAsSeed = String(localized: "It starts as a seed the day you plant it.",
                                  comment: "Seed sheet: a tree that grows from the day it is planted")
        guard proposal.id == GardenDocID.seedOurTree, let start = proposal.startDay else { return startsAsSeed }
        let since = GardenDayText.long(stored: start)
        switch TreeGrowthStage.from(daysTogether: GardenDayCount.days(fromStored: start, now: garden.now)) {
        case .seed:
            return startsAsSeed
        case .sprout:
            return String(localized: "It will be a sprout the day you plant it: it has been growing since \(since).",
                          comment: "Seed sheet: Our tree on the day it is planted, when the start date was 7 to 29 days ago (the Sprout stage). The placeholder is the start date, such as '12 March 2023'.")
        case .sapling:
            return String(localized: "It will be a sapling the day you plant it: it has been growing since \(since).",
                          comment: "Seed sheet: Our tree on the day it is planted, when the start date was 30 to 89 days ago (the Sapling stage). The placeholder is the start date, such as '12 March 2023'.")
        case .young:
            return String(localized: "It will be a young tree the day you plant it: it has been growing since \(since).",
                          comment: "Seed sheet: Our tree on the day it is planted, when the start date was 90 to 179 days ago (the Young Tree stage). The placeholder is the start date, such as '12 March 2023'.")
        case .blooming:
            return String(localized: "It will be in bloom the day you plant it: it has been growing since \(since).",
                          comment: "Seed sheet: Our tree on the day it is planted, when the start date was 180 to 364 days ago (the Blooming stage). The placeholder is the start date, such as '12 March 2023'.")
        case .fruiting:
            return String(localized: "It will bear fruit the day you plant it: it has been growing since \(since).",
                          comment: "Seed sheet: Our tree on the day it is planted, when the start date was 1 to 2 years ago (the Fruiting stage). The placeholder is the start date, such as '12 March 2023'.")
        case .mature:
            return String(localized: "It will be a mature tree the day you plant it: it has been growing since \(since).",
                          comment: "Seed sheet: Our tree on the day it is planted, when the start date was 2 to 4 years ago (the Mature stage). The placeholder is the start date, such as '12 March 2023'.")
        case .ancient:
            return String(localized: "It will be an ancient tree the day you plant it: it has been growing since \(since).",
                          comment: "Seed sheet: Our tree on the day it is planted, when the start date was more than 4 years ago (the Ancient stage). The placeholder is the start date, such as '12 March 2023'.")
        }
    }

    // MARK: Changes

    private func changeBody(_ proposal: GardenProposal) -> some View {
        let tree = targetTree
        let newLook = proposal.look ?? tree?.look ?? .ourTreeDefault
        return BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 0) {
                if let tree {
                    let changes = changedParts(tree: tree, proposal: proposal)
                    if changes.isEmpty {
                        Text("Nothing differs from the tree as it is.",
                             comment: "Seed sheet: a suggested change that matches the tree")
                            .font(JourneyFont.body)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                        if index > 0 { divider }
                        // Two labelled lines, not "old → new": an arrow
                        // between two values points the wrong way in a
                        // right-to-left language.
                        row(change.label) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Currently: \(change.current)",
                                     comment: "Seed sheet, a suggested change to a tree: what one detail of the tree is now, under its label such as 'Place'. The placeholder is the current name, place, day or look, such as 'Café Giảng'.")
                                    .foregroundStyle(Brand.textSecondary)
                                Text("Suggested: \(change.suggested)",
                                     comment: "Seed sheet, a suggested change to a tree: what that detail would become, on the line under 'Currently: …'. The placeholder is the suggested name, place, day or look, such as 'Lisbon'.")
                            }
                        }
                    }
                    if proposal.place != nil {
                        divider
                        placeRow(proposal.place, scene: newLook.scene, tappableSlot: tree.slot)
                    }
                } else {
                    // The tree was let rest while the change waited.
                    Text(GardenCopy.treeResting)
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                }
                noteRow(proposal.note)
            }
        }
    }

    private struct ChangedPart {
        let label: LocalizedStringResource
        let current: String
        let suggested: String
    }

    /// What differs: the name, the place, the day, the look.
    private func changedParts(tree: GardenTree, proposal: GardenProposal) -> [ChangedPart] {
        var parts: [ChangedPart] = []
        if let title = proposal.displayTitle, title != tree.displayTitle {
            parts.append(ChangedPart(label: LocalizedStringResource("Name", comment: "Seed sheet row label: a tree's title"),
                                     current: tree.displayTitle, suggested: title))
        }
        if proposal.place != tree.place {
            parts.append(ChangedPart(label: LocalizedStringResource("Place", comment: "Seed sheet row label: a tree's place"),
                                     current: tree.place?.name ?? noPlace, suggested: proposal.place?.name ?? noPlace))
        }
        if !tree.isOurTree, !sameDay(proposal.momentDay, tree.momentDay) {
            parts.append(ChangedPart(label: LocalizedStringResource("Day", comment: "Seed sheet row label: the tree's day"),
                                     current: tree.momentDay.map(GardenDayText.long(stored:)) ?? noDay,
                                     suggested: proposal.momentDay.map(GardenDayText.long(stored:)) ?? noDay))
        }
        if let look = proposal.look, look != tree.look {
            parts.append(ChangedPart(label: LocalizedStringResource("Look", comment: "Seed sheet row label: a tree's scene and species"),
                                     current: GardenPlaceText.look(tree.look), suggested: GardenPlaceText.look(look)))
        }
        return parts
    }

    private var noPlace: String {
        String(localized: "No place", comment: "Seed sheet: a tree without a place, after 'Currently:' or 'Suggested:' in a suggested change")
    }

    private var noDay: String {
        String(localized: "No day", comment: "Seed sheet: a tree without a moment's day, after 'Currently:' or 'Suggested:' in a suggested change")
    }

    private func sameDay(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?):
            return Calendar.current.isDate(JourneyCalendarDay.localDay(ofStored: a),
                                           inSameDayAs: JourneyCalendarDay.localDay(ofStored: b))
        default: return false
        }
    }

    // MARK: Start date

    private func startDateBody(_ proposal: GardenProposal) -> some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 10) {
                if let newDay = proposal.startDay {
                    if let current = garden.anchor.startDate {
                        Text("\(GardenDayText.long(stored: newDay)) instead of \(GardenDayText.long(stored: current)).",
                             comment: "Start date suggestion: the new day, then the current one, as in '10 March 2023 instead of 12 March 2023.'")
                            .font(JourneyFont.title)
                            .foregroundStyle(Brand.textPrimary)
                    } else {
                        Text(GardenDayText.long(stored: newDay))
                            .font(JourneyFont.title)
                            .foregroundStyle(Brand.textPrimary)
                    }
                    Text("Your day count would be \(GardenDayCount.days(fromStored: newDay, now: garden.now)).",
                         comment: "Start date suggestion: the day count from the suggested day. The placeholder is a number.")
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                }
                noteRow(proposal.note)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startDateConfirmTitle(_ proposal: GardenProposal) -> Text {
        let day = proposal.startDay.map(GardenDayText.long(stored:)) ?? ""
        return Text("Change your start date to \(day)?",
                    comment: "Start date suggestion: confirmation title. The placeholder is a date such as '10 March 2023'.")
    }

    // MARK: Rest

    private func restBody(_ proposal: GardenProposal) -> some View {
        let title = targetTree?.displayTitle ?? proposal.displayTitle ?? ""
        return BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 10) {
                Text("“\(title)” leaves your garden if you agree. Its waterings stay in the journal.",
                     comment: "Rest request: what letting a tree rest means. The placeholder is the tree's title.")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let tree = targetTree, let place = tree.place {
                    placeRow(place, scene: tree.look.scene, tappableSlot: tree.slot)
                }
                noteRow(proposal.note)
            }
        }
    }

    // MARK: Mine, waiting

    @ViewBuilder
    private func waitingBlock(_ proposal: GardenProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let at = proposal.at {
                Text("Waiting for \(partnerName) since \(FutureLetterClock.moment(at, now: garden.now))",
                     comment: "Seed sheet: my seed or request waits. First placeholder: the partner's name; second: a moment such as 'today at 9:14 PM'.")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
            }
            if garden.partner.canGarden == false {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(partnerName) needs the latest Coupley to plant together.",
                         comment: "Garden: the partner's app is too old to answer. The placeholder is the partner's name.")
                        .font(JourneyFont.body)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        confirmsTellPartner = true
                    } label: {
                        Text("Tell \(partnerName)", comment: "Garden: offer to send the partner a Chat message about updating. The placeholder is the partner's name.")
                            .font(JourneyFont.label)
                            .foregroundStyle(Brand.accentStart)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ proposal: GardenProposal) -> some View {
        VStack(spacing: 10) {
            if showsError, let message = garden.errorMessage {
                statusText(message)
            }
            if isMine {
                mineControls(proposal)
            } else {
                answerControls(proposal)
            }
            if !reachability.isOnline {
                statusText(GardenError.offline.message(partnerName: partnerName, now: garden.now))
            }
        }
    }

    @ViewBuilder
    private func answerControls(_ proposal: GardenProposal) -> some View {
        switch proposal.kind {
        case .plant:
            let duplicate = myDuplicate
            GardenHoldToPlantButton(
                title: duplicate == nil
                    ? String(localized: "Hold to plant together", comment: "Seed sheet: the press-and-hold planting control")
                    : String(localized: "Hold to plant \(partnerName)'s",
                             comment: "Seed sheet: plant the partner's seed instead of my own duplicate. The placeholder is the partner's name."),
                spokenLabel: duplicate == nil
                    ? String(localized: "Plant it together", comment: "VoiceOver: the press-and-hold planting control; one activation plants")
                    : String(localized: "Plant \(partnerName)'s seed",
                             comment: "VoiceOver: the planting control when both partners sent a seed for the same kind of tree; one activation plants the partner's seed. The placeholder is the partner's first name."),
                spokenHint: duplicate.map { mine in
                    String(localized: "Also takes back your own seed for “\(mine.displayTitle ?? proposal.displayTitle ?? "")”.",
                           comment: "VoiceOver hint of the planting control when both partners sent a seed for the same kind of tree: planting the partner's seed also withdraws the user's own. The placeholder is that tree's title, such as 'Our first date'.")
                },
                isEnabled: canAct, isBusy: isActing) {
                plant(proposal)
            }
            BrandCTA(title: String(localized: "Suggest a change", comment: "Seed sheet: answer the partner's seed with my own version"),
                     tier: .card, isEnabled: canAct) {
                if let seen = proposal.version { pushed = .form(.counter(seen)) }
            }
            textButton(String(localized: "Not now", comment: "Seed sheet: hide this seed for a few days on this phone"),
                       isEnabled: true) {
                garden.snooze(proposalId)
                dismiss()
            }
        case .change, .startDate, .rest:
            BrandCTA(title: proposal.kind == .rest
                        ? String(localized: "Let it rest", comment: "Rest request: agree to let the tree rest")
                        : String(localized: "Agree", comment: "Change or start date suggestion: agree to it"),
                     tier: .hero, isEnabled: canAct, isBusy: isActing) {
                if proposal.kind == .startDate {
                    confirmsStartDate = true
                } else {
                    agree(proposal)
                }
            }
            textButton(String(localized: "Keep it as it is", comment: "Seed sheet: decline a suggested change, start date or rest")) {
                act { await garden.letGo(proposalId) }
            }
        }
    }

    @ViewBuilder
    private func mineControls(_ proposal: GardenProposal) -> some View {
        switch proposal.kind {
        case .plant:
            BrandCTA(title: String(localized: "Edit seed", comment: "Seed sheet: edit my own seed"),
                     tier: .card, isEnabled: canAct) {
                if let seen = proposal.version { pushed = .form(.editSeed(seen)) }
            }
            textButton(String(localized: "Take it back", comment: "Seed sheet: withdraw my seed or request")) {
                confirmsTakeBack = true
            }
        case .change, .startDate:
            BrandCTA(title: String(localized: "Edit", comment: "Seed sheet: edit my own suggestion"),
                     tier: .card, isEnabled: canAct) {
                guard let seen = proposal.version else { return }
                pushed = proposal.kind == .change ? .form(.editChange(seen)) : .startDate
            }
            textButton(String(localized: "Take it back", comment: "Seed sheet: withdraw my seed or request")) {
                act { await garden.takeBack(proposalId) }
            }
        case .rest:
            textButton(String(localized: "Take it back", comment: "Seed sheet: withdraw my seed or request")) {
                act { await garden.takeBack(proposalId) }
            }
        }
    }

    /// A text button; answers are disabled offline and while one runs.
    private func textButton(_ title: String, isEnabled: Bool? = nil, action: @escaping () -> Void) -> some View {
        let enabled = isEnabled ?? canAct
        return Button(action: action) {
            Text(title)
                .font(JourneyFont.label)
                .foregroundStyle(enabled ? Brand.accentStart : Brand.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(!enabled)
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(JourneyFont.meta)
            .foregroundStyle(Brand.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: Rows

    private func row<Value: View>(_ label: LocalizedStringResource, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(JourneyFont.caption)
                .foregroundStyle(Brand.textSecondary)
            value()
                .font(JourneyFont.label)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func placeRow(_ place: GardenPlace?, scene: GardenSceneID, tappableSlot: GardenSlot?) -> some View {
        if let place {
            divider
            VStack(alignment: .leading, spacing: 8) {
                row(LocalizedStringResource("Place", comment: "Seed sheet row label: a tree's place")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                        if let locality = place.locality, locality != place.name {
                            Text(locality)
                                .font(JourneyFont.meta)
                                .foregroundStyle(Brand.textSecondary)
                        }
                    }
                }
                GeometryReader { proxy in
                    let snapshot = GardenSnapshotImage(place: place, scene: scene,
                                                       size: CGSize(width: proxy.size.width, height: 120))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: Brand.cornerStyle))
                    if let tappableSlot {
                        Button {
                            onOpenTree(tappableSlot)
                        } label: {
                            snapshot
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.98))
                    } else {
                        snapshot
                    }
                }
                .frame(height: 120)
                .padding(.bottom, 8)
            }
        }
    }

    private func lookRow(_ look: GardenLook) -> some View {
        HStack(spacing: 12) {
            row(LocalizedStringResource("Look", comment: "Seed sheet row label: a tree's scene and species")) {
                Text(GardenPlaceText.look(look))
            }
            GardenSceneSwatch(scene: look.scene, size: CGSize(width: 56, height: 40))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: Brand.cornerStyle))
        }
    }

    @ViewBuilder
    private func noteRow(_ note: String?) -> some View {
        if let note, !note.isEmpty {
            divider
            row(isMine
                ? LocalizedStringResource("Your note", comment: "Seed sheet row label: the note I sent with my seed or request")
                : LocalizedStringResource("From \(partnerName)", comment: "Seed sheet row label: the partner's note. The placeholder is the partner's name.")) {
                Text("“\(note)”", comment: "A quoted note. The placeholder is the note's text.")
                    .font(JourneyFont.body)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Brand.divider).frame(height: 1)
    }

    // MARK: Gone

    private var goneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf")
                .font(.largeTitle)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text(goneMessage)
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Brand.Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The failed answer's own error; else what became of my own seed or
    /// request; else the partner's: "Sam took this back."
    private var goneMessage: String {
        if showsError, let message = garden.errorMessage { return message }
        guard let shown = lastShown, shown.by == garden.session.userId else {
            return GardenError.gone.message(partnerName: partnerName, now: garden.now)
        }
        // Change, start date and rest requests carry their tree's key.
        let tree = shown.targetSlot.flatMap(garden.tree)
        switch shown.kind {
        case .plant:
            // A tree carries its key; Our tree's seed is also planted once
            // a start date exists (an older app plants it with the date).
            if garden.docs.trees.contains(where: { $0.key == shown.key })
                || (shown.id == GardenDocID.seedOurTree && garden.anchor.exists) {
                return GardenError.alreadyPlanted.message(partnerName: partnerName, now: garden.now)
            }
            return GardenCopy.seedSetAside(partnerName: partnerName, title: shown.displayTitle ?? "")
        case .change:
            guard let tree else { return GardenCopy.treeResting }
            if wasAgreed(shown, tree: tree) {
                return String(localized: "\(partnerName) agreed to your change.",
                              comment: "Seed sheet: replaces my suggested change to a tree when the partner agrees to it while I look at it. The placeholder is the partner's first name.")
            }
            return String(localized: "\(partnerName) chose to keep “\(tree.displayTitle)” as it is.",
                          comment: "Seed sheet: replaces my suggested change to a tree when the partner declines it while I look at it. First placeholder: the partner's first name; second: the tree's title, such as 'Our first trip'.")
        case .startDate:
            // The agreement can reach the start date's listener first.
            if wasAgreed(shown, tree: tree) || sameDay(garden.anchor.startDate, shown.startDay) {
                return String(localized: "\(partnerName) agreed to your new start date.",
                              comment: "Seed sheet: replaces my suggested start date when the partner agrees to it while I look at it. The placeholder is the partner's first name.")
            }
            if let start = garden.anchor.startDate, let from = shown.fromStartDay, !sameDay(start, from) {
                return GardenCopy.startDateChangedElsewhere(storedDay: start)
            }
            return String(localized: "\(partnerName) chose to keep the start date as it is.",
                          comment: "Seed sheet: replaces my suggested start date when the partner declines it while I look at it. The placeholder is the partner's first name.")
        case .rest:
            guard let tree else { return GardenCopy.treeResting }
            return String(localized: "\(partnerName) chose to keep “\(tree.displayTitle)”.",
                          comment: "Seed sheet: replaces my request to let a tree rest when the partner declines it (the tree stays) while I look at it. First placeholder: the partner's first name; second: the tree's title, such as 'Our first trip'.")
        }
    }

    /// The tree records its agreement to this request, made after the
    /// version shown (an older agreement to an earlier request does not count).
    private func wasAgreed(_ shown: GardenProposal, tree: GardenTree?) -> Bool {
        guard let tree, tree.fromProposal == shown.id,
              tree.agreementKind == (shown.kind == .startDate ? .startDate : .change),
              let agreedAt = tree.agreementAt, let at = shown.at else { return false }
        return agreedAt >= at
    }

    // MARK: Pushed

    @ViewBuilder
    private func destination(_ route: Pushed) -> some View {
        switch route {
        case .form(let form):
            GardenPlantForm(garden: garden, mode: mode(for: form)) {
                pushed = nil
            }
        case .startDate:
            GardenStartDateSuggestionView(garden: garden, proposal: proposal) {
                pushed = nil
            }
        }
    }

    private func mode(for route: GardenFormRoute) -> GardenDraft.Mode {
        switch route {
        case .editSeed(let seen):   return .editSeed(id: proposalId, seen: seen)
        case .counter(let seen):    return .counter(id: proposalId, seen: seen)
        case .editChange(let seen): return .editChange(id: proposalId, seen: seen)
        }
    }

    // MARK: Actions

    /// Runs one answer; closes on success, shows the error under the controls otherwise.
    private func act(_ operation: @escaping () async -> Bool) {
        isActing = true
        showsError = false
        Task {
            let succeeded = await operation()
            if succeeded { isFinished = true }
            isActing = false
            if succeeded {
                dismiss()
            } else {
                showsError = true
            }
        }
    }

    private func plant(_ proposal: GardenProposal) {
        guard let seen = proposal.version else { return }
        let alsoDelete = myDuplicate?.id
        isActing = true
        showsError = false
        Task {
            let succeeded = await garden.plant(proposalId, seen: seen, alsoDelete: alsoDelete)
            if succeeded { isFinished = true }
            isActing = false
            if succeeded {
                onPlanted()
                dismiss()
            } else {
                showsError = true
            }
        }
    }

    private func agree(_ proposal: GardenProposal) {
        guard let seen = proposal.version else { return }
        act { await garden.agree(proposalId, seen: seen) }
    }
}

// MARK: - Start date, edited

/// My own waiting start-date suggestion, edited (B5.7 in short): the
/// suggestion keeps its id; sending it again replaces it.
private struct GardenStartDateSuggestionView: View {

    @ObservedObject var garden: GardenViewModel
    let proposal: GardenProposal?
    let onDone: () -> Void

    @ObservedObject private var reachability = GardenReachability.shared
    @State private var day: Date
    @State private var note: String
    @State private var isSending = false
    @State private var failed = false

    init(garden: GardenViewModel, proposal: GardenProposal?, onDone: @escaping () -> Void) {
        self.garden = garden
        self.proposal = proposal
        self.onDone = onDone
        _day = State(initialValue: proposal?.startDay.map { JourneyCalendarDay.localDay(ofStored: $0) }
                     ?? Calendar.current.startOfDay(for: Date()))
        _note = State(initialValue: proposal?.note ?? "")
    }

    /// The day already suggested, or the current start date: nothing to send.
    private var isUnchanged: Bool {
        let calendar = Calendar.current
        let current = garden.anchor.startDate.map { JourneyCalendarDay.localDay(ofStored: $0) }
        let suggested = proposal?.startDay.map { JourneyCalendarDay.localDay(ofStored: $0) }
        let sameNote = GardenLimits.seedNote.clean(note) == GardenLimits.seedNote.clean(proposal?.note)
        return current.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            || (suggested.map { calendar.isDate($0, inSameDayAs: day) } ?? false && sameNote)
    }

    var body: some View {
        Form {
            Section {
                DatePicker(selection: Binding(get: { day }, set: { day = Calendar.current.startOfDay(for: $0) }),
                           in: ...Date(), displayedComponents: [.date]) {
                    Text("Start date", comment: "Start date sheet: VoiceOver label of the calendar")
                }
                .datePickerStyle(.graphical)
                .tint(Brand.accentStart)
                .labelsHidden()
            } header: {
                Text("When did it begin?", comment: "Start date sheet heading")
                    .font(JourneyFont.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
            Section {
                TextField(text: Binding(get: { note }, set: { note = GardenLimits.seedNote.truncate($0) }),
                          axis: .vertical) {
                    Text("A note for \(garden.partnerName) (optional)",
                         comment: "Start date sheet: placeholder of the note. The placeholder is the partner's name.")
                }
                .font(JourneyFont.body)
                .lineLimit(2...5)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.bgGradient.ignoresSafeArea())
        .navigationTitle(Text("Start date", comment: "Start date sheet title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if failed, let message = garden.errorMessage {
                    Text(message)
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                }
                BrandCTA(title: String(localized: "Suggest this date", comment: "Start date sheet: the filled button in suggest mode"),
                         tier: .hero,
                         isEnabled: reachability.isOnline && !isUnchanged,
                         isBusy: isSending) {
                    send()
                }
                if !reachability.isOnline {
                    Text(GardenError.offline.message(partnerName: garden.partnerName, now: garden.now))
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Brand.Space.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(.bar)
        }
    }

    private func send() {
        isSending = true
        failed = false
        Task {
            let succeeded = await garden.suggestStartDate(day: day, note: GardenLimits.seedNote.clean(note))
            isSending = false
            if succeeded { onDone() } else { failed = true }
        }
    }
}

// MARK: - Hold to plant

/// The seed sheet's one fill: a ring fills around a seed glyph while the
/// finger stays down (0.6 s), a soft tap on touch-down and a rigid one on
/// completion; letting go early rewinds in 0.2 s. One activation plants for
/// VoiceOver, Switch Control and Voice Control.
///
/// While it can't plant (offline, a pending version, a planting on its way)
/// it is disabled, so VoiceOver reads it dimmed; Voice Control answers to
/// the words on it as well as to the spoken label.
struct GardenHoldToPlantButton: View {

    /// The words on the control ("Hold to plant together").
    let title: String
    /// What VoiceOver says: one activation plants, so it never says "hold".
    let spokenLabel: String
    /// Said after the label when planting does more than plant.
    let spokenHint: String?
    let isEnabled: Bool
    let isBusy: Bool
    let action: () -> Void

    static let holdDuration: TimeInterval = 0.6

    @State private var progress: CGFloat = 0
    @State private var hold: Task<Void, Never>?

    init(title: String, spokenLabel: String, spokenHint: String? = nil,
         isEnabled: Bool, isBusy: Bool, action: @escaping () -> Void) {
        self.title = title
        self.spokenLabel = spokenLabel
        self.spokenHint = spokenHint
        self.isEnabled = isEnabled
        self.isBusy = isBusy
        self.action = action
    }

    private var canPlant: Bool { isEnabled && !isBusy }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .ringStartsAtTop()
                if isBusy {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 30, height: 30)
            Text(title)
                .font(BrandType.cta)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: Brand.buttonCornerRadius, style: Brand.cornerStyle)
                .fill(Brand.accentStart.opacity(isEnabled ? 1 : 0.35))
        )
        .scaleEffect(hold != nil ? 0.98 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hold != nil)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in begin() }
                .onEnded { _ in release() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityValue(isBusy
                            ? Text("Planting…", comment: "VoiceOver: the value of the planting control while the planting is on its way")
                            : Text(verbatim: ""))
        .accessibilityHint(Text(verbatim: spokenHint ?? ""))
        .accessibilityInputLabels([Text(verbatim: title), Text(verbatim: spokenLabel)])
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard canPlant else { return }
            action()
        }
        // Blocks the hold and the activation alike, and reads as dimmed.
        .disabled(!canPlant)
        // A hold under way when it can no longer plant rewinds (the gesture
        // that would have ended it is cancelled with the touch).
        .onChange(of: canPlant) { _, can in
            if !can { release() }
        }
        .onDisappear { hold?.cancel() }
    }

    private func begin() {
        guard hold == nil, canPlant else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
        hold = Task {
            try? await Task.sleep(for: .seconds(Self.holdDuration))
            guard !Task.isCancelled else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            hold = nil
            action()
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        }
    }

    /// Lifting early rewinds; after completion it does nothing.
    private func release() {
        guard let running = hold else { return }
        running.cancel()
        hold = nil
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

// MARK: - Seed packet

/// A kraft seed packet: a cream label with the title, a stamp with the
/// scene's symbol and a round postmark with the day. Shapes and SwiftUI
/// text only.
struct GardenSeedPacket: View {

    let title: String
    let stampSymbol: String
    /// "12 MAR 2023", or nil for no day.
    let postmark: String?
    let height: CGFloat

    private static let kraft = GardenRGB(0xD9B98C).color
    private static let flap = GardenRGB(0xC9A574).color
    private static let cream = GardenRGB(0xFBF4E4).color
    private static let ink = GardenRGB(0x6B4E2E).color

    var body: some View {
        let width = height * 0.74
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: height * 0.04, style: .continuous)
                .fill(Self.kraft)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            // The folded flap.
            UnevenRoundedRectangle(topLeadingRadius: height * 0.04, topTrailingRadius: height * 0.04, style: .continuous)
                .fill(Self.flap)
                .frame(height: height * 0.16)

            VStack(spacing: height * 0.05) {
                // Clears the stamp (0.04…0.24 of the height).
                Spacer(minLength: height * 0.26)
                Text(title)
                    .font(height >= 120 ? JourneyFont.title : JourneyFont.meta)
                    .foregroundStyle(Self.ink)
                    .multilineTextAlignment(.center)
                    // Titles run long in many languages; the small packet
                    // on the request card has room for four short lines.
                    .lineLimit(height >= 120 ? 3 : 4)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Self.cream))
                    .padding(.horizontal, width * 0.1)
                Spacer(minLength: 0)
            }

            // The stamp, top right across the flap's fold, with the scene's
            // symbol. Above the label, never over its words.
            Image(systemName: stampSymbol)
                .font(.system(size: height * 0.08, weight: .semibold))
                .foregroundStyle(Self.ink)
                .frame(width: height * 0.17, height: height * 0.2)
                .background(Rectangle().fill(Self.cream))
                .overlay(Rectangle().strokeBorder(Self.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, height * 0.04)
                .padding(.trailing, width * 0.07)

            if let postmark, height >= 120 {
                Text(verbatim: postmark)
                    .font(JourneyFont.meta)
                    .foregroundStyle(Self.ink.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(8)
                    .frame(width: height * 0.4, height: height * 0.4)
                    .overlay(Circle().strokeBorder(Self.ink.opacity(0.55), lineWidth: 1.5))
                    .rotationEffect(.degrees(-12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(width * 0.06)
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(postmark.map {
            String(localized: "Seed packet: \(title), \($0)",
                   comment: "VoiceOver: a seed packet. First placeholder: the tree's title; second: its day.")
        } ?? String(localized: "Seed packet: \(title)",
                    comment: "VoiceOver: a seed packet. The placeholder is the tree's title."))
    }
}

// MARK: - Previews

#Preview("Seed packet") {
    HStack(spacing: 24) {
        GardenSeedPacket(title: "Our first trip", stampSymbol: "mountain.2", postmark: "12 MAR 2023", height: 180)
        GardenSeedPacket(title: "Where we first met", stampSymbol: "leaf", postmark: nil, height: 72)
    }
    .padding()
}

#Preview("Hold to plant") {
    VStack(spacing: 16) {
        GardenHoldToPlantButton(title: "Hold to plant together", spokenLabel: "Plant it together",
                                isEnabled: true, isBusy: false) {}
        GardenHoldToPlantButton(title: "Hold to plant together", spokenLabel: "Plant it together",
                                isEnabled: false, isBusy: false) {}
    }
    .padding()
}
