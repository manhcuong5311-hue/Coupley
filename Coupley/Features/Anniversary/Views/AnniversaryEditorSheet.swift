//
//  AnniversaryEditorSheet.swift
//  Coupley
//

import SwiftUI

// MARK: - Editor

struct AnniversaryEditorSheet: View {

    enum Mode: Equatable {
        case create
        case edit(Anniversary)
    }

    @ObservedObject var viewModel: AnniversaryViewModel
    let mode: Mode

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var date: Date
    @State private var note: String
    @State private var showDeleteConfirm = false

    init(viewModel: AnniversaryViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode

        switch mode {
        case .create:
            _title = State(initialValue: "")
            _date  = State(initialValue: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
            _note  = State(initialValue: "")
        case .edit(let a):
            _title = State(initialValue: a.title)
            _date  = State(initialValue: a.date)
            _note  = State(initialValue: a.note ?? "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                Form {
                    Section("Title") {
                        TextField("1 year together", text: $title)
                            .font(.system(size: 16, design: .rounded))
                            .textInputAutocapitalization(.sentences)
                    }

                    Section("Date") {
                        DatePicker(
                            "Date",
                            selection: $date,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .tint(Brand.accentStart)
                    }

                    Section("Note (optional)") {
                        TextField("Something to remember…", text: $note, axis: .vertical)
                            .font(.system(size: 15, design: .rounded))
                            .lineLimit(3...6)
                    }

                    if isEditing {
                        Section {
                            Button("Delete anniversary", role: .destructive) {
                                showDeleteConfirm = true
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "Edit" : "New Anniversary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Create") { save() }
                        .foregroundStyle(canSave ? Brand.accentStart : Brand.textTertiary)
                        .disabled(!canSave || viewModel.isSaving)
                }
            }
            .confirmationDialog(
                "Delete this anniversary?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if case .edit(let a) = mode {
                        Task {
                            await viewModel.delete(a)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your partner will stop seeing it too.")
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue: String? = trimmedNote.isEmpty ? nil : trimmedNote

        Task {
            switch mode {
            case .create:
                await viewModel.create(title: title, date: date, note: noteValue)
            case .edit(let existing):
                await viewModel.update(existing, title: title, date: date, note: noteValue)
            }
            dismiss()
        }
    }
}
