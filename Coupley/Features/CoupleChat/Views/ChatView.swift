//
//  ChatView.swift
//  Coupley
//
//  Tab 4 — Couple Quiz Chat. iMessage-inspired, calm and minimal, uses the
//  Brand theme tokens so it inherits CoupleSync / Classic.
//

import SwiftUI
import PhotosUI

struct ChatView: View {

    @StateObject private var viewModel: ChatViewModel
    @ObservedObject var profileViewModel: CouplePersonProfileViewModel
    @EnvironmentObject private var premiumStore: PremiumStore
    let session: UserSession
    @State private var showProfile = false
    @State private var showPartnerAndMe = false
    @State private var showQuizHub = false
    @State private var photosPickerItem: PhotosPickerItem? = nil
    @State private var pendingPhotoPopup: ChatMessage? = nil
    @State private var seenPhotoMessageIds: Set<String> = []
    @State private var showPhotoPaywall = false

    init(session: UserSession, profileViewModel: CouplePersonProfileViewModel) {
        self.session = session
        self.profileViewModel = profileViewModel
        _viewModel = StateObject(wrappedValue: ChatViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                if session.isPaired {
                    chatBody
                } else {
                    NotPairedView()
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Quiz Hub — primary entry point for the Daily / AI /
                        // Custom / History flows. Replaces the previous
                        // single-picker shortcut.
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showQuizHub = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Quiz")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Brand.accentGradient)
                                    .shadow(color: Brand.accentStart.opacity(0.30), radius: 6, y: 2)
                            )
                        }
                        .accessibilityLabel("Open Quiz Hub")

                        Button { showPartnerAndMe = true } label: {
                            Image(systemName: "heart.text.square")
                                .foregroundStyle(Brand.accentStart)
                        }
                        .accessibilityLabel("Partner & Me Profile")

                        Button { showProfile = true } label: {
                            Image(systemName: "sparkles.rectangle.stack")
                                .foregroundStyle(Brand.accentStart)
                        }
                    }
                }
            }
            .sheet(isPresented: $showProfile) {
                NavigationStack {
                    CoupleProfileView(coupleId: session.coupleId,
                                      userAId: session.userId,
                                      userBId: session.partnerId)
                }
                .presentationBackground(Brand.backgroundTop)
            }
            .sheet(isPresented: $showPartnerAndMe) {
                PartnerAndMeProfileView(
                    profileViewModel: profileViewModel,
                    session: session
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Brand.backgroundTop)
            }
            .sheet(item: $viewModel.activeQuizForAnswering) { quiz in
                QuizAnswerSheet(
                    quiz: quiz,
                    onSubmit: { answer in viewModel.submit(answer: answer, for: quiz) },
                    onCancel: { viewModel.activeQuizForAnswering = nil }
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(Brand.backgroundTop)
            }
            .sheet(isPresented: $showQuizHub) {
                QuizHubView(viewModel: viewModel)
                    .environmentObject(premiumStore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Brand.backgroundTop)
            }
            .onAppear   { viewModel.start() }
            .onDisappear { viewModel.stop() }
            .onChange(of: photosPickerItem) { _, item in
                guard let item else { return }
                // Re-check access at load time in case the user already sent
                // their one free photo earlier in the same day.
                guard premiumStore.hasAccess(to: .chatPhotos) else {
                    photosPickerItem = nil
                    showPhotoPaywall = true
                    return
                }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    viewModel.sendPhoto(image)
                    // Only count against the free daily quota — unlimited
                    // sends for premium shouldn't consume the counter.
                    if !premiumStore.isActive {
                        premiumStore.recordUsage(for: .chatPhotos)
                    }
                    await MainActor.run { photosPickerItem = nil }
                }
            }
            .sheet(isPresented: $showPhotoPaywall) {
                NavigationStack { PremiumPaywallView() }
                    .environmentObject(premiumStore)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: viewModel.messages) { _, messages in
                checkForIncomingPhoto(in: messages)
            }
            .overlay {
                if let photo = pendingPhotoPopup, let url = photo.imageURL {
                    PartnerPhotoPopupView(imageURL: url) {
                        markPhotoSeen(photo)
                    }
                    .transition(.opacity)
                    .zIndex(200)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: pendingPhotoPopup?.id)
        }
    }

    private func checkForIncomingPhoto(in messages: [ChatMessage]) {
        // Find the newest photo message from the partner not yet shown
        let partnerPhotos = messages.filter {
            $0.kind == .photo &&
            $0.senderId == session.partnerId &&
            !seenPhotoMessageIds.contains($0.id) &&
            !$0.readBy.contains(session.userId)
        }
        guard let newest = partnerPhotos.last else { return }
        seenPhotoMessageIds.insert(newest.id)
        pendingPhotoPopup = newest
    }

    private func markPhotoSeen(_ message: ChatMessage) {
        pendingPhotoPopup = nil
        // Mark read in Firestore so popup won't show again after relaunch
        Task {
            try? await ChatViewModel.markMessageRead(
                messageId: message.id,
                coupleId: session.coupleId,
                userId: session.userId
            )
        }
    }

    // MARK: - Chat body

    private var chatBody: some View {
        VStack(spacing: 0) {
            messagesScroll
            composerBar
        }
    }

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    loadOlderIndicator
                        .id("__loadOlder")

                    ForEach(viewModel.messages) { msg in
                        MessageRow(
                            message: msg,
                            isMine: msg.senderId == viewModel.myUserId,
                            quiz: viewModel.quiz(for: msg),
                            viewerId: viewModel.myUserId,
                            partnerId: viewModel.partnerUserId,
                            outgoingStatus: viewModel.outgoingStatus(for: msg),
                            onAnswerTapped: { quizId in
                                viewModel.presentQuizForAnswering(quizId: quizId)
                            }
                        )
                        .id(msg.id)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .onChange(of: viewModel.messages.last?.id) { _, newLast in
                guard let newLast else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newLast, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var loadOlderIndicator: some View {
        if viewModel.hasMoreOlder {
            HStack {
                Spacer()
                if viewModel.isLoadingOlder {
                    ProgressView()
                        .tint(Brand.accentStart)
                        .controlSize(.small)
                } else {
                    Text("Pull up to see older messages")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Brand.textTertiary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .onAppear {
                // Fires when the top sentinel scrolls into view — LazyVStack
                // only instantiates it near the top of the scroll range.
                viewModel.loadOlder()
            }
        }
    }

    // MARK: - Composer

    private var composerBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showQuizHub = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Brand.surfaceLight)
                            .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    )
            }
            .buttonStyle(BouncyButtonStyle())
            .accessibilityLabel("Open Quiz Hub")

            photoButton
                .accessibilityLabel("Send a photo")

            TextField("Message", text: $viewModel.draftText, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(Brand.divider, lineWidth: 1)
                        )
                )

            Button {
                viewModel.sendDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(Brand.accentGradient)
                    )
                    .opacity(canSend ? 1 : 0.4)
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Brand.backgroundTop.opacity(0.95)
                .overlay(Rectangle().fill(Brand.divider).frame(height: 0.5), alignment: .top)
        )
    }

    private var canSend: Bool {
        !viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !viewModel.isSending
    }

    // MARK: - Photo button (gated by `chatPhotos` premium)

    /// Free users can send 1 photo per day. When their quota is spent we
    /// swap the `PhotosPicker` for a plain `Button` that surfaces the paywall
    /// — mirrors the `AvatarPickerSheet` pattern so gating feels consistent.
    @ViewBuilder
    private var photoButton: some View {
        if premiumStore.hasAccess(to: .chatPhotos) {
            PhotosPicker(selection: $photosPickerItem, matching: .images) {
                photoButtonLabel(locked: false)
            }
            .disabled(viewModel.isUploadingPhoto)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showPhotoPaywall = true
            } label: {
                photoButtonLabel(locked: true)
            }
        }
    }

    private func photoButtonLabel(locked: Bool) -> some View {
        ZStack {
            if viewModel.isUploadingPhoto {
                ProgressView()
                    .tint(Brand.accentStart)
                    .controlSize(.small)
            } else {
                Image(systemName: locked ? "lock.fill" : "photo")
                    .font(.system(size: locked ? 13 : 16, weight: .semibold))
                    .foregroundStyle(locked ? Brand.textTertiary : Brand.accentStart)
            }
        }
        .frame(width: 38, height: 38)
        .background(
            Circle()
                .fill(Brand.surfaceLight)
                .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
        )
    }
}

// MARK: - Not Paired fallback

private struct NotPairedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle")
                .font(.system(size: 56))
                .foregroundStyle(Brand.accentStart)
            Text("Connect your partner to start chatting")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.center)
            Text("Share an invite code from the Home tab, then come back here.")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}
