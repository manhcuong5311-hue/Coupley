//
//  ChatView.swift
//  Coupley
//
//  Tab 4 — Couple Quiz Chat. iMessage-inspired, calm and minimal, uses the
//  Brand theme tokens so it inherits CoupleSync / Classic.
//

import SwiftUI

struct ChatView: View {

    @StateObject private var viewModel: ChatViewModel
    @ObservedObject var profileViewModel: CouplePersonProfileViewModel
    let session: UserSession
    @State private var showProfile = false
    @State private var showPartnerAndMe = false

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
                    HStack(spacing: 14) {
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
            .onAppear   { viewModel.start() }
            .onDisappear { viewModel.stop() }
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
                    ForEach(viewModel.messages) { msg in
                        MessageRow(
                            message: msg,
                            isMine: msg.senderId == viewModel.myUserId,
                            quiz: viewModel.quiz(for: msg),
                            viewerId: viewModel.myUserId,
                            partnerId: viewModel.partnerUserId,
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

    // MARK: - Composer

    private var composerBar: some View {
        HStack(spacing: 10) {
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
