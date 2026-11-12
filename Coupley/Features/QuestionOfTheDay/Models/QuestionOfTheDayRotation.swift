//
//  QuestionOfTheDayRotation.swift
//  Coupley
//
//  Picks which curated question a couple gets on a given day.
//
//  Two properties matter and neither is negotiable:
//
//    1. **Deterministic across devices.** Both partners must land on the same
//       question. That rules out `Hasher`/`hashValue`, which Swift seeds
//       randomly per process — the same string hashes differently on two
//       phones, and differently again after a relaunch. FNV-1a is used
//       instead: a fixed, documented algorithm with no hidden state.
//
//    2. **No repeats until the bank is exhausted.** Stepping the sequence by
//       one and walking the bank modulo its size visits every question before
//       any comes back. A per-couple offset means two couples who start on the
//       same day don't march through the bank in lockstep.
//
//  The sequence number lives on the couple document (`qotdSequence`) and is
//  incremented inside the same transaction that creates the question, so a
//  double-open can't burn two questions on one day.
//

import Foundation

extension ChatQuizBank {

    /// The question for a given couple at a given point in their rotation.
    ///
    /// - Parameters:
    ///   - coupleId: seeds the per-couple offset so couples diverge.
    ///   - sequence: 1-based counter of how many daily questions this couple
    ///     has been served. Comes from `couples/{id}.qotdSequence`.
    static func questionOfTheDay(coupleId: String, sequence: Int) -> ChatQuizTemplate? {
        let bank = all
        guard !bank.isEmpty else { return nil }

        let offset = stableOffset(for: coupleId, modulo: bank.count)
        // `sequence` is always >= 1 in practice; the extra modulo keeps this
        // total in case a bad value ever reaches here.
        let step = ((sequence % bank.count) + bank.count) % bank.count
        return bank[(step + offset) % bank.count]
    }

    /// How many days a couple can go before a question repeats.
    static var rotationLength: Int { all.count }

    /// FNV-1a (64-bit). Chosen over `Hasher` because it is stable across
    /// processes, devices, and OS versions — which is the whole point here.
    private static func stableOffset(for key: String, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV offset basis
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3          // FNV prime
        }
        return Int(hash % UInt64(modulo))
    }
}
