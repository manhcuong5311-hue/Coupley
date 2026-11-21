//
//  GardenRequestsSection.swift
//  Coupley
//
//  Under the garden hero (spec B4): the cards for what waits for ME (at most
//  two, then "1 more request"), and the quiet zone (what waits for the
//  partner, one-time notices, the "home" invite).
//
//  Cards are outlined (BrandCTA .card and text buttons): the hero or the
//  masthead + keeps the screen's one fill. Every answer passes the version
//  of the request the user was shown (`seen`) and is disabled while it is
//  nil (a pending write). Our tree's own seed is not a card: the planting
//  hero shows it (B3.3, B3.4). The whole section hides until the garden is
//  ready (loading, unavailable).
//

import Foundation
import SwiftUI
import UIKit

struct GardenRequestsSection: View {

    @ObservedObject var garden: GardenViewModel
    /// Opens a seed, change, start-date or rest request (the seed sheet).
    let onOpenRequest: (String) -> Void
    /// "1 more request": the Garden sheet.
    let onOpenGarden: () -> Void
    /// The invite's "Choose a place": Our tree's change flow.
    let onChoosePlace: () -> Void
    /// "Tell Sam": Journey confirms, then sends the chat line.
    let onTellPartner: () -> Void

    init(garden: GardenViewModel,
         onOpenRequest: @escaping (String) -> Void = { _ in },
         onOpenGarden: @escaping () -> Void = {},
         onChoosePlace: @escaping () -> Void = {},
         onTellPartner: @escaping () -> Void = {}) {
        self.garden = garden
        self.onOpenRequest = onOpenRequest
        self.onOpenGarden = onOpenGarden
        self.onChoosePlace = onChoosePlace
        self.onTellPartner = onTellPartner
    }

    /// The start-date suggestion waiting for "Change it" in the confirmation.
    @State private var confirmingStartDate: GardenRequestModel?

    private static let maxCards = 2

    var body: some View {
        if garden.availability == .ready {
            let forMe = garden.requests.filter { !$0.isMine && $0.kind != .ourTreeSeed }
            let cards = forMe.filter { !$0.isSnoozed }
            let snoozed = forMe.filter { $0.isSnoozed }
            let mine = garden.requests.filter { $0.isMine && $0.kind != .ourTreeSeed }
            let notice = garden.notices.first { $0.kind != .homeInvite }
            let invite = garden.notices.first { $0.kind == .homeInvite }
            let legacy = garden.partner.canGarden == false && !mine.isEmpty
            let hasQuietRows = !mine.isEmpty || !snoozed.isEmpty || legacy || notice != nil

            if !cards.isEmpty || hasQuietRows || invite != nil {
                VStack(alignment: .leading, spacing: Brand.Space.sibling) {
                    ForEach(cards.prefix(Self.maxCards)) { request in
                        requestCard(request)
                    }
                    if cards.count > Self.maxCards {
                        moreButton(count: cards.count - Self.maxCards)
                    }
                    if hasQuietRows {
                        BrandCard(tier: .quiet) {
                            VStack(alignment: .leading, spacing: 12) {
                                waitingForPartnerRows(mine)
                                if !snoozed.isEmpty { snoozedRow(snoozed) }
                                if legacy { legacyRow }
                                if let notice { noticeRow(notice) }
                            }
                        }
                    }
                    if let invite {
                        inviteCard(invite)
                    }
                }
                // Its own gap under the hero, so nothing is left when it is empty.
                .padding(.top, Brand.Space.sibling)
                .alert(startDateQuestion, isPresented: Binding(
                    get: { confirmingStartDate != nil },
                    set: { if !$0 { confirmingStartDate = nil } }
                ), presenting: confirmingStartDate) { request in
                    Button {
                        agree(request)
                    } label: {
                        Text("Change it", comment: "Garden: confirm agreeing to the partner's new start date")
                    }
                    Button(role: .cancel) {} label: {
                        Text("Cancel", comment: "Button: close the menu without doing anything")
                    }
                } message: { _ in
                    Text("Your tree, anniversaries and crowns will count from that day, for both of you.",
                         comment: "Garden: message of the confirmation before agreeing to a new start date")
                }
            }
        }
    }

    // MARK: - Cards for me

