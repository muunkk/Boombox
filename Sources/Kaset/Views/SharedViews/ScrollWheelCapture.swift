import AppKit
import SwiftUI

// MARK: - ScrollWheelCapture

/// Transparent overlay that forwards `scrollWheel` events from AppKit to a
/// SwiftUI closure. Use as a `.background { ScrollWheelCapture { ... } }` to
/// add scroll-wheel adjustment to controls that SwiftUI does not otherwise
/// react to (volume sliders, scrubbers, etc.).
struct ScrollWheelCapture: NSViewRepresentable {
    /// Called with the event's `scrollingDeltaY`. Positive = scroll up.
    let onScroll: (CGFloat) -> Void

    func makeNSView(context _: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = self.onScroll
        return view
    }

    func updateNSView(_ view: ScrollWheelView, context _: Context) {
        view.onScroll = self.onScroll
    }
}

// MARK: - ScrollWheelView

final class ScrollWheelView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override var isFlipped: Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        // Prefer precise (trackpad / Magic Mouse) deltas when available;
        // fall back to legacy deltaY for classic mice.
        let delta: CGFloat = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        if delta != 0 {
            self.onScroll?(delta)
        }
    }
}
