//
//  FirestoreConfirmedWrite.swift
//  Coupley
//
//  A Codable write that can actually fail.
//
//  `setData(from:)` has no async form in the Firebase SDK. Writing
//  `try await ref.setData(from:)` compiles, but it calls the synchronous
//  method, which returns as soon as the write is queued locally — so a write
//  the server later rejects (rules, a disconnected couple, an expired session)
//  never reaches a `catch`. The message or mood shows up, then quietly
//  disappears when the listener reconciles.
//
//  The SDK does report the outcome, through a completion handler that fires
//  once the backend has answered. Waiting on it without a limit would hang
//  every write made offline, because offline the answer only comes after
//  reconnecting. So this waits a short while: a rejection inside that window
//  is thrown, an acknowledgement returns normally, and silence is treated as
//  "queued" — Firestore keeps the write and syncs it when it can, exactly as
//  before.
//

import Foundation
import FirebaseFirestore

extension DocumentReference {

    /// Writes `value` and throws if the server rejects it within `timeout`.
    func setDataConfirmed<T: Encodable>(from value: T,
                                        timeout: TimeInterval = 2.5) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            do {
                try setData(from: value) { error in
                    once.run {
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } catch {
                // Encoding failed; the write was never queued.
                once.run { continuation.resume(throwing: error) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                once.run { continuation.resume() }
            }
        }
    }
}

/// Lets exactly one of several racing callbacks through.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
