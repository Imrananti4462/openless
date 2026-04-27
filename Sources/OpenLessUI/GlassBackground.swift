import SwiftUI

/// macOS 26+ 用真 Liquid Glass（.glassEffect），macOS 15 fallback 到 .ultraThinMaterial。
struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    func openLessGlass() -> some View {
        modifier(GlassBackground())
    }
}
