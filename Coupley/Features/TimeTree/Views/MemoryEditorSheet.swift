//
//  MemoryEditorSheet.swift
//  Coupley
//
//  Create or edit one memory. Sections:
//   - Kind (pill row; switches the preset)
//   - Title (autofills with the kind's name)
//   - Date, which also holds the capsule switch: "Seal until a day, for
//     both of you". On, the memory date becomes an "Opens on" day, and the
//     capsule opens at 9:00 that morning (JourneyCalendarDay), the same
//     moment its reminder fires.
//   - Photo, Note, Emotions, Attribution
//   - Delete (edit only)
//
//  A capsule is hidden in the app for both partners; a future letter is
//  sealed on the server for one. When the sheet is creating a memory and its
//  presenter can write letters, a row under the switch hands the typed note
//  and the chosen day to a future letter instead.
//
//  Editing a capsule that has already opened never re-locks it: there is no
//  switch, and Save keeps its unlock moment. A sealed capsule reaches this
//  sheet only for its author (MemoryDetailSheet hides Edit otherwise), who
//  can move the day or switch the seal off, which opens it for both.
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Editor

struct MemoryEditorSheet: View {

    enum Mode: Equatable {
        case create(MemoryKind)
        case edit(TimeMemory)
    }

    @ObservedObject var viewModel: TimeTreeViewModel
    let mode: Mode
    let partnerName: String
    /// Hands the trimmed note and, when the capsule switch is on, its unlock
    /// moment to a future letter. The presenter opens Compose once this
    /// sheet is gone. Offered in create mode only, and only when non-nil.
    let onWriteLetterInstead: ((_ seed: String, _ opensAt: Date?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Form state

    @State private var kind: MemoryKind
    @State private var title: String
    @State private var date: Date
    @State private var note: String
    @State private var emotions: Set<MemoryEmotion>
    @State private var attribution: String
    @State private var isCapsule: Bool
    /// The day the capsule opens. Only its calendar day is used.
    @State private var unlockDay: Date

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var existingPhotoURL: String?
    @State private var clearPhoto = false

    @State private var showDeleteConfirm = false

    // MARK: - Init

    init(viewModel: TimeTreeViewModel,
         mode: Mode,
         partnerName: String = String(localized: "your partner",
                                      comment: "Stands in for the partner's name inside a sentence when it is unknown"),
         onWriteLetterInstead: ((_ seed: String, _ opensAt: Date?) -> Void)? = nil) {
        self.viewModel = viewModel
        self.mode = mode
        self.partnerName = partnerName
        self.onWriteLetterInstead = onWriteLetterInstead

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sixMonthsOut = calendar.date(byAdding: .month, value: 6, to: today) ?? today

        switch mode {
        case .create(let kind):
            _kind = State(initialValue: kind)
            _title = State(initialValue: kind == .custom ? "" : kind.displayName)
            _date = State(initialValue: Date())
            _note = State(initialValue: "")
            _emotions = State(initialValue: Set(kind.suggestedEmotions))
            _attribution = State(initialValue: "")
            _isCapsule = State(initialValue: false)
            _unlockDay = State(initialValue: sixMonthsOut)
            _existingPhotoURL = State(initialValue: nil)
        case .edit(let memory):
            let isSealed = memory.isLocked(at: viewModel.now)
            _kind = State(initialValue: memory.kind)
            _title = State(initialValue: memory.title)
            _date = State(initialValue: memory.date)
            _note = State(initialValue: memory.note ?? "")
            _emotions = State(initialValue: Set(memory.emotions))
            _attribution = State(initialValue: memory.attribution ?? "")
            _isCapsule = State(initialValue: isSealed)
            _unlockDay = State(initialValue: isSealed ? (memory.unlockDate ?? sixMonthsOut) : sixMonthsOut)
            _existingPhotoURL = State(initialValue: memory.photoURL)
        }
    }

    // MARK: - Derived

    /// What the memory being edited is, as a capsule, on the Journey clock.
    private enum CapsuleState: Equatable {
        /// Creating, or editing a memory that was never sealed.
        case none
        /// Editing a capsule whose day has not come.
        case sealed(unlock: Date)
        /// Editing a capsule that has opened.
        case opened(unlock: Date)
    }

    private var capsuleState: CapsuleState {
        guard case .edit(let existing) = mode, let unlock = existing.unlockDate else { return .none }
        return existing.isLocked(at: viewModel.now) ? .sealed(unlock: unlock) : .opened(unlock: unlock)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Whether the seal switch is offered. An opened capsule never gets it
    /// back. A plain memory can be sealed by whoever wrote it: only the
    /// author can later move or lift a seal, so sealing someone else's
    /// memory would hide it from them with no way back.
    private var canSeal: Bool {
        switch mode {
        case .create:
            return true
        case .edit(let existing):
            switch capsuleState {
            case .none:   return existing.createdBy == viewModel.currentUserId
            case .sealed: return true
            case .opened: return false
            }
        }
    }

    private var isSealing: Bool { canSeal && isCapsule }

    private var showsLetterRow: Bool {
        if case .create = mode { return onWriteLetterInstead != nil }
        return false
    }

    /// From the start of tomorrow to ten years out. A sealed capsule that
    /// opens later today keeps its own day selectable, so leaving the picker
    /// alone can never move it.
    private var unlockRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let tenYearsOut = calendar.date(byAdding: .year, value: 10, to: today) ?? tomorrow
        guard case .sealed(let unlock) = capsuleState else { return tomorrow...tenYearsOut }
        let sealedDay = calendar.startOfDay(for: unlock)
        return min(tomorrow, sealedDay)...max(tenYearsOut, sealedDay)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasPhoto: Bool {
        selectedImage != nil || (existingPhotoURL != nil && !clearPhoto)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                titleSection
                dateSection
                photoSection
                noteSection
                emotionsSection
                attributionSection

                if isEditing {
                    deleteSection
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.bgGradient.ignoresSafeArea())
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
                            .disabled(!canSave || viewModel.isSavingMemory || isLoadingPhoto)
                    }
                }
            }
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                loadPhoto(item)
            }
            .confirmationDialog(
                "Delete this memory?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if case .edit(let memory) = mode {
                        Task {
                            await viewModel.deleteMemory(memory)
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

    // MARK: - Kind

    private var kindSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MemoryKind.allCases.sorted { $0.pickerOrder < $1.pickerOrder }) { option in
                        kindPill(option)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } header: {
            sectionHeader(LocalizedStringResource("Kind", comment: "Memory editor section header: what kind of memory this is"))
        }
    }

