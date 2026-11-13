//
//  CurrencyPickerSheet.swift
//  Coupley
//
//  Searchable currency picker shown from the goal editor and goal detail.
//  Lives in the Together feature folder because that's the only surface using
//  it today; promote to Core/Currency if a second feature picks one up.
//

import SwiftUI

struct CurrencyPickerSheet: View {

    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { info in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selected = info.code
                        dismiss()
                    } label: {
                        row(for: info)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        info.code == selected
                            ? Brand.accentStart.opacity(0.10)
                            : Color.clear
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.bgGradient.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringResource("Done", comment: "Toolbar button: closes the sheet")) {
                        dismiss()
                    }
                    .foregroundStyle(Brand.accentStart)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Row

    private func row(for info: CurrencyInfo) -> some View {
        HStack(spacing: 14) {
            Text(info.flag)
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.displayName(for: info))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(verbatim: "\(info.code) · \(info.symbol)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            if info.code == selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Brand.accentStart)
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Display name

    /// The currency's name in the user's language ("Đô la Mỹ" for USD in
    /// Vietnamese): `CurrencyInfo.name`, from Foundation's locale data and
    /// capitalised to stand alone as a row title.
    static func displayName(for info: CurrencyInfo) -> String {
        info.name
    }

    // MARK: - Search

    /// Matches the code, the localized name, the English name and the symbol,
    /// ignoring case and accents, "Đ" included ("do la" finds "Đô la Mỹ").
    /// See `CurrencyInfo.matches(_:)`.
    private var filtered: [CurrencyInfo] {
        CurrencyCatalog.search(query)
    }
}

#Preview {
    StatefulPreviewWrapper("USD") { binding in
        CurrencyPickerSheet(selected: binding)
    }
}

// MARK: - Preview helper

/// Lets us bind into a `@State` from inside a #Preview block without dragging
/// in a hosting view model. Reuse-safe — no side effects beyond preview.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
