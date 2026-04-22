//
//  AnniversaryEditorSheet.swift
//  Coupley
//

import SwiftUI
import PhotosUI

// MARK: - Editor

struct AnniversaryEditorSheet: View {

    enum Mode: Equatable {
        case create
        case edit(Anniversary)
    }

    @ObservedObject var viewModel: AnniversaryViewModel
    let mode: Mode

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPaywall = false

    @State private var title: String
    @State private var date: Date
    @State private var note: String
    @State private var showDeleteConfirm = false

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var existingImageURL: String?

    init(viewModel: AnniversaryViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode

        switch mode {
        case .create:
            _title           = State(initialValue: "")
            _date            = State(initialValue: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
            _note            = State(initialValue: "")
            _existingImageURL = State(initialValue: nil)
        case .edit(let a):
            _title           = State(initialValue: a.title)
            _date            = State(initialValue: a.date)
            _note            = State(initialValue: a.note ?? "")
            _existingImageURL = State(initialValue: a.imageURL)
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

                    Section("Cover Photo") {
                        if premiumStore.hasAccess(to: .anniversaryPhoto) {
                            imagePicker
                        } else {
                            lockedPhotoPicker
                        }
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
                    if viewModel.isUploadingImage {
                        ProgressView()
                            .tint(Brand.accentStart)
                    } else {
                        Button(isEditing ? "Save" : "Create") { save() }
                            .foregroundStyle(canSave ? Brand.accentStart : Brand.textTertiary)
                            .disabled(!canSave || viewModel.isSaving)
                    }
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
            .onChange(of: selectedItem) { _, item in
                Task {
                    guard let item else { return }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PremiumPaywallView()
                }
                .environmentObject(premiumStore)
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Locked Photo Picker (free users)

    private var lockedPhotoPicker: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Brand.accentStart.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Brand.accentStart)
                        Text("Premium feature")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.accentStart)
                        Text("Upgrade to add cover photos")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Image Picker

    @ViewBuilder
    private var imagePicker: some View {
        VStack(spacing: 12) {
            if let selected = selectedImage {
                Image(uiImage: selected)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .clipped()
            } else if let urlString = existingImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .clipped()
                    case .failure, .empty:
                        imagePlaceholder
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(
                        (selectedImage != nil || existingImageURL != nil) ? "Change Photo" : "Add Photo",
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
                }

                if selectedImage != nil || existingImageURL != nil {
                    Button(role: .destructive) {
                        selectedImage = nil
                        existingImageURL = nil
                        selectedItem = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var imagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.accentStart.opacity(0.08))
                .frame(maxWidth: .infinity)
                .frame(height: 160)

            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Brand.accentStart.opacity(0.5))
                Text("No photo yet")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Brand.textTertiary)
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
                await viewModel.create(title: title, date: date, note: noteValue, image: selectedImage)
            case .edit(var existing):
                // If user removed the existing image and didn't pick a new one, clear the URL
                if selectedImage == nil && existingImageURL == nil {
                    existing.imageURL = nil
                }
                await viewModel.update(existing, title: title, date: date, note: noteValue, image: selectedImage)
            }
            dismiss()
        }
    }
}
