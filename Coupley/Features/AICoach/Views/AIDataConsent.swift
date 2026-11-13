//
//  AIDataConsent.swift
//  Coupley
//
//  One explicit, one-time agreement before anything is sent to the AI
//  provider.
//
//  Until 1.2 the coach and the mood suggestions were canned, on-device
//  content, and the coach screen said so: "private and saved only on this
//  device". 1.2 switches both to a real model, which means what the user types
//  — together with names, profile answers and recent moods — leaves the device
//  for our Cloud Function and then OpenAI. The old sentence became false the
//  moment that shipped, and App Store guideline 5.1.2 requires saying who
//  personal data is shared with, third-party AI included, and getting
//  permission first.
//
//  The gate is an opaque overlay rather than an alert: it is drawn by the
//  screen itself, so it cannot lose a race with the sheet that presents the
//  screen, and nothing behind it is reachable until the user answers.
//

import SwiftUI

enum AIDataConsent {
    /// Versioned so the question can be asked again if what is sent changes.
    static let storageKey = "aiDataConsentGranted.v1"

    static var isGranted: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}

extension View {
    /// Blocks the screen until the user has agreed to AI data sharing.
    ///
    /// - Parameters:
    ///   - onDecline: leave the screen; nothing has been sent.
    ///   - onGranted: runs on every appearance once consent exists, and once
    ///     at the moment it is given. Put the screen's first network call
    ///     here instead of in `onAppear`.
    func aiDataConsentGate(onDecline: @escaping () -> Void,
                           onGranted: @escaping () -> Void) -> some View {
        modifier(AIDataConsentGate(onDecline: onDecline, onGranted: onGranted))
    }
}

private struct AIDataConsentGate: ViewModifier {
    @AppStorage(AIDataConsent.storageKey) private var granted = false
    let onDecline: () -> Void
    let onGranted: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { if granted { onGranted() } }
            .overlay {
                if !granted {
                    AIDataConsentCard(
                        onAgree: {
                            granted = true
                            onGranted()
                        },
                        onDecline: onDecline
                    )
                }
            }
    }
}

private struct AIDataConsentCard: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Brand.bgGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)

                    Text("Before you use AI features")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Coupley's AI coach and mood suggestions are written by OpenAI. To get a reply, this is sent to OpenAI through our servers:")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        row("What you type to the coach, and that conversation")
                        row("Both of your names and profile answers, such as love language, attachment and communication style, personality, likes, dislikes and goals")
                        row("Recent moods for both of you, your partner's latest mood note, how long you've been together, and your first anniversary")
                    }

                    Text("It is used only to write the reply. OpenAI states that data sent this way is not used to train its models. Your coach history is stored on this device only.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text("Agree and continue")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Capsule().fill(Brand.accentStart))
                        }

                        Button(action: onDecline) {
                            Text("Not now")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.right.circle.fill")
                .flipsForRightToLeftLayoutDirection(true)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
