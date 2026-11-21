//
//  AnchorSetupSheet.swift
//  Coupley
//
//  "When did it begin?": picks the day the couple's story started, which
//  every day count, anniversary and crown on Journey grows from. First run
//  plants the tree; later it edits the start date from the hero's
//  "Since … · Edit" line.
//
//  In the garden (B5.7) the start date belongs to both: the sheet only
//  suggests a day, with an optional note, and it changes when the partner
//  agrees. Without the garden it saves the day at once, as it always has.
//
//  The day is a calendar day, not an instant: the picker starts from the day
//  the stored value names (JourneyCalendarDay.localDay(ofStored:)), and the
//  view model stores what is picked as that day for both partners, wherever
//  each of them is.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Start-date sheet

struct AnchorSetupSheet: View {

    /// How the sheet saves the day.
    enum Mode {
        /// Today's sheet: the picked day is saved at once.
        case directSave
        /// Garden mode (B5.7): the day is suggested to the partner and changes
        /// when they agree. `partnerCanAnswer` is false on a legacy partner
        /// (nil while unknown); `agreedOn` is the day both agreed, if they did.
        /// `onSuggest` sends the day and the note: nil once sent, else the
        /// message that says why not (offline, the partner's suggestion came
        /// first, …), shown in the sheet.
        case suggest(currentStored: Date, partnerCanAnswer: Bool?, agreedOn: Date?,
                     onSuggest: (Date, String?) async -> String?, onTellPartner: () -> Void)
    }

    @ObservedObject var viewModel: TimeTreeViewModel
    /// The current start date, if one is set. Non-nil makes this an edit.
    let existing: RelationshipAnchor?
    /// This user's name, stored with the date so the partner's phone can say
    /// who set it.
    let myName: String?
    let partnerName: String
    let mode: Mode

    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    /// Suggest mode: the note sent with the suggestion.
    @State private var note = ""
    @State private var isSuggesting = false
    /// Suggest mode: why the last suggestion was not sent.
    @State private var suggestFailure: String?

    /// The leaf's well grows with the text.
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 84

    init(viewModel: TimeTreeViewModel,
         existing: RelationshipAnchor?,
         myName: String?,
         partnerName: String,
         mode: Mode = .directSave) {
        self.viewModel = viewModel
        self.existing = existing
        self.myName = myName
        self.partnerName = partnerName
        self.mode = mode

        let calendar = Calendar.current
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let current: Date?
        if case .suggest(let currentStored, _, _, _, _) = mode {
            current = currentStored
        } else {
            current = existing?.startDate
        }
        _startDate = State(initialValue: current.map { JourneyCalendarDay.localDay(ofStored: $0) }
                           ?? calendar.startOfDay(for: threeMonthsAgo))
    }

    private var isEditing: Bool { existing != nil }

    /// Suggest mode's values, unpacked from `Mode.suggest`.
    private struct Suggestion {
        let currentStored: Date
        let partnerCanAnswer: Bool?
        let agreedOn: Date?
        let onSuggest: (Date, String?) async -> String?
        let onTellPartner: () -> Void
    }

    /// nil in direct-save mode.
    private var suggestion: Suggestion? {
        if case .suggest(let currentStored, let partnerCanAnswer, let agreedOn, let onSuggest, let onTellPartner) = mode {
            return Suggestion(currentStored: currentStored, partnerCanAnswer: partnerCanAnswer, agreedOn: agreedOn,
                              onSuggest: onSuggest, onTellPartner: onTellPartner)
        }
        return nil
    }

