//
//  OnboardingInputSteps.swift
//  Coupley
//
//  The "tell us about you two" half of onboarding. Each screen here collects
//  one or two pieces of profile data; the layout pattern is consistent so
//  the user feels they're moving through one continuous form rather than
//  N disconnected screens.
//
//  Notes:
//    • All inputs except first name are optional. Skip is hot.
//    • Per-step `canAdvance` flows from `viewModel.canAdvance()` so the
//      Continue button correctly disables when required state isn't met.
//    • Haptics live in the ViewModel selection methods, not in the views.
//

import SwiftUI
import UserNotifications

// MARK: - Name

struct NameInputStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingStepScaffold(
            viewModel: viewModel,
            canAdvance: viewModel.canAdvance(),
            primaryAction: {
                Task {
                    await viewModel.saveName()
                    viewModel.advance()
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(
                    eyebrow: "About you",
                    title: "What should\nwe call you?",
                    subtitle: "Just your first name — your partner will see it when you connect."
                )
                .padding(.top, 8)

                BrandField(icon: "person",
                           placeholder: "First name",
                           text: $viewModel.profile.firstName,
                           textContentType: .givenName)
                    .focused($focused)
                    .submitLabel(.next)
                    .onSubmit {
                        if viewModel.canAdvance() {
                            Task {
                                await viewModel.saveName()
                                viewModel.advance()
                            }
                        }
                    }

                Spacer(minLength: 0)
            }
            .onAppear {
                // Tiny delay so the keyboard plays nicely with the step
                // transition animation.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    focused = true
                }
            }
        }
    }
}

// MARK: - Partner

struct PartnerInputStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var partnerFocused: Bool
    @State private var includeAnniversary: Bool

    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
        _includeAnniversary = State(initialValue: viewModel.profile.anniversary != nil)
    }

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeader(
                    eyebrow: "About your partner",
                    title: "Tell us a little\nabout the two of you.",
                    subtitle: "Both fields are optional. You can fill them in later from Settings."
                )
                .padding(.top, 8)

                BrandField(icon: "heart",
                           placeholder: "Partner's first name",
                           text: $viewModel.profile.partnerName,
                           textContentType: .givenName)
                    .focused($partnerFocused)

                anniversaryCard
            }
        }
    }

    private var anniversaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Brand.accentStart.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.accentStart)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your anniversary")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text(includeAnniversary
                         ? "We'll remind you ahead of time."
                         : "Add a date and we'll remember it for you.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { includeAnniversary },
                    set: { newValue in
                        includeAnniversary = newValue
                        if newValue {
                            // Default to today if the user just enabled the field.
                            if viewModel.profile.anniversary == nil {
                                viewModel.profile.anniversary = Date()
                            }
                        } else {
                            viewModel.profile.anniversary = nil
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                ))
                .labelsHidden()
                .tint(Brand.accentStart)
            }

            if includeAnniversary {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { viewModel.profile.anniversary ?? Date() },
                        set: { viewModel.profile.anniversary = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(Brand.accentStart)
                .padding(.horizontal, -4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Brand.surfaceLight)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Brand.divider, lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: includeAnniversary)
    }
}

// MARK: - Goals

struct GoalsStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeader(
                    eyebrow: "What matters to you",
                    title: "What do you want\nout of Coupley?",
                    subtitle: "Pick a few — we'll lean into them as we get to know you both."
                )
                .padding(.top, 8)

                VStack(spacing: 10) {
                    ForEach(RelationshipGoal.allCases) { goal in
                        SelectableCard(
                            icon: goal.icon,
                            title: goal.label,
                            isSelected: viewModel.profile.goals.contains(goal),
                            action: { viewModel.toggle(goal: goal) }
                        ) {
                            checkbox(isOn: viewModel.profile.goals.contains(goal))
                        }
                    }
                }
            }
        }
    }

    private func checkbox(isOn: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(isOn ? Brand.accentStart : Color.clear)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isOn ? Brand.accentStart : Brand.divider, lineWidth: 1.5)
                )
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Communication Style

