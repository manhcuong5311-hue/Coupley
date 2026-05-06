//
//  FirestoreListenerBag.swift
//  Coupley
//
//  Lightweight holder for Firestore `ListenerRegistration` tokens. Use this
//  whenever a service or view model owns more than one snapshot subscription
//  so cleanup is a single `.removeAll()` call instead of N nilable fields.
//
//  Why we need it
//  --------------
//  After Firebase signs the user out, any Firestore listeners that survive
//  briefly poll on the now-unauthorized session and the SDK fills the
//  console with "Missing or insufficient permissions" warnings. The fix is
//  deterministic teardown: pre-signOut, every owner of listeners calls
//  `removeAll()` on its bag. SessionStore drives this via its
//  `registerTeardown` hook system, so adding a new listener-holding service
//  is a two-step pattern:
//
//      1. Store a `FirestoreListenerBag` and put new listeners into it.
//      2. From the owner's setup site, call
//         `sessionStore.registerTeardown { [weak self] in self?.bag.removeAll() }`.
//
//  Threading
//  ---------
//  Pinned to `@MainActor` because all current call sites mutate from the
//  main actor (view models, observable stores). The Firestore SDK's
//  `ListenerRegistration.remove()` is documented thread-safe, so the
//  non-isolated `deinit` can call into the underlying tokens directly.
//

import Foundation
import FirebaseFirestore

@MainActor
final class FirestoreListenerBag {

    private var registrations: [ListenerRegistration] = []

    init() {}

    /// Adds a registration to the bag. The bag takes ownership — when
    /// `removeAll()` runs (or when the bag deinits), the registration is
    /// torn down.
    func insert(_ registration: ListenerRegistration) {
        registrations.append(registration)
    }

    /// Convenience wrapper for the common `bag.insert(ref.addSnapshotListener { ... })`
    /// pattern. Returns the registration in case the caller wants to also
    /// hold it directly (e.g. for early removal of just one listener).
    @discardableResult
    func register(_ make: () -> ListenerRegistration) -> ListenerRegistration {
        let reg = make()
        registrations.append(reg)
        return reg
    }

    /// Number of live registrations. Useful in tests / debug logs.
    var count: Int { registrations.count }

    var isEmpty: Bool { registrations.isEmpty }

    /// Tear down every registration the bag is holding. Idempotent — safe
    /// to call multiple times.
    func removeAll() {
        for registration in registrations {
            registration.remove()
        }
        registrations.removeAll()
    }

    deinit {
        // ListenerRegistration.remove() is thread-safe per the Firestore
        // SDK's documentation, so a non-isolated deinit can call it
        // directly. Belt-and-suspenders against forgotten teardown calls.
        for registration in registrations {
            registration.remove()
        }
    }
}
