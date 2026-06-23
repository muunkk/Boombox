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
///    promoted to a navigation swipe via `NSEvent.trackSwipeEvent`. While
///    the gesture is in flight a Safari-style chevron tracks the user's
///    finger as a visual confirmation.
@available(macOS 26.0, *)
struct NavigationSwipeGestures: ViewModifier {
    @Binding var path: NavigationPath

    @State private var swipeMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var mouseButtonMonitor: Any?
    @State private var forwardStack: [NavigationPath.CodableRepresentation] = []
    @State private var isRestoringForward = false

    /// Current gesture progress in `[-1, 1]`. Positive = back (swipe right),
    /// negative = forward (swipe left). Drives the on-screen indicator.
    @State private var gestureProgress: CGFloat = 0
    /// Suppresses overlapping `trackSwipeEvent` calls so a single physical
    /// gesture only triggers one navigation.
    @State private var isTrackingSwipe = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if self.gestureProgress > 0.02, !self.path.isEmpty {
                    SwipeNavIndicator(direction: .back, progress: self.gestureProgress)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .trailing) {
                if self.gestureProgress < -0.02, !self.forwardStack.isEmpty {
                    SwipeNavIndicator(direction: .forward, progress: -self.gestureProgress)
                        .padding(.trailing, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
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
                        self.flashIndicator(progress: 1.0)
                        self.goBack()
                    } else if dx < 0 {
                        self.flashIndicator(progress: -1.0)
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
        if self.mouseButtonMonitor == nil {
            // Mouse 4 (button 3) = back, Mouse 5 (button 4) = forward — the
            // standard mapping on multi-button mice. We consume the event so
            // it doesn't leak through to the page underneath.
            self.mouseButtonMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
                switch event.buttonNumber {
                case 3:
                    Task { @MainActor in
                        self.flashIndicator(progress: 1.0)
                        self.goBack()
                    }
                    return nil
                case 4:
                    Task { @MainActor in
                        self.flashIndicator(progress: -1.0)
                        self.goForward()
                    }
                    return nil
                default:
                    return event
                }
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
        if let monitor = self.mouseButtonMonitor {
            NSEvent.removeMonitor(monitor)
            self.mouseButtonMonitor = nil
        }
        self.gestureProgress = 0
        self.isTrackingSwipe = false
    }

    /// Minimum ratio of horizontal-to-vertical scroll delta required to treat a
    /// scroll as a navigation swipe rather than (carousel) content scrolling.
    private static let swipeHorizontalDominance: CGFloat = 2.0
    /// Minimum horizontal magnitude (points) before a scroll can become a swipe.
    private static let swipeMinHorizontalDelta: CGFloat = 1.5

    /// Whether a precise scroll is dominantly horizontal enough to promote to a
    /// back/forward navigation swipe. Pure logic, extracted for unit testing.
    static func isStronglyHorizontal(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        abs(deltaX) > self.swipeHorizontalDominance * abs(deltaY)
            && abs(deltaX) > self.swipeMinHorizontalDelta
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
              // Require clear horizontal dominance + magnitude before promoting
              // to a back/forward swipe. A looser deltaX > deltaY test also
              // captured the near-horizontal flicks used to scroll horizontal
              // carousels inside pushed detail views, hijacking them into
              // navigation. Deliberate two-finger swipes stay strongly
              // horizontal and still qualify.
              Self.isStronglyHorizontal(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
        else {
            return
        }

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
                Task { @MainActor in
                    // Suppress reverse-direction progress when the user has
                    // nothing to navigate to that side.
                    if (gestureAmount > 0 && !canBack) || (gestureAmount < 0 && !canForward) {
                        self.gestureProgress = 0
                    } else {
                        self.gestureProgress = gestureAmount
                    }

                    if isComplete {
                        self.isTrackingSwipe = false
                        let triggeredBack = gestureAmount >= 0.999
                        let triggeredForward = gestureAmount <= -0.999
                        if triggeredBack {
                            self.goBack()
                        } else if triggeredForward {
                            self.goForward()
                        }
                        // Smoothly fade the indicator out at the end.
                        withAnimation(.easeOut(duration: 0.18)) {
                            self.gestureProgress = 0
                        }
                    }
                }
            }
        )
    }

    /// One-shot indicator flash for `.swipe` events (no progressive callback).
    private func flashIndicator(progress: CGFloat) {
        self.gestureProgress = progress
        withAnimation(.easeOut(duration: 0.22)) {
            self.gestureProgress = 0
        }
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

// MARK: - SwipeNavIndicator

/// Small Safari-style pill that grows and brightens with swipe progress.
@available(macOS 26.0, *)
private struct SwipeNavIndicator: View {
    enum Direction {
        case back, forward

        var symbol: String {
            switch self {
            case .back: "chevron.left"
            case .forward: "chevron.right"
            }
        }
    }

    let direction: Direction
    /// Progress in `[0, 1]` representing swipe distance from rest.
    let progress: CGFloat

    var body: some View {
        let clamped = max(0, min(1, self.progress))
        let scale = 0.7 + 0.3 * clamped
        let opacity = 0.4 + 0.6 * clamped

        Image(systemName: self.direction.symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(.black.opacity(0.55))
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    }
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(.easeOut(duration: 0.08), value: self.progress)
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
