//
//  QuizViewModel.swift
//  Coupley
//
//  Created by Sam Manh Cuong on 1/4/26.
//

import Foundation
import Combine
// MARK: - Quiz State

enum QuizState: Equatable {
    case nameEntry
    case inProgress
    case saving
    case completed
}

// MARK: - Quiz ViewModel

@MainActor
final class QuizViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var partnerName: String = ""
    @Published var quizState: QuizState = .nameEntry
    @Published var currentIndex: Int = 0
    @Published var currentAnswer: QuizAnswer = .empty
    @Published var answers: [UUID: QuizAnswer] = [:]
    @Published var profile: PartnerProfile = .emptyPartner

    // MARK: - Computed Properties

    var questions: [QuizQuestion] {
        QuizBank.allQuestions(partnerName: partnerName)
    }

    var currentQuestion: QuizQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var totalQuestions: Int {
        questions.count
    }

    var progress: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(currentIndex) / Double(totalQuestions)
    }

    var isLastQuestion: Bool {
        currentIndex >= totalQuestions - 1
    }

    var canProceed: Bool {
        !currentAnswer.isEmpty
    }

    var canStartQuiz: Bool {
        !partnerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Dependencies

    private let profileService: ProfileService

    // MARK: - Init

    init(profileService: (any ProfileService)? = nil) {
        self.profileService = profileService ?? LocalProfileService()
    }

    // MARK: - Actions

    func startQuiz() {
        let trimmed = partnerName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        profile = PartnerProfile(name: trimmed)
        currentIndex = 0
        currentAnswer = .empty
        answers = [:]

        withStateAnimation {
            self.quizState = .inProgress
        }
    }

    func saveAnswer() {
        guard let question = currentQuestion else { return }

        answers[question.id] = currentAnswer

        // Apply answer to profile
        profileService.updatePreference(
            category: question.category,
            values: currentAnswer.allValues,
            in: &profile
        )

        // Add to likes for AI consumption
        let newLikes = currentAnswer.allValues.filter { !$0.isEmpty }
        profile.likes.append(contentsOf: newLikes)
    }

    func nextQuestion() {
        saveAnswer()

        if isLastQuestion {
            finishQuiz()
        } else {
            currentIndex += 1
            // Restore previous answer if going back
            if let question = currentQuestion, let saved = answers[question.id] {
                currentAnswer = saved
            } else {
                currentAnswer = .empty
            }
        }
    }

    func previousQuestion() {
        guard currentIndex > 0 else { return }
        saveAnswer()
        currentIndex -= 1
        if let question = currentQuestion, let saved = answers[question.id] {
            currentAnswer = saved
        } else {
            currentAnswer = .empty
        }
    }

    func toggleOption(_ option: String) {
        if currentQuestion?.allowsMultiple == true {
            if currentAnswer.selectedOptions.contains(option) {
                currentAnswer.selectedOptions.remove(option)
            } else {
                currentAnswer.selectedOptions.insert(option)
            }
        } else {
            currentAnswer.selectedOptions = [option]
        }
    }

    func updateTextInput(_ text: String) {
        let items = text
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        currentAnswer.textValues = items
    }

    // MARK: - Private

    private func finishQuiz() {
        // Deduplicate likes
        profile.likes = Array(Set(profile.likes))

        quizState = .saving

        Task {
            do {
                try await profileService.saveProfile(profile)
                withStateAnimation {
                    self.quizState = .completed
                }
            } catch {
                // Fallback: mark as completed anyway (data is in memory)
                withStateAnimation {
                    self.quizState = .completed
                }
            }
        }
    }

    private func withStateAnimation(_ body: @escaping () -> Void) {
        body()
        objectWillChange.send()
    }
}
