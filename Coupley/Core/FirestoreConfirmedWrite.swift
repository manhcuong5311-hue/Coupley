//
//  FirestoreConfirmedWrite.swift
//  Coupley
//
//  Writes that can actually fail, and never hang offline.
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
//  The dictionary `setData(_:merge:)` and `delete()` do have async forms, but
//  those wait for the server with no limit: offline, a Save button stays
//  disabled until the connection returns. The confirmed variants below give
//  them the same short-wait contract.
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

    /// The dictionary form of `setDataConfirmed(from:)`: writes `data`
    /// (merged into the document when `merge` is true) and throws if the
    /// server rejects it within `timeout`. Silence (offline) returns with the
    /// write still queued, where `try await setData(_:merge:)` would hang
    /// until the device reconnects.
    func setDataConfirmed(_ data: [String: Any],
                          merge: Bool = false,
                          timeout: TimeInterval = 2.5) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            setData(data, merge: merge) { error in
                once.run {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                once.run { continuation.resume() }
            }
        }
    }

    /// `updateData` with the same short-wait contract. Unlike a merging
    /// `setData`, it never creates the document: if it is gone (deleted on
    /// another phone, even while this write sat queued offline), the server
    /// answers NOT_FOUND (PERMISSION_DENIED where the rules read the missing
    /// document) instead of bringing it back.
    func updateDataConfirmed(_ fields: [AnyHashable: Any],
                             timeout: TimeInterval = 2.5) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            updateData(fields) { error in
                once.run {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                once.run { continuation.resume() }
            }
        }
    }

    /// Deletes the document and throws if the server rejects it within
    /// `timeout`. Silence (offline) returns with the delete still queued.
    func deleteConfirmed(timeout: TimeInterval = 2.5) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            delete { error in
                once.run {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                once.run { continuation.resume() }
            }
        }
    }
}

extension WriteBatch {

    /// Same contract as `setDataConfirmed`: a rejection inside `timeout`
    /// throws, an acknowledgement returns, and silence (offline) returns with
    /// the batch still queued. `try await commit()` would hang until the
    /// device reconnects.
    func commitConfirmed(timeout: TimeInterval = 2.5) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            commit { error in
                once.run {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
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