struct CommunicationStyleStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeader(
                    eyebrow: "How you love",
                    title: "How would you\ndescribe your love?",
                    subtitle: "There's no wrong answer — this just helps us match the tone of nudges and prompts."
                )
                .padding(.top, 8)

                VStack(spacing: 10) {
                    ForEach(OnboardingCommunicationStyle.allCases) { style in
                        SelectableCard(
                            icon: style.icon,
                            title: style.label,
                            subtitle: style.blurb,
                            isSelected: viewModel.profile.communicationStyle == style,
                            action: { viewModel.setStyle(style) }
                        ) {
                            radio(isOn: viewModel.profile.communicationStyle == style)
                        }
                    }
                }
            }
        }
    }

    private func radio(isOn: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? Brand.accentStart : Brand.divider, lineWidth: 2)
                .frame(width: 22, height: 22)
            if isOn {
                Circle()
                    .fill(Brand.accentStart)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Daily Habit (reminder + mood check)

struct DailyHabitStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(viewModel: viewModel) {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(
                    eyebrow: "Daily rhythm",
                    title: "When should we\nnudge you?",
                    subtitle: "Set the cadence and time that fits your day. You can always change it later."
                )
                .padding(.top, 8)

                cadenceCard
                timeCard
                moodCheckCard
            }
        }
    }

    // MARK: Cadence

    private var cadenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Reminder cadence")
            VStack(spacing: 8) {
                ForEach(ReminderCadence.allCases) { cadence in
                    Button {
                        viewModel.profile.reminderCadence = cadence
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(cadence.label)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                            Spacer()
                            if viewModel.profile.reminderCadence == cadence {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Brand.accentStart)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.profile.reminderCadence == cadence
                                      ? Brand.accentStart.opacity(0.10)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.99))
                }
            }
        }
        .padding(14)
        .background(stackBackground)
    }

    // MARK: Time

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Best time of day")

            DatePicker(
                "",
                selection: Binding(
                    get: { hourBinding },
                    set: { date in
                        let hour = Calendar.current.component(.hour, from: date)
                        viewModel.profile.reminderHour = hour
                    }
                ),
                displayedComponents: [.hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .clipped()
            .opacity(viewModel.profile.reminderCadence == .off ? 0.4 : 1.0)
            .disabled(viewModel.profile.reminderCadence == .off)
        }
        .padding(14)
        .background(stackBackground)
    }

    private var hourBinding: Date {
        let comps = DateComponents(hour: viewModel.profile.reminderHour, minute: 0)
        return Calendar.current.date(from: comps) ?? Date()
    }

    // MARK: Mood

    private var moodCheckCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Mood check-ins")

            VStack(spacing: 8) {
                ForEach(MoodCheckCadence.allCases) { cadence in
                    Button {
                        viewModel.profile.moodCheckCadence = cadence
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cadence.label)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Brand.textPrimary)
                                Text(cadence.blurb)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(Brand.textSecondary)
                            }
                            Spacer()
                            if viewModel.profile.moodCheckCadence == cadence {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Brand.accentStart)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.profile.moodCheckCadence == cadence
                                      ? Brand.accentStart.opacity(0.10)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.99))
                }
            }
        }
        .padding(14)
        .background(stackBackground)
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(Brand.textSecondary)
    }

    private var stackBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Brand.surfaceLight)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Brand.divider, lineWidth: 1)
            )
    }
}

// MARK: - Notifications

