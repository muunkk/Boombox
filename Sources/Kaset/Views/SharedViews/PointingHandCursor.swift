import AppKit
import SwiftUI

// MARK: - PointingHandCursor

/// Switches to the system pointing-hand cursor while the receiving view is
/// hovered, *and* underlines any text within the view. Use to signal that
/// something is clickable (the typical "link" affordance on the web).
extension View {
    func pointingHandCursor() -> some View {
        modifier(LinkHoverModifier())
    }
}

private struct LinkHoverModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .underline(self.isHovering, pattern: .solid)
            .onHover { hovering in
                self.isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