    private func kindPill(_ option: MemoryKind) -> some View {
        let isSelected = kind == option
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            kind = option
            // Re-suggest feelings only while none are picked.
            if emotions.isEmpty {
                emotions = Set(option.suggestedEmotions)
            }
            // Autofill the title only while it is empty.
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = option == .custom ? "" : option.displayName
            }
        } label: {
            HStack(spacing: 5) {
                Text(option.emoji)
                    .accessibilityHidden(true)
                Text(option.displayName)
            }
            .font(JourneyFont.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Brand.accentStart.opacity(0.18) : Brand.surfaceMid)
                    .overlay(
                        Capsule().strokeBorder(isSelected ? Brand.accentStart : Brand.divider,
                                               lineWidth: 1)
                    )
            )
            .foregroundStyle(isSelected ? Brand.accentStart : Brand.textSecondary)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.94))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Title

    private var titleSection: some View {
        Section {
            TextField(kind.displayName, text: $title)
                .font(JourneyFont.title)
                .foregroundStyle(Brand.textPrimary)
                .textInputAutocapitalization(.sentences)
        } header: {
            sectionHeader(LocalizedStringResource("Title", comment: "Memory editor section header: the memory's title"))
        }
    }

    // MARK: - Date and seal

    private var dateSection: some View {
        Section {
            if canSeal {
                sealToggle

                if case .sealed = capsuleState, !isCapsule {
                    Text("Saving now opens it for both of you.")
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                }

                if showsLetterRow {
                    letterInsteadRow
                }
            }

            if case .opened(let unlock) = capsuleState {
                openedLine(unlock)
            }

            if isSealing {
                DatePicker(selection: $unlockDay,
                           in: unlockRange,
                           displayedComponents: [.date]) {
                    Text("Opens on", comment: "Memory editor: the day a sealed capsule opens")
                }
                .datePickerStyle(.graphical)
                .tint(Brand.accentStart)
            } else {
                DatePicker(selection: $date, displayedComponents: [.date]) {
                    Text("Date", comment: "Memory editor: the calendar day the memory happened (not a romantic date)")
                }
                .datePickerStyle(.graphical)
                .tint(Brand.accentStart)
            }
        } header: {
            sectionHeader(isSealing
                          ? LocalizedStringResource("Opens on", comment: "Memory editor: the day a sealed capsule opens")
                          : LocalizedStringResource("Date", comment: "Memory editor: the calendar day the memory happened (not a romantic date)"))
        }
    }

    private var sealToggle: some View {
        Toggle(isOn: $isCapsule.animation(reduceMotion ? nil : .snappy)) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(JourneyFont.label)
                    .foregroundStyle(FutureLetterStyle.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Seal until a day, for both of you")
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textPrimary)
                    Text("The app keeps the note, photo and feelings out of sight for both of you until \(sealOpeningTime) that day. It's hidden, not locked.",
                         comment: "Memory editor, under the capsule switch. %@ is a time of day such as '9:00 AM'.")
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Brand.accentStart)
    }

    /// When the capsule being sealed opens on its day, mirroring save(): a
    /// moment an older version stored is kept while its day is unchanged;
    /// any other day opens at 9:00.
    private var sealOpeningTime: String {
        if case .sealed(let existingUnlock) = capsuleState,
           Calendar.current.isDate(unlockDay, inSameDayAs: existingUnlock) {
            return existingUnlock.formatted(date: .omitted, time: .shortened)
        }
        return JourneyCalendarDay.capsuleUnlockMoment(forLocalDay: unlockDay)
            .formatted(date: .omitted, time: .shortened)
    }

    private var letterInsteadRow: some View {
        Button(action: writeLetterInstead) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(JourneyFont.label)
                    .foregroundStyle(FutureLetterStyle.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just for \(partnerName)?")
                        .font(JourneyFont.label)
                        .foregroundStyle(Brand.textPrimary)
                    Text("Write a future letter instead — only they can open it, and not a moment early.")
                        .font(JourneyFont.meta)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(JourneyFont.meta)
                    .foregroundStyle(Brand.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Closes this memory and starts a letter with your note.")
    }

    private func openedLine(_ unlock: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.open.fill")
                .font(JourneyFont.caption)
                .foregroundStyle(FutureLetterStyle.gold)
                .accessibilityHidden(true)
            Text("Opened \(unlock.formatted(date: .long, time: .omitted))")
                .font(JourneyFont.caption)
                .foregroundStyle(JourneyStyle.goldText)
        }
    }

    // MARK: - Photo

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                photoPreview

                HStack(spacing: 16) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(hasPhoto ? "Change Photo" : "Add Photo", systemImage: "photo.on.rectangle")
                            .font(JourneyFont.label)
                            .foregroundStyle(Brand.accentStart)
                    }
                    .buttonStyle(.borderless)

                    if hasPhoto {
                        Button(role: .destructive) {
                            selectedImage = nil
                            clearPhoto = true
                            selectedItem = nil
                            isLoadingPhoto = false
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(JourneyFont.label)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        } header: {
            sectionHeader(LocalizedStringResource("Photo", comment: "Memory editor section header: the memory's photo"))
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: Brand.cornerStyle)
        if isLoadingPhoto {
            ProgressView()
                .tint(Brand.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(shape.fill(Brand.accentStart.opacity(0.06)))
        } else if let image = selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(shape)
                .accessibilityLabel("Chosen photo")
        } else if let urlString = existingPhotoURL, !clearPhoto, let url = URL(string: urlString) {
            CachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                ZStack {
                    Brand.accentStart.opacity(0.06)
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
            }
            .clipShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current photo")
            .accessibilityAddTraits(.isImage)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.title2.weight(.light))
                    .foregroundStyle(Brand.accentStart.opacity(0.5))
                    .accessibilityHidden(true)
                Text("No photo yet")
                    .font(JourneyFont.body)
                    .foregroundStyle(Brand.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(shape.fill(Brand.accentStart.opacity(0.06)))
        }
    }

    /// Decodes a picked photo at most 1600px on its long edge, straight from
    /// the file through ImageIO, so a 12 MP original is never held in memory
    /// as a full bitmap. A newer pick supersedes a slower, older one.
    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            let image = await Self.downsampled(data)
            guard selectedItem == item else { return }
            isLoadingPhoto = false
            if let image {
                selectedImage = image
                clearPhoto = false
            }
        }
    }

    /// The decode runs off the main actor.
    private static func downsampled(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            ImageCache.downsampledImage(data: data, maxPixelSize: 1600)
        }.value
    }

    // MARK: - Note

    private var noteSection: some View {
        Section {
            TextField(kind.notePrompt, text: $note, axis: .vertical)
                .font(JourneyFont.body)
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(3...8)
        } header: {
            sectionHeader(LocalizedStringResource("Note", comment: "Memory editor section header: the memory's written story (noun)"))
        }
    }

    // MARK: - Emotions

    private var emotionsSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(MemoryEmotion.allCases) { emotion in
                    emotionChip(emotion)
                }
            }
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: {
            sectionHeader(LocalizedStringResource("Emotions", comment: "Memory editor section header: feeling tags for the memory"))
        }
    }

    private func emotionChip(_ emotion: MemoryEmotion) -> some View {
        let isSelected = emotions.contains(emotion)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                emotions.remove(emotion)
            } else {
                emotions.insert(emotion)
            }
        } label: {
            HStack(spacing: 4) {
                Text(emotion.emoji)
                    .accessibilityHidden(true)
                Text(emotion.displayName)
            }
            .font(JourneyFont.caption)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Brand.accentStart.opacity(0.18) : Brand.surfaceMid)
                    .overlay(
                        Capsule().strokeBorder(isSelected ? Brand.accentStart : Brand.divider,
                                               lineWidth: 1)
                    )
            )
            .foregroundStyle(isSelected ? Brand.accentStart : Brand.textSecondary)
        }
        .buttonStyle(BouncyButtonStyle(scale: 0.94))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Attribution

    private var attributionSection: some View {
        Section {
            TextField(text: $attribution) {
                Text("e.g. \"From Sam\" or \"From us both\"",
                     comment: "Placeholder: who a memory is from. 'Sam' is an example first name; use a common one in your language.")
            }
            .font(JourneyFont.body)
            .foregroundStyle(Brand.textPrimary)
            .textInputAutocapitalization(.sentences)
        } header: {
            sectionHeader(LocalizedStringResource("Who's writing this?", comment: "Memory editor section header: who the memory is from"))
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button("Delete memory", role: .destructive) {
                showDeleteConfirm = true
            }
            .font(JourneyFont.label)
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionHeader(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(JourneyFont.caption)
            .foregroundStyle(Brand.textSecondary)
    }

    // MARK: - Actions

    private func writeLetterInstead() {
        guard let onWriteLetterInstead else { return }
        let seed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let opensAt = isSealing ? JourneyCalendarDay.capsuleUnlockMoment(forLocalDay: unlockDay) : nil
        onWriteLetterInstead(seed, opensAt)
        dismiss()
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue: String? = trimmedNote.isEmpty ? nil : trimmedNote
        let trimmedAttribution = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributionValue: String? = trimmedAttribution.isEmpty ? nil : trimmedAttribution
        let emotionList = MemoryEmotion.allCases.filter { emotions.contains($0) }

        // A capsule's date doubles as its memory date: the day it surfaces.
        let unlock: Date?
        let memoryDate: Date
        switch capsuleState {
        case .opened(let existingUnlock):
            // Fixing a typo must never re-lock an opened capsule.
            unlock = existingUnlock
            memoryDate = date
        case .sealed(let existingUnlock):
            if isCapsule {
                // Same day as before: keep the stored moment, so a capsule
                // saved by an older version opens exactly when it always
                // would have. A new day opens at 9:00 that morning.
                let moment = Calendar.current.isDate(unlockDay, inSameDayAs: existingUnlock)
                    ? existingUnlock
                    : JourneyCalendarDay.capsuleUnlockMoment(forLocalDay: unlockDay)
                unlock = moment
                memoryDate = moment
            } else {
                unlock = nil
                memoryDate = date
            }
        case .none:
            if isSealing {
                let moment = JourneyCalendarDay.capsuleUnlockMoment(forLocalDay: unlockDay)
                unlock = moment
                memoryDate = moment
            } else {
                unlock = nil
                memoryDate = date
            }
        }

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
