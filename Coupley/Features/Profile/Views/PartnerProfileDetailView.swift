//
//  PartnerProfileDetailView.swift
//  Coupley
//
//  Detail screen for either "Me" or "Partner". Both viewers can add hints
//  (attributed with a gendered "by He / by She" tag when the contributor
//  isn't the profile owner); only the profile owner can edit free-text
//  sections like communication style and notes.
//

import SwiftUI

// MARK: - Profile Detail Screen

struct PartnerProfileDetailView: View {

    @StateObject private var viewModel: PartnerProfileDetailViewModel
    @EnvironmentObject private var premiumStore: PremiumStore
    let avatar: AvatarOption
    let displayName: String
    /// Pronoun label for the *non-owner* contributor, used in attribution
    /// chips ("by He / by She / by Them"). Derived from the partner's avatar
    /// in both viewing modes.
    let partnerPronounLabel: String

    @Environment(\.dismiss) private var dismiss

    @State private var likeDraft: String = ""
    @State private var dislikeDraft: String = ""
    @State private var activityDraft: String = ""
    @State private var showCreateCustomQuiz = false
    @State private var showCustomQuizPaywall = false

    init(
        targetUserId: String,
        currentUserId: String,
        mode: PartnerProfileDetailViewModel.Mode,
        hasPartner: Bool,
        avatar: AvatarOption,
        displayName: String,
        partnerPronounLabel: String
    ) {
        _viewModel = StateObject(
            wrappedValue: PartnerProfileDetailViewModel(
                targetUserId: targetUserId,
                currentUserId: currentUserId,
                mode: mode,
                hasPartner: hasPartner
            )
        )
        self.avatar = avatar
        self.displayName = displayName
        self.partnerPronounLabel = partnerPronounLabel
    }

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let error = viewModel.errorMessage {
                        banner(error)
                    }
                    likesSection
                    dislikesSection
                    communicationSection
                    notesSection
                    activitiesSection
                    customQuizSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(viewModel.mode == .mine ? "My Profile" : "\(displayName)'s Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Brand.textSecondary)
            }
            if viewModel.isSaving {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView().tint(Brand.accentStart)
                }
            }
        }
        .onAppear  { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .sheet(isPresented: $showCreateCustomQuiz) {
            CreateCustomQuizSheet { question, options, selected in
                viewModel.addCustomAnswer(question: question, options: options, selected: selected)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCustomQuizPaywall) {
            NavigationStack { PremiumPaywallView() }
                .environmentObject(premiumStore)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Brand.backgroundTop)
                    .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                avatar.image()
                    .clipShape(Circle())
                    .padding(3)
            }
            .frame(width: 88, height: 88)
            .shadow(color: .black.opacity(0.15), radius: 14, y: 4)

            Text(displayName)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Text(headerSubtitle)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var headerSubtitle: String {
        switch viewModel.mode {
        case .mine:
            return "Keep this up to date — your partner sees it and can add hints too."
        case .partner:
            return "Add hints about what they love — they'll see who added each one."
        }
    }

    // MARK: - Sections

    private var likesSection: some View {
        ChipSection(
            title: "Likes",
            icon: "heart.fill",
            tint: Brand.accentStart,
            items: viewModel.profile.likes,
            addedBy: viewModel.profile.likesAddedBy,
            attributionFor: attributionFor,
            canRemove: { viewModel.canRemove(addedBy: viewModel.profile.likesAddedBy[$0]) },
            canAdd: viewModel.canAdd,
            draft: $likeDraft,
            placeholder: "+ Add like",
            emptyMessage: "No likes added yet",
            onAdd: { viewModel.addLike($0) },
            onRemove: { viewModel.removeLike($0) }
        )
    }

    private var dislikesSection: some View {
        ChipSection(
            title: "Dislikes",
            icon: "hand.raised.fill",
            tint: Color(red: 1.0, green: 0.55, blue: 0.25),
            items: viewModel.profile.dislikes,
            addedBy: viewModel.profile.dislikesAddedBy,
            attributionFor: attributionFor,
            canRemove: { viewModel.canRemove(addedBy: viewModel.profile.dislikesAddedBy[$0]) },
            canAdd: viewModel.canAdd,
            draft: $dislikeDraft,
            placeholder: "+ Add dislike",
            emptyMessage: "No dislikes added yet",
            onAdd: { viewModel.addDislike($0) },
            onRemove: { viewModel.removeDislike($0) }
        )
    }

    private var communicationSection: some View {
        SectionCard(title: "Communication Style", icon: "bubble.left.and.bubble.right.fill", tint: Color(red: 0.40, green: 0.70, blue: 1.0)) {
            if viewModel.canEditFreeText {
                TextField(
                    "e.g. Direct, playful, needs space when stressed",
                    text: Binding(
                        get: { viewModel.profile.communicationStyle },
                        set: { viewModel.updateCommunicationStyle($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            } else {
                Text(viewModel.profile.communicationStyle.isEmpty
                     ? "No preferences added yet"
                     : viewModel.profile.communicationStyle)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(viewModel.profile.communicationStyle.isEmpty
                                     ? Brand.textTertiary
                                     : Brand.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var notesSection: some View {
        SectionCard(title: "Notes", icon: "note.text", tint: Color(red: 0.50, green: 0.40, blue: 1.0)) {
            if viewModel.canEditFreeText {
                TextField(
                    "Anything you want to remember…",
                    text: Binding(
                        get: { viewModel.profile.notes },
                        set: { viewModel.updateNotes($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(3...8)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            } else {
                Text(viewModel.profile.notes.isEmpty
                     ? "No notes yet"
                     : viewModel.profile.notes)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(viewModel.profile.notes.isEmpty
                                     ? Brand.textTertiary
                                     : Brand.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var activitiesSection: some View {
        ChipSection(
            title: "Our Activities",
            icon: "sparkles",
            tint: Color(red: 1.0, green: 0.55, blue: 0.20),
            items: viewModel.profile.activities,
            addedBy: viewModel.profile.activitiesAddedBy,
            attributionFor: attributionFor,
            canRemove: { viewModel.canRemove(addedBy: viewModel.profile.activitiesAddedBy[$0]) },
            canAdd: viewModel.canAdd,
            draft: $activityDraft,
            placeholder: "+ Add activity",
            emptyMessage: "No shared activities yet",
            onAdd: { viewModel.addActivity($0) },
            onRemove: { viewModel.removeActivity($0) }
        )
    }

    // MARK: - Custom Q&A (premium)

    @ViewBuilder
    private var customQuizSection: some View {
        SectionCard(
            title: "Custom Q&A",
            icon: "pencil.and.list.clipboard",
            tint: Color(red: 0.85, green: 0.40, blue: 0.80)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.profile.customAnswers.isEmpty {
                    Text(customEmptyMessage)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewModel.profile.customAnswers) { entry in
                        customAnswerCard(entry)
                    }
                }

                if viewModel.canEditCustomAnswers {
                    createCustomButton
                }
            }
        }
    }

    private var customEmptyMessage: String {
        switch viewModel.mode {
        case .mine:    return "Write your own questions and share what you love."
        case .partner: return "\(displayName) hasn't added any custom Q&A yet."
        }
    }

    private var createCustomButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if premiumStore.hasAccess(to: .customQuizzes) {
                showCreateCustomQuiz = true
            } else {
                showCustomQuizPaywall = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: premiumStore.hasAccess(to: .customQuizzes) ? "plus.circle.fill" : "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(premiumStore.hasAccess(to: .customQuizzes) ? "Create a quiz" : "Create a quiz — Premium")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if !premiumStore.hasAccess(to: .customQuizzes) {
                    Text("PRO")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.25)))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Brand.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Brand.accentStart.opacity(0.30), radius: 10, y: 4)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.97))
    }

    private func customAnswerCard(_ entry: CustomQuizAnswer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.question)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.canEditCustomAnswers {
                    Button {
                        viewModel.removeCustomAnswer(id: entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Brand.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ChipFlow(spacing: 6) {
                ForEach(entry.options, id: \.self) { option in
                    let isPicked = entry.selectedOptions.contains(option)
                    Text(option)
                        .font(.system(size: 12, weight: isPicked ? .semibold : .regular, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                isPicked
                                    ? Color(red: 0.85, green: 0.40, blue: 0.80).opacity(0.18)
                                    : Brand.backgroundTop.opacity(0.6)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isPicked
                                    ? Color(red: 0.85, green: 0.40, blue: 0.80).opacity(0.4)
                                    : Brand.divider,
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(
                            isPicked
                                ? Color(red: 0.75, green: 0.30, blue: 0.70)
                                : Brand.textSecondary
                        )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.backgroundTop.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Brand.divider, lineWidth: 1))
        )
    }

    // MARK: - Attribution

    /// Returns a short attribution label ("by me" / "by He" / "by She") when
    /// the entry was added by somebody other than the profile owner. Owner-
    /// added or legacy entries return nil and render without a tag.
    private func attributionFor(addedBy: String?) -> String? {
        guard let addedBy else { return nil }
        if addedBy == viewModel.targetUserId { return nil }
        if addedBy == viewModel.currentUserId { return "by me" }
        return "by \(partnerPronounLabel)"
    }

    // MARK: - Error Banner

    private func banner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1))
        )
    }
}

// MARK: - Section Card

private struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                .fill(Brand.surfaceLight)
                .overlay(RoundedRectangle(cornerRadius: Brand.cardCornerRadius)
                    .strokeBorder(Brand.divider, lineWidth: 1))
        )
    }
}

// MARK: - Chip Section (likes / dislikes / activities)

private struct ChipSection: View {
    let title: String
    let icon: String
    let tint: Color
    let items: [String]
    let addedBy: [String: String]
    let attributionFor: (String?) -> String?
    let canRemove: (String) -> Bool
    let canAdd: Bool
    @Binding var draft: String
    let placeholder: String
    let emptyMessage: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        SectionCard(title: title, icon: icon, tint: tint) {
            if items.isEmpty && !canAdd {
                Text(emptyMessage)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !items.isEmpty {
                ChipFlow(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        chip(item)
                    }
                }
            }

            if canAdd {
                HStack(spacing: 8) {
                    TextField(placeholder, text: $draft)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .textFieldStyle(.plain)
                        .submitLabel(.done)
                        .onSubmit(commit)

                    Button(action: commit) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(tint.opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.3 : 1))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Brand.backgroundTop.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Brand.divider, lineWidth: 1))
                )
            }
        }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onAdd(value)
        draft = ""
    }

    private func chip(_ item: String) -> some View {
        let attribution = attributionFor(addedBy[item])
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(tint)
                if let attribution {
                    Text(attribution)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(tint.opacity(0.65))
                }
            }

            if canRemove(item) {
                Button {
                    onRemove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Simple flow layout for chips

private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(
            width: maxWidth.isFinite ? maxWidth : x,
            height: y + rowHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