    /// Suggest mode: the picked day is the start date already.
    private var picksCurrentDay: Bool {
        guard let currentStored = suggestion?.currentStored else { return false }
        return Calendar.current.isDate(JourneyCalendarDay.localDay(ofStored: currentStored), inSameDayAs: startDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    heroBlock

                    dateCard

                    if let suggestion {
                        noteCard
                        suggestFooter(suggestion)
                        if let agreedOn = suggestion.agreedOn {
                            agreedFootnote(agreedOn)
                        } else if let existing {
                            attributionFootnote(existing)
                        }
                    } else if let existing {
                        attributionFootnote(existing)
                    }
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            // The sheet's one filled control, pinned under the content.
            .safeAreaInset(edge: .bottom) {
                Group {
                    if let suggestion {
                        SuggestControls(partnerName: partnerName, failure: suggestFailure,
                                        picksCurrentDay: picksCurrentDay, isSuggesting: isSuggesting) {
                            suggest(suggestion.onSuggest)
                        }
                    } else {
                        BrandCTA(title: isEditing ? "Save start date" : "Plant tree",
                                 tier: .hero,
                                 isBusy: viewModel.isSavingAnchor) {
                            save()
                        }
                    }
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(isEditing || suggestion != nil ? "Start date" : "Plant your tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }

    // MARK: - Hero block

    private var heroBlock: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf.fill")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Brand.accentStart)
                .frame(width: glyphSize, height: glyphSize)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Brand.accentStart.opacity(0.30), Brand.accentEnd.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(isEditing || suggestion != nil ? "When did it begin?" : "Plant your tree")
                    .font(JourneyFont.display)
                    .foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Group {
                    if suggestion != nil {
                        Text("Pick the day your story began. It changes when \(partnerName) agrees too.",
                             comment: "Start date sheet in the garden: the day is suggested to the partner. The placeholder is the partner's name.")
                    } else {
                        Text("Pick the day your story began. Your tree grows from it, and \(partnerName) sees it too.")
                    }
                }
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Date card

    private var dateCard: some View {
        BrandCard(tier: .card) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Start date", systemImage: "calendar")
                    .font(JourneyFont.label)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityHidden(true)

                DatePicker(
                    "Start date",
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(Brand.accentStart)
                .labelsHidden()
            }
        }
    }

    // MARK: - Suggest mode

    private var noteCard: some View {
        BrandCard(tier: .card) {
            TextField(text: Binding(get: { note }, set: { note = GardenLimits.seedNote.truncate($0) }),
                      axis: .vertical) {
                Text("A note for \(partnerName) (optional)",
                     comment: "Start date sheet: placeholder of the note sent with a suggested start date. The placeholder is the partner's name.")
            }
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textPrimary)
            .lineLimit(2...5)
        }
    }

    /// "Your tree keeps growing from 26 Jan 2026 until Sam says yes.", and
    /// on a legacy partner the Tell Sam line (the button stays enabled: the
    /// suggestion waits until Sam updates).
    private func suggestFooter(_ suggestion: Suggestion) -> some View {
        let current = JourneyCalendarDay.localDay(ofStored: suggestion.currentStored)
            .formatted(date: .abbreviated, time: .omitted)
        return VStack(spacing: 8) {
            Text("Your tree keeps growing from \(current) until \(partnerName) says yes.",
                 comment: "Start date sheet in the garden. First placeholder: the current start date such as 'Jan 26, 2026'; second: the partner's name.")
            if suggestion.partnerCanAnswer == false {
                Text("\(partnerName)'s Coupley is out of date, so \(partnerName) can't agree yet.",
                     comment: "Start date sheet: the partner's app is too old to answer. The placeholders are the partner's name.")
                Button {
                    suggestion.onTellPartner()
                } label: {
                    Text("Tell \(partnerName)", comment: "Garden: offer to send the partner a Chat message about updating. The placeholder is the partner's name.")
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.accentStart)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .font(JourneyFont.meta)
        .foregroundStyle(Brand.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func agreedFootnote(_ day: Date) -> some View {
        let text = day.formatted(date: .abbreviated, time: .omitted)
        return HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text("Agreed together on \(text)",
                 comment: "Start date sheet footnote: both partners agreed on the start date. The placeholder is a date such as 'Nov 14, 2026'.")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Attribution footnote

    private func attributionFootnote(_ anchor: RelationshipAnchor) -> some View {
        let day = anchor.setAt.formatted(date: .abbreviated, time: .omitted)
        // Two whole sentences: "you" is never spliced into the partner's.
        let line = anchor.setBy == viewModel.currentUserId
            ? String(localized: "Set by you on \(day)",
                     comment: "Start date sheet footnote: the user set the start date. %@ is a date such as 'Jan 26, 2026'.")
            : String(localized: "Set by \(partnerName) on \(day)",
                     comment: "Start date sheet footnote. First %@ is the partner's name, second a date such as 'Jan 26, 2026'.")
        return HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textTertiary)
                .accessibilityHidden(true)
            Text(line)
                .font(JourneyFont.meta)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Save

    private func save() {
        Task {
            await viewModel.setAnchor(startDay: startDate, myName: myName)
            dismiss()
        }
    }

    /// Suggest mode: sends the day and the note; stays open with the reason
    /// on failure.
    private func suggest(_ onSuggest: @escaping (Date, String?) async -> String?) {
        isSuggesting = true
        suggestFailure = nil
        Task {
            let failure = await onSuggest(startDate, GardenLimits.seedNote.clean(note))
            isSuggesting = false
            if let failure {
                suggestFailure = failure
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Suggest mode's controls

/// "Suggest this date", the reason the last suggestion was not sent above
/// it, and the offline line under it: a suggestion is a transaction, so it
/// needs a connection (as the plant and seed sheets). Its own view, so only
/// suggest mode (the garden) watches connectivity: the direct-save sheet
/// starts no garden monitor.
private struct SuggestControls: View {

    let partnerName: String
    let failure: String?
    let picksCurrentDay: Bool
    let isSuggesting: Bool
    let onSuggest: () -> Void

    @ObservedObject private var reachability = GardenReachability.shared

    var body: some View {
        VStack(spacing: 8) {
            if let failure {
                line(failure)
            }
            BrandCTA(title: LocalizedStringResource("Suggest this date",
                                                    comment: "Start date sheet in the garden: the filled button that suggests the day to the partner"),
                     tier: .hero,
                     isEnabled: reachability.isOnline && !picksCurrentDay,
                     isBusy: isSuggesting,
                     action: onSuggest)
            if !reachability.isOnline {
                line(GardenError.offline.message(partnerName: partnerName, now: Date()))
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(JourneyFont.meta)
            .foregroundStyle(Brand.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