struct NotificationsStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel
    @State private var isRequesting = false
    @State private var didRespond = false

    var body: some View {
        OnboardingStepScaffold(
            viewModel: viewModel,
            primaryTitle: didRespond ? "Continue" : "Allow notifications",
            secondaryTitle: didRespond ? nil : "Maybe later",
            canAdvance: !isRequesting,
            primaryAction: {
                if didRespond {
                    viewModel.advance()
                } else {
                    requestPermission()
                }
            },
            secondaryAction: didRespond ? nil : {
                viewModel.profile.notificationsEnabled = false
                viewModel.advance()
            }
        ) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    OnboardingHeroIcon(
                        icon: "bell.badge.fill",
                        tint: Color(red: 1.0, green: 0.55, blue: 0.30),
                        size: 96
                    )
                    Spacer()
                }
                .padding(.top, 12)

                StepHeader(
                    eyebrow: "Stay in the loop",
                    title: "Want a tap on the\nshoulder when it counts?",
                    subtitle: "We'll only nudge you for the things you actually care about — moods, anniversaries, sweet messages from your partner."
                )

                VStack(alignment: .leading, spacing: 10) {
                    notifRow(icon: "heart.fill", text: "When your partner shares a mood")
                    notifRow(icon: "calendar.badge.clock", text: "On dates that matter to you both")
                    notifRow(icon: "bubble.left.fill", text: "When they send you something sweet")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Brand.surfaceLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Brand.divider, lineWidth: 1)
                        )
                )

                if didRespond {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.profile.notificationsEnabled
                              ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(viewModel.profile.notificationsEnabled
                                             ? Color(red: 0.30, green: 0.75, blue: 0.55)
                                             : Brand.textSecondary)
                        Text(viewModel.profile.notificationsEnabled
                             ? "Great — you're all set."
                             : "No problem. You can turn these on later in Settings.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: didRespond)
        }
    }

    private func notifRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.accentStart)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
        }
    }

    private func requestPermission() {
        isRequesting = true
        Task {
            let granted = await requestSystemAuthorization()
            await MainActor.run {
                viewModel.profile.notificationsEnabled = granted
                didRespond = true
                isRequesting = false
                if granted {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
    }

    private func requestSystemAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            ) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - Widget

struct WidgetStepView: View {

    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
            viewModel: viewModel,
            primaryTitle: viewModel.profile.widgetSuggestionAcknowledged
                ? "Continue"
                : "Got it, show me how",
            secondaryTitle: viewModel.profile.widgetSuggestionAcknowledged ? nil : "Skip for now",
            primaryAction: {
                if viewModel.profile.widgetSuggestionAcknowledged {
                    viewModel.advance()
                } else {
                    viewModel.profile.widgetSuggestionAcknowledged = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            },
            secondaryAction: viewModel.profile.widgetSuggestionAcknowledged ? nil : {
                viewModel.advance()
            }
        ) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    OnboardingHeroIcon(
                        icon: "rectangle.3.group.fill",
                        tint: Color(red: 0.55, green: 0.45, blue: 1.0),
                        size: 96
                    )
                    Spacer()
                }
                .padding(.top, 12)

                StepHeader(
                    eyebrow: "Widgets",
                    title: "Carry their mood\non your home screen.",
                    subtitle: "Add the Coupley widget so you can see their day at a glance — without ever opening the app."
                )

                widgetMockup

                if viewModel.profile.widgetSuggestionAcknowledged {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.30, green: 0.75, blue: 0.55))
                        Text("Long-press your home screen → tap +, then search Coupley.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.profile.widgetSuggestionAcknowledged)
        }
    }

    /// A faux iOS-widget mockup. Pure SwiftUI, no assets — gives the user a
    /// concrete preview of what they'll see.
    private var widgetMockup: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(red: 1.0, green: 0.42, blue: 0.55),
                                     Color(red: 1.0, green: 0.62, blue: 0.42)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("M")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Maya")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Text("just now")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                    }
                    Spacer()
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("🥰")
                        .font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feeling loved")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                        Text("Thinking about you")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                    Spacer()
                }
            }
            .padding(14)
            .frame(width: 170, height: 170)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(.white.opacity(0.30), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
