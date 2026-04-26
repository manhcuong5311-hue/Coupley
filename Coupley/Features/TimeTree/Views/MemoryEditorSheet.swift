//
//  MemoryEditorSheet.swift
//  Coupley
//
//  Full-fidelity create/edit form for a TimeMemory. Sections:
//   - Kind selector (large pill row at the top, switches preset)
//   - Title (autofills with kind's display name)
//   - Date (graphical date picker)
//   - Photo (premium-gated, via .anniversaryPhoto entitlement)
//   - Note
//   - Emotions (multi-select chips)
//   - Attribution
//   - Capsule mode (premium-gated, via .memoryCapsule entitlement)
//
//  Capsule mode swaps the "Date" picker for an "Unlock On" picker and
//  shows a soft warning that the memory will be hidden until that day.
//

import SwiftUI
import PhotosUI

// MARK: - Editor

struct MemoryEditorSheet: View {

    enum Mode: Equatable {
        case create(MemoryKind)
        case edit(TimeMemory)
    }

    @ObservedObject var viewModel: TimeTreeViewModel
    let mode: Mode

    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state

    @State private var kind: MemoryKind
    @State private var title: String
    @State private var date: Date
    @State private var note: String
    @State private var emotions: Set<MemoryEmotion>
    @State private var attribution: String
    @State private var isCapsule: Bool
    @State private var unlockDate: Date

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var existingPhotoURL: String?
    @State private var clearPhoto: Bool = false

    @State private var showDeleteConfirm = false
    @State private var showPaywall = false

    // MARK: - Init

    init(viewModel: TimeTreeViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode

        switch mode {
        case .create(let kind):
            _kind = State(initialValue: kind)
            _title = State(initialValue: kind == .custom ? "" : kind.displayName)
            _date = State(initialValue: Date())
            _note = State(initialValue: "")
            _emotions = State(initialValue: Set(kind.suggestedEmotions))
            _attribution = State(initialValue: "")
            _isCapsule = State(initialValue: false)
            _unlockDate = State(initialValue: Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date())
            _existingPhotoURL = State(initialValue: nil)
        case .edit(let memory):
            _kind = State(initialValue: memory.kind)
            _title = State(initialValue: memory.title)
            _date = State(initialValue: memory.date)
            _note = State(initialValue: memory.note ?? "")
            _emotions = State(initialValue: Set(memory.emotions))
            _attribution = State(initialValue: memory.attribution ?? "")
            _isCapsule = State(initialValue: memory.unlockDate != nil)
            _unlockDate = State(initialValue: memory.unlockDate ?? (Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()))
            _existingPhotoURL = State(initialValue: memory.photoURL)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bgGradient.ignoresSafeArea()

                Form {
                    kindSection
                    titleSection
                    if isCapsule {
                        capsuleUnlockSection
                    } else {
                        dateSection
                    }
                    photoSection
                    noteSection
                    emotionsSection
                    attributionSection
                    capsuleToggleSection

                    if isEditing {
                        deleteSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "Edit Memory" : "New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isUploadingPhoto {
                        ProgressView().tint(Brand.accentStart)
                    } else {
                        Button(isEditing ? "Save" : "Create") { save() }
                            .foregroundStyle(canSave ? Brand.accentStart : Brand.textTertiary)
                            .disabled(!canSave || viewModel.isSavingMemory)
                    }
                }
            }
            .onChange(of: selectedItem) { _, item in
                Task {
                    guard let item else { return }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                        clearPhoto = false
                    }
                }
            }
            .confirmationDialog(
                "Delete this memory?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if case .edit(let m) = mode {
                        Task {
                            await viewModel.deleteMemory(m)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your partner will stop seeing it too.")
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

    // MARK: - Kind section

    private var kindSection: some View {
        Section("Kind") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MemoryKind.allCases.sorted { $0.pickerOrder < $1.pickerOrder }) { k in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            kind = k
                            // Re-suggest emotions if the user hasn't customized
                            if emotions.isEmpty {
                                emotions = Set(k.suggestedEmotions)
                            }
                            // Auto-fill title for first time only
                            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                title = k == .custom ? "" : k.displayName
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(k.emoji).font(.system(size: 13))
                                Text(k.displayName)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(kind == k ? Brand.accentStart.opacity(0.18) : Brand.surfaceMid)
                                    .overlay(
                                        Capsule().strokeBorder(
                                            kind == k ? Brand.accentStart : Brand.divider,
                                            lineWidth: 1
                                        )
                                    )
                            )
                            .foregroundStyle(kind == k ? Brand.accentStart : Brand.textSecondary)
                        }
                        .buttonStyle(BouncyButtonStyle(scale: 0.94))
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        Section("Title") {
            TextField(kind.displayName, text: $title)
                .font(.system(size: 16, design: .rounded))
                .textInputAutocapitalization(.sentences)
        }
    }

    // MARK: - Date

