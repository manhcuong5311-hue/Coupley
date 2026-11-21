//
//  WaterNoteSheet.swift
//  Coupley
//
//  "Water with a note" (spec B5.6): chips, the note field with its counter,
//  the filled "Water with this note". The sheet closes first; Journey starts
//  the watering and its effect in onDismiss.
//
//  The note is plain text, at most 100 graphemes and 400 UTF-8 bytes
//  (GardenLimits.wateringNote); whitespace alone is no note. The draft
//  lives with Journey: swiping the sheet away keeps it (a dot on the hero's
//  ✎), Cancel clears it.
//

import Foundation
import Observation
import SwiftUI

// MARK: - The draft

/// The watering note being written. Journey keeps it while the water-note
/// sheet is closed. Observable, so typing re-renders only the sheet that
/// reads `text`: Journey and the hero read `isDrafted`, which changes only
/// when the draft starts or stops holding a note (the dot on the ✎).
@Observable
final class GardenNoteDraft {

    /// Whether the draft holds a note (not empty, not whitespace alone).
    private(set) var isDrafted = false
    private var storage = ""

    /// The note as typed.
    var text: String {
        get { storage }
        set {
            storage = newValue
            let drafted = GardenLimits.wateringNote.clean(newValue) != nil
            if drafted != isDrafted { isDrafted = drafted }
        }
    }
}

// MARK: - Sheet

struct WaterNoteSheet: View {

    @ObservedObject var garden: GardenViewModel
    /// The note being written; Journey keeps it while the sheet is closed.
    @Bindable var draft: GardenNoteDraft
    /// The note the user chose to water with. Called before the sheet
    /// dismisses itself; Journey waters in the sheet's onDismiss.
    let onWater: (String) -> Void

    init(garden: GardenViewModel, draft: GardenNoteDraft, onWater: @escaping (String) -> Void) {
        self.garden = garden
        _draft = Bindable(draft)
        self.onWater = onWater
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    private var limit: GardenTextLimit { GardenLimits.wateringNote }

    /// Watering is possible right now (not in my 12-hour rest, garden ready).
    /// The hero's own action, read without building the whole hero (this
    /// body runs on every keystroke).
    private var canWater: Bool {
        switch garden.waterAction {
        case .locked, .none: return false
        default:             return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    chips
                    field
                    Text(footnote)
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Brand.bgGradient.ignoresSafeArea())
            .navigationTitle(Text("Water with a note", comment: "Garden: title of the sheet for a note that goes with the watering"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        draft.text = ""
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Button: close the water-note sheet and discard the note")
                    }
                    .foregroundStyle(Brand.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                BrandCTA(title: String(localized: "Water with this note",
                                       comment: "Garden: waters the garden with the note just written"),
                         icon: "drop.fill", tier: .hero, isEnabled: canWater) {
                    let note = limit.clean(draft.text) ?? ""
                    onWater(note)
                    dismiss()
                }
                .padding(.horizontal, Brand.Space.gutter)
                .padding(.vertical, 10)
                .background(Brand.backgroundTop.opacity(0.96))
            }
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: Chips

    /// "Thinking of you", "Miss you", "Proud of us", and one for the time of
    /// day (A7).
    private var suggestions: [String] {
        var chips = [
            String(localized: "Thinking of you", comment: "Garden: a suggested watering note"),
            String(localized: "Miss you", comment: "Garden: a suggested watering note"),
            String(localized: "Proud of us", comment: "Garden: a suggested watering note")
        ]
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            chips.append(String(localized: "Good morning ☀️", comment: "Garden: a suggested watering note, offered 05:00–11:59"))
        case 21..., 0..<5:
            chips.append(String(localized: "Good night 🌙", comment: "Garden: a suggested watering note, offered 21:00–04:59"))
        default:
            chips.append(String(localized: "See you soon", comment: "Garden: a suggested watering note, offered in the afternoon and evening"))
        }
        return chips
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { chip in
                    Button {
                        draft.text = limit.truncate(chip)
                    } label: {
                        Text(chip)
                            .font(JourneyFont.caption)
                            .foregroundStyle(Brand.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Brand.backgroundTop))
                            .overlay(Capsule().strokeBorder(Brand.divider, lineWidth: 1))
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.95))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: Field

    private var field: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField(text: $draft.text, axis: .vertical) {
                Text("A few words for \(garden.partnerName) (optional)",
                     comment: "Garden: placeholder of the watering note. %@ is the partner's name.")
            }
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textPrimary)
            .lineLimit(2...4)
            .focused($fieldFocused)
            .padding(12)
            .wellBackground(in: .card)
            .onChange(of: draft.text) { _, text in
                if !limit.accepts(text) { draft.text = limit.truncate(text) }
            }

            // "86/100" once the note nears its limit.
            if draft.text.count >= 80 {
                let count = draft.text.count, maximum = limit.graphemes
                Text("\(count)/\(maximum)",
                     comment: "Garden: characters used in the watering note and the limit, as in '86/100'")
                    .font(JourneyFont.meta)
                    .monospacedDigit()
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityLabel(Text("\(count) of \(maximum) characters",
                                             comment: "VoiceOver: characters used in the watering note and the limit"))
            }
        }
    }

    private var footnote: String {
        let partner = garden.partnerName
        if garden.partner.canGarden == false {
            return String(localized: "\(partner) will see it after updating Coupley.",
                          comment: "Garden: under the watering note when the partner's app is out of date. %@ is the partner's name.")
        }
        return String(localized: "\(partner) sees your note on Journey.",
                      comment: "Garden: under the watering note. %@ is the partner's name.")
    }
}

// MARK: - Preview

// Builds a GardenViewModel on the in-memory service, so DEBUG only (K7).
#if DEBUG
#Preview("Water with a note") {
    let garden = GardenViewModel(session: GardenLab.session, service: InMemoryGardenService())
    Color.clear
        .sheet(isPresented: .constant(true)) {
            WaterNoteSheet(garden: garden, draft: GardenNoteDraft(), onWater: { _ in })
                .presentationDetents([.height(320), .large])
        }
        .onAppear { garden.start() }
}
#endif
