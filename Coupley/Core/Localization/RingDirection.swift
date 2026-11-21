//
//  RingDirection.swift
//  Coupley
//
//  A progress ring that starts at the top in every language.
//

import SwiftUI

extension View {

    /// For a ring drawn with `trim` and turned a quarter back, so that it
    /// starts at twelve o'clock. In a right-to-left language that turn runs
    /// the other way and the ring starts at six. This keeps the ring's own
    /// drawing left-to-right: it starts at the top and fills clockwise in
    /// every language, like a clock face. Goes after `rotationEffect`.
    func ringStartsAtTop() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}