    private var dateSection: some View {
        Section("Date") {
            DatePicker("Date", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .tint(Brand.accentStart)
        }
    }

    // MARK: - Capsule unlock

    private var capsuleUnlockSection: some View {
        Section {
            DatePicker(
                "Unlock On",
                selection: $unlockDate,
                in: Date()...,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .tint(Brand.accentStart)

            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                Text("Hidden from both of you until this day.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
            }
            .foregroundStyle(Brand.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text("Unlock Date")
        }
    }

    // MARK: - Photo

    private var photoSection: some View {
        Section("Photo") {
            if premiumStore.hasAccess(to: .anniversaryPhoto) {
                photoPicker
            } else {
                lockedPhotoCard
            }
        }
    }

    @ViewBuilder
    private var photoPicker: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .clipped()
            } else if let urlString = existingPhotoURL, !clearPhoto, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .clipped()
                    case .empty, .failure:
                        photoPlaceholder
                    @unknown default:
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(
                        (selectedImage != nil || (existingPhotoURL != nil && !clearPhoto)) ? "Change Photo" : "Add Photo",
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.accentStart)
                }

                if selectedImage != nil || (existingPhotoURL != nil && !clearPhoto) {
                    Button(role: .destructive) {
                        selectedImage = nil
                        clearPhoto = true
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

    private var photoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Brand.accentStart.opacity(0.06))
                .frame(maxWidth: .infinity)
                .frame(height: 180)

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

    private var lockedPhotoCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Brand.accentStart.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 110)
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Brand.accentStart)
                        Text("Premium feature")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.accentStart)
                        Text("Upgrade to add memory photos")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Note

    private var noteSection: some View {
        Section {
            TextField(kind.notePrompt, text: $note, axis: .vertical)
                .font(.system(size: 15, design: .rounded))
                .lineLimit(3...8)
        } header: {
            Text("Note")
        }
    }

    // MARK: - Emotions

    private var emotionsSection: some View {
        Section("Emotions") {
            FlowLayout(spacing: 8) {
                ForEach(MemoryEmotion.allCases) { emotion in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if emotions.contains(emotion) { emotions.remove(emotion) }
                        else { emotions.insert(emotion) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(emotion.emoji).font(.system(size: 11))
                            Text(emotion.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(emotions.contains(emotion) ? Brand.accentStart.opacity(0.18) : Brand.surfaceMid)
                                .overlay(
                                    Capsule().strokeBorder(
                                        emotions.contains(emotion) ? Brand.accentStart : Brand.divider,
                                        lineWidth: 1
                                    )
                                )
                        )
                        .foregroundStyle(emotions.contains(emotion) ? Brand.accentStart : Brand.textSecondary)
                    }
                    .buttonStyle(BouncyButtonStyle(scale: 0.94))
                }
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    // MARK: - Attribution

    private var attributionSection: some View {
        Section {
            TextField("e.g. \"From Sam\" or \"From us both\"", text: $attribution)
                .font(.system(size: 15, design: .rounded))
                .textInputAutocapitalization(.sentences)
        } header: {
            Text("Who's writing this?")
        }
    }

    // MARK: - Capsule toggle

    private var capsuleToggleSection: some View {
        Section {
            if premiumStore.hasAccess(to: .memoryCapsule) {
                Toggle(isOn: $isCapsule) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Make this a Capsule")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                            Text("Hide it until a future date.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(Brand.textSecondary)
                        }
                    }
                }
                .tint(Brand.accentStart)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Brand.accentStart)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Memory Capsule")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                            Text("Premium — write a memory that opens later")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(Brand.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Capsule")
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button("Delete memory", role: .destructive) {
                showDeleteConfirm = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue: String? = trimmedNote.isEmpty ? nil : trimmedNote
        let trimmedAttribution = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributionValue: String? = trimmedAttribution.isEmpty ? nil : trimmedAttribution

        let unlock: Date? = isCapsule ? unlockDate : nil
        // Capsule date doubles as the memory date (the day it'll surface).
        let memoryDate = isCapsule ? unlockDate : date

        let emotionList = MemoryEmotion.allCases.filter { emotions.contains($0) }

        Task {
            switch mode {
            case .create:
                await viewModel.createMemory(
                    kind: kind,
                    title: title,
                    date: memoryDate,
                    note: noteValue,
                    emotions: emotionList,
                    attribution: attributionValue,
                    anniversaryId: nil,
                    unlockDate: unlock,
                    photo: selectedImage
                )
            case .edit(let existing):
                await viewModel.updateMemory(
                    existing,
                    kind: kind,
                    title: title,
                    date: memoryDate,
                    note: noteValue,
                    emotions: emotionList,
                    attribution: attributionValue,
                    anniversaryId: existing.anniversaryId,
                    unlockDate: unlock,
                    photo: selectedImage,
                    clearPhoto: clearPhoto
                )
            }
            dismiss()
        }
    }
}
