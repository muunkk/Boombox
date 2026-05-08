import AppKit
import SwiftUI

// MARK: - PointingHandCursor

/// Switches to the system pointing-hand cursor while the receiving view is
/// hovered. Use to signal that something is clickable (matches the typical
/// "link" hover affordance on the web).
extension View {
    func pointingHandCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
