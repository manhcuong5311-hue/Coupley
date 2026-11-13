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
    @State private var pendingPhotoQueue: [ChatMessage] = []
    @State private var seenPhotoMessageIds: Set<String> = []
    @FocusState private var isComposerFocused: Bool
    /// Opens a future letter seeded with the given words. Returns false when
    /// it could not (no partner yet), so the typed message is kept.
    private let onWriteLetter: ((String) -> Bool)?

    init(session: UserSession,
         profileViewModel: CouplePersonProfileViewModel,
         onWriteLetter: ((String) -> Bool)? = nil) {
        self.session = session
        self.profileViewModel = profileViewModel
        self.onWriteLetter = onWriteLetter
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
            .navigationTitle(Text("Chat", comment: "Title of the Chat tab (noun)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.backgroundTop.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if session.isPaired {
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
                                    Text("Quiz", comment: "Chat toolbar button that opens the Quiz Hub (noun)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .foregroundStyle(Brand.accentStart)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Brand.surfaceLight)
                                        .overlay(Capsule().strokeBorder(
                                            Brand.accentStart.opacity(0.45), lineWidth: 1))
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
                            .accessibilityLabel("Couple Profile")
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                    partnerName: profileViewModel.partnerProfile.displayName,
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
            .onChange(of: viewModel.draftText) { _, text in
                // Clearing the field (send, or manual delete) should stop the
                // dots immediately rather than waiting out the window.
                if text.isEmpty { viewModel.stopTyping() } else { viewModel.noteTyping() }
            }
            .onChange(of: isComposerFocused) { _, focused in
                if !focused { viewModel.stopTyping() }
            }
            .onChange(of: photosPickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        await MainActor.run { photosPickerItem = nil }
                        return
                    }
                    // `sendPhoto` returns false if another upload is already in flight.
                    _ = viewModel.sendPhoto(image)
                    await MainActor.run { photosPickerItem = nil }
                }
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
        // Queue every unseen partner photo (oldest first) so a burst of
        // photos doesn't silently drop all but the most recent one.
        let partnerPhotos = messages.filter {
            $0.kind == .photo &&
            $0.senderId == session.partnerId &&
            !seenPhotoMessageIds.contains($0.id) &&
            !$0.readBy.contains(session.userId)
        }
        guard !partnerPhotos.isEmpty else { return }
        for photo in partnerPhotos {
            seenPhotoMessageIds.insert(photo.id)
            pendingPhotoQueue.append(photo)
        }
        if pendingPhotoPopup == nil {
            pendingPhotoPopup = pendingPhotoQueue.first
            if !pendingPhotoQueue.isEmpty { pendingPhotoQueue.removeFirst() }
        }
    }

    private func markPhotoSeen(_ message: ChatMessage) {
        // Mark read in Firestore so popup won't show again after relaunch
        Task {
            try? await ChatViewModel.markMessageRead(
                messageId: message.id,
                coupleId: session.coupleId,
                userId: session.userId
            )
        }
        // Advance to the next queued photo (if any) so the user sees them all.
        if let next = pendingPhotoQueue.first {
            pendingPhotoQueue.removeFirst()
            pendingPhotoPopup = next
        } else {
            pendingPhotoPopup = nil
        }
    }

    // MARK: - Chat body

    private var chatBody: some View {
        VStack(spacing: 0) {
            messagesScroll

            if viewModel.partnerIsTyping {
                PartnerTypingRow()
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            composerBar
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85),
                   value: viewModel.partnerIsTyping)
        .alert("Message not sent", isPresented: Binding(
            get: { viewModel.sendFailure != nil },
            set: { if !$0 { viewModel.sendFailure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.sendFailure ?? "")
        }
        // No banner on this screen, as in 1.1. Under the composer it sat 10pt
        // from Send, photo and quiz, and it loaded a moment after the keyboard
        // closed — taking the spot the composer had just dropped into, so a
        // tap aimed at Send landed on the ad. That is the accidental-click
        // pattern AdMob limits small accounts for.
    }

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    loadOlderIndicator
                        .id("__loadOlder")

                    // A freshly paired couple used to see nothing here but the
                    // "Pull up to see older messages" sentinel, on a thread
                    // that has never held a message.
                    if viewModel.messages.isEmpty && !viewModel.isLoadingOlder {
                        emptyThreadNote
                    }

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
                            },
                            onReact: { quiz, kind in
                                viewModel.react(to: quiz, kind: kind)
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

    private var emptyThreadNote: some View {
        VStack(spacing: 8) {
            Text("Say the first thing")
                .font(BrandType.title)
                .foregroundStyle(Brand.textPrimary)
            Text("Everything you send each other lives here.")
                .font(BrandType.body)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var loadOlderIndicator: some View {
        if viewModel.hasMoreOlder && !viewModel.messages.isEmpty {
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
            // "+": a future letter or a quiz. A typed message can be turned
            // into a letter instead of being sent: the words move into the
            // letter draft and leave the field, so the surprise can't go out
            // by accident.
            Menu {
                if let onWriteLetter {
                    Button {
                        if onWriteLetter(viewModel.draftText) {
                            viewModel.draftText = ""
                            isComposerFocused = false
                        }
                    } label: {
                        Label(hasDraft ? "Turn into a future letter" : "Write a future letter",
                              systemImage: "envelope")
                    }
                }
                Button {
                    showQuizHub = true
                } label: {
                    Label("Quiz", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Brand.surfaceLight)
                            .overlay(Circle().strokeBorder(Brand.divider, lineWidth: 1))
                    )
            }
            .accessibilityLabel("Future letter or quiz")

            photoButton
                .accessibilityLabel("Send a photo")

            TextField(String(localized: "Message", comment: "Placeholder in the chat composer (noun)"),
                      text: $viewModel.draftText, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .focused($isComposerFocused)
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
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            isComposerFocused = false
                        } label: {
                            Text("Done", comment: "Keyboard toolbar button: hide the keyboard")
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.accentStart)
                    }
                }

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
            .accessibilityLabel(Text("Send", comment: "Button that sends the typed chat message (verb)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Brand.backgroundTop.opacity(0.95)
                .overlay(Rectangle().fill(Brand.divider).frame(height: 0.5), alignment: .top)
        )
    }

    /// Words in the message field, which the + menu can turn into a letter.
    private var hasDraft: Bool {
        !viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        !viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !viewModel.isSending
    }

    // MARK: - Photo button

    private var photoButton: some View {
        PhotosPicker(selection: $photosPickerItem, matching: .images) {
            photoButtonLabel
        }
        .disabled(viewModel.isUploadingPhoto)
    }

    private var photoButtonLabel: some View {
        ZStack {
            if viewModel.isUploadingPhoto {
                ProgressView()
                    .tint(Brand.accentStart)
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accentStart)
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
