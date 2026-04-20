//
//  PairingViewModel.swift
//  Coupley
//

import Foundation
import Combine

// MARK: - Pairing Step

enum PairingStep {
    case choice
    case showCode(String)
    case enterCode
}

// MARK: - Live preview state for the enter-code screen
enum CodeLookupState: Equatable {
    case idle
    case loading
    case found(PartnerPreview)
    case failed(String)
}

// MARK: - Pairing ViewModel

@MainActor
final class PairingViewModel: ObservableObject {

    @Published var step: PairingStep = .choice
    @Published var enteredCode: String = "" {
        didSet { scheduleCodeLookup() }
    }
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lookupState: CodeLookupState = .idle

    let userId: String
    let displayName: String

    private let pairingService: PairingServiceProtocol
    private var lookupTask: Task<Void, Never>?

    init(
        userId: String,
        displayName: String,
        pairingService: (any PairingServiceProtocol)? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.pairingService = pairingService ?? FirestorePairingService()
    }

    // MARK: - Actions

    func generateCode() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let code = try await pairingService.createInviteCode(
                    userId: userId,
                    displayName: displayName
                )
                step = .showCode(code)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func joinWithCode() {
        let code = enteredCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await pairingService.joinWithCode(code, userId: userId)
                // SessionStore snapshot listener fires → appState becomes .ready automatically
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func showEnterCode() {
        step = .enterCode
        enteredCode = ""
        errorMessage = nil
        lookupState = .idle
    }

    func back() {
        step = .choice
        errorMessage = nil
        lookupState = .idle
        lookupTask?.cancel()
    }

    // MARK: - Live code lookup

    private func scheduleCodeLookup() {
        lookupTask?.cancel()
        errorMessage = nil

        let normalized = enteredCode
            .uppercased()
            .trimmingCharacters(in: .whitespaces)

        guard normalized.count >= 6 else {
            lookupState = normalized.isEmpty ? .idle : .loading
            return
        }

        lookupState = .loading

        lookupTask = Task { [weak self, pairingService, userId] in
            try? await Task.sleep(nanoseconds: 250_000_000) // debounce
            if Task.isCancelled { return }

            do {
                let preview = try await pairingService.previewCode(normalized)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    if preview.userId == userId {
                        self.lookupState = .failed(PairingError.cannotJoinOwnCode.localizedDescription)
                    } else {
                        self.lookupState = .found(preview)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.lookupState = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Computed

    var canConnect: Bool {
        if case .found = lookupState { return !isLoading }
        return false
    }

    var detectedPartner: PartnerPreview? {
        if case .found(let p) = lookupState { return p }
        return nil
    }
}