    private func requestCard(_ request: GardenRequestModel) -> some View {
        let busy = garden.busyProposalIds.contains(request.id)
        return BrandCard(tier: .card) {
            HStack(alignment: .top, spacing: 14) {
                if request.kind == .seed {
                    let proposal = garden.proposal(id: request.id)
                    GardenSeedPacket(title: proposal?.displayTitle ?? "",
                                     stampSymbol: proposal?.look?.scene.info.stampSymbol
                                        ?? GardenSceneID.meadow.info.stampSymbol,
                                     postmark: nil, height: 72)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.title)
                            .font(JourneyFont.title)
                            .foregroundStyle(Brand.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(request.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(JourneyFont.body)
                                .foregroundStyle(index == 0 ? Brand.textPrimary : Brand.textSecondary)
                                // A seed's second line is the partner's note: one line.
                                .lineLimit(request.kind == .seed && index > 0 ? 1 : nil)
                                .fixedSize(horizontal: false, vertical: request.kind != .seed || index == 0)
                        }
                    }
                    BrandCTA(title: request.primaryTitle, tier: .card,
                             isEnabled: opensSheet(request) || request.seen != nil,
                             isBusy: busy) {
                        primaryAction(request)
                    }
                    .padding(.top, 2)
                    if let secondary = request.secondaryTitle {
                        Button {
                            secondaryAction(request)
                        } label: {
                            Text(secondary)
                                .font(JourneyFont.label)
                                .foregroundStyle(Brand.accentStart)
                                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                }
            }
        }
    }

    /// Seeds and changes open the seed sheet, where the answer is given.
    private func opensSheet(_ request: GardenRequestModel) -> Bool {
        request.kind == .seed || request.kind == .change || request.kind == .ourTreeSeed
    }

    private func primaryAction(_ request: GardenRequestModel) {
        switch request.kind {
        case .seed, .ourTreeSeed, .change:
            onOpenRequest(request.id)
        case .startDate:
            confirmingStartDate = request
        case .rest:
            agree(request)
        }
    }

    /// "Not now" snoozes a seed on this device; "Keep 12 March" and "Keep
    /// it" decline (the request is deleted).
    private func secondaryAction(_ request: GardenRequestModel) {
        switch request.kind {
        case .seed, .ourTreeSeed:
            garden.snooze(request.id)
        case .change, .startDate, .rest:
            Task { _ = await garden.letGo(request.id) }
        }
    }

    private func agree(_ request: GardenRequestModel) {
        guard let seen = request.seen else { return }
        Task { _ = await garden.agree(request.id, seen: seen) }
    }

    private var startDateQuestion: Text {
        guard let request = confirmingStartDate,
              let day = garden.proposal(id: request.id)?.startDay else {
            return Text(verbatim: "")
        }
        let date = GardenCopy.longDay(stored: day)
        return Text("Change your start date to \(date)?",
                    comment: "Garden: confirmation before agreeing to the partner's new start date. %@ is a date such as '10 March 2023'.")
    }

    private func moreButton(count: Int) -> some View {
        Button(action: onOpenGarden) {
            Text(GardenCopy.moreRequests(count))
                .font(JourneyFont.label)
                .foregroundStyle(Brand.accentStart)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - The quiet zone

    /// What waits for the partner: one row each, or one row for several of
    /// my seeds ("Waiting for Sam · 2 seeds").
    @ViewBuilder
    private func waitingForPartnerRows(_ mine: [GardenRequestModel]) -> some View {
        let seeds = mine.filter { $0.kind == .seed }
        let others = mine.filter { $0.kind != .seed }
        if seeds.count > 1 {
            quietRow(GardenCopy.waitingSeeds(partnerName: garden.partnerName, count: seeds.count),
                     action: onOpenGarden)
        } else if let seed = seeds.first {
            quietRow(seed.title) { onOpenRequest(seed.id) }
        }
        ForEach(others) { request in
            quietRow(request.title) { onOpenRequest(request.id) }
        }
    }

    private func quietRow(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Seeds I said "Not now" to, collapsed: "1 seed from Sam · See". The
    /// first opens.
    private func snoozedRow(_ snoozed: [GardenRequestModel]) -> some View {
        quietRow(GardenCopy.snoozedSeeds(count: snoozed.count, partnerName: garden.partnerName)) {
            if let first = snoozed.first { onOpenRequest(first.id) }
        }
    }

    /// "Sam needs the latest Coupley to answer · Tell Sam".
    private var legacyRow: some View {
        let partner = garden.partnerName
        return inlineLink(GardenCopy.partnerNeedsUpdateToAnswer(partnerName: partner),
                          link: GardenCopy.tellPartner(partnerName: partner),
                          action: onTellPartner)
    }

    /// "Text · Link" with the link tappable, wrapping as one sentence.
    private func inlineLink(_ text: String, link: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            (Text(text) + Text(verbatim: " · ") + Text(link).foregroundStyle(Brand.accentStart))
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One notice at a time; its action ("OK" records a legacy change,
    /// "Change it back", "Water again") or its dismissal.
    private func noticeRow(_ notice: GardenNotice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(notice.text)
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                if let action = notice.actionTitle {
                    textButton(action) {
                        Task { await garden.perform(notice) }
                    }
                }
                if let dismissal = notice.dismissTitle {
                    textButton(dismissal) {
                        garden.dismiss(notice)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A text link with a 44 pt target ("OK", "Change it back", "Not now").
    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(JourneyFont.label)
                .foregroundStyle(Brand.accentStart)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - The invite

    /// "Give your tree a home", once (a card, not quiet).
    private func inviteCard(_ notice: GardenNotice) -> some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 10) {
                Text(notice.title ?? GardenCopy.homeInviteTitle)
                    .font(JourneyFont.title)
                    .foregroundStyle(Brand.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(notice.text)
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Choosing answers the invitation (it does not come back, and
                // Our tree offers "Add a place"); its prefill stays for the flow.
                BrandCTA(title: notice.actionTitle ?? GardenCopy.chooseAPlace,
                         icon: "mappin", tier: .card) {
                    garden.acceptHomeInvite()
                    onChoosePlace()
                }
                .padding(.top, 2)
                textButton(notice.dismissTitle ?? GardenCopy.notNow) {
                    garden.dismiss(notice)
                }
            }
        }
    }
}

// MARK: - Preview

// Builds a GardenViewModel on the in-memory service, so DEBUG only (K7).
#if DEBUG
#Preview("Requests · a seed and a rest request") {
    let service = InMemoryGardenService()
    let garden = GardenViewModel(session: GardenLab.session, service: service)
    ScrollView {
        GardenRequestsSection(garden: garden)
            .padding(.horizontal, Brand.Space.gutter)
    }
    .background(Brand.bgGradient.ignoresSafeArea())
    .onAppear {
        garden.start()
        service.simulatePartner(.sendSeed(.firstDate))
    }
}
#endif
