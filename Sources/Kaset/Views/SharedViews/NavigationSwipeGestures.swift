import AppKit
import SwiftUI

// MARK: - NavigationSwipeGestures

/// Adds trackpad swipe navigation to a view that owns a `NavigationPath`.
///
/// Right swipe pops the stack (back); left swipe restores the most recently
/// popped state. Two paths are covered:
///
/// 1. Explicit `.swipe` events — when System Settings → Trackpad has
///    "Swipe between pages" set to "Swipe with two fingers" (or three).
/// 2. Scroll-wheel-driven swipes — the macOS default ("Swipe with two or
///    three fingers"), where horizontal momentum on a scroll gesture is
///    promoted to a navigation swipe via `NSEvent.trackSwipeEvent`.
@available(macOS 26.0, *)
struct NavigationSwipeGestures: ViewModifier {
    @Binding var path: NavigationPath

    @State private var swipeMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var forwardStack: [NavigationPath.CodableRepresentation] = []
    @State private var isRestoringForward = false
    /// Suppresses overlapping `trackSwipeEvent` calls so a single physical
    /// gesture only triggers one navigation.
    @State private var isTrackingSwipe = false

    func body(content: Content) -> some View {
        content
            .onAppear { self.startMonitoring() }
            .onDisappear { self.stopMonitoring() }
            .onChange(of: self.path.count) { oldCount, newCount in
                if self.isRestoringForward {
                    self.isRestoringForward = false
                    return
                }
                // Any external push (taps, links) invalidates the redo stack
                // — same model browsers use.
                if newCount > oldCount {
                    self.forwardStack.removeAll()
                }
            }
    }

    private func startMonitoring() {
        if self.swipeMonitor == nil {
            self.swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { event in
                let dx = event.deltaX
                Task { @MainActor in
                    if dx > 0 {
                        self.goBack()
                    } else if dx < 0 {
                        self.goForward()
                    }
                }
                return event
            }
        }
        if self.scrollMonitor == nil {
            self.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                self.handleScrollWheel(event)
                return event
            }
        }
    }

    private func stopMonitoring() {
        if let monitor = self.swipeMonitor {
            NSEvent.removeMonitor(monitor)
            self.swipeMonitor = nil
        }
        if let monitor = self.scrollMonitor {
            NSEvent.removeMonitor(monitor)
            self.scrollMonitor = nil
        }
    }

    /// Promotes a horizontal scroll to a navigation swipe via AppKit's
    /// fluid swipe tracking API. Called from a local event monitor; we only
    /// hook the gesture when it `began` so we don't interfere with ongoing
    /// vertical scrolling or carousel scrolling already in flight.
    private func handleScrollWheel(_ event: NSEvent) {
        guard !self.isTrackingSwipe,
              event.phase == .began,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        else {
            return
        }

        // No-op gestures (delta near zero) shouldn't kick off tracking.
        guard abs(event.scrollingDeltaX) > 0.1 else { return }

        // Only intercept if we have somewhere to navigate; otherwise let the
        // event flow normally to scrollables underneath.
        let canBack = !self.path.isEmpty
        let canForward = !self.forwardStack.isEmpty
        guard canBack || canForward else { return }

        self.isTrackingSwipe = true
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: -1.0,
            max: 1.0,
            usingHandler: { gestureAmount, _, isComplete, _ in
                guard isComplete else { return }
                Task { @MainActor in
                    self.isTrackingSwipe = false
                    if gestureAmount >= 0.999 {
                        self.goBack()
                    } else if gestureAmount <= -0.999 {
                        self.goForward()
                    }
                }
            }
        )
    }

    private func goBack() {
        guard !self.path.isEmpty else { return }
        if let snapshot = self.path.codable {
            self.forwardStack.append(snapshot)
        }
        self.path.removeLast()
    }

    private func goForward() {
        guard let snapshot = self.forwardStack.popLast() else { return }
        self.isRestoringForward = true
        self.path = NavigationPath(snapshot)
    }
}

@available(macOS 26.0, *)
extension View {
    /// Attaches two-finger trackpad swipe navigation to the receiving view,
    /// driving the supplied `NavigationPath` for back/forward.
    func navigationSwipeGestures(path: Binding<NavigationPath>) -> some View {
        modifier(NavigationSwipeGestures(path: path))
    }
}
