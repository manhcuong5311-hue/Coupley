//
//  WidgetGlassCapsule.swift
//  CoupleyWidget
//
//  Reusable glass-morphism container — used for mood pills, nudge bubbles,
//  and milestone chips. Outside iOS 26's stylised material APIs, the
//  cleanest cross-version look is a translucent fill + hairline border.
//

import SwiftUI

struct WidgetGlassCapsule<Content: View>: View {

    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 7
    var cornerRadius: CGFloat = 18
    var tint: Color = WidgetPalette.glass
    var border: Color = WidgetPalette.glassBorder
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.6)
            )
    }
}

// MARK: - Glass Card (rectangle variant)

struct WidgetGlassCard<Content: View>: View {

    var padding: EdgeInsets = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    var cornerRadius: CGFloat = 16
    var tint: Color = WidgetPalette.glass
    var border: Color = WidgetPalette.glassBorder
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.6)
            )
    }
}
