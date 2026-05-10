import AppKit
import SwiftUI

// MARK: - SidePanelSwipeSwitchModifier

/// Detects horizontal swipes on the lyrics/queue side panel and toggles
/// between the two. Right swipe → show queue. Left swipe → show lyrics.
/// Both `.swipe` events and scroll-wheel-based horizontal swipes are
/// handled, mirroring the navigation swipe gesture.
@available(macOS 26.0, *)
struct SidePanelSwipeSwitchModifier: ViewModifier {
    let playerService: PlayerService

    @State private var swipeMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var isTrackingSwipe = false
    @State private var hostFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                // Capture the panel's frame in screen coordinates so the
                // monitors can ignore events outside the panel.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { self.hostFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, new in
                            self.hostFrame = new
                        }
                }
            }
            .onAppear { self.startMonitoring() }
            .onDisappear { self.stopMonitoring() }
    }

    private func startMonitoring() {
        if self.swipeMonitor == nil {
            self.swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { event in
                guard self.eventIsInsidePanel(event) else { return event }
                let dx = event.deltaX
                Task { @MainActor in
                    if dx > 0 {
                        self.switchTo(lyrics: true)
                    } else if dx < 0 {
                        self.switchTo(lyrics: false)
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
        self.isTrackingSwipe = false
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard !self.isTrackingSwipe,
              event.phase == .began,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              abs(event.scrollingDeltaX) > 0.1
        else { return }
        guard self.eventIsInsidePanel(event) else { return }

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
                        self.switchTo(lyrics: true)
                    } else if gestureAmount <= -0.999 {
                        self.switchTo(lyrics: false)
                    }
                }
            }
        )
    }

    private func switchTo(lyrics: Bool) {
        guard self.playerService.showLyrics || self.playerService.showQueue else { return }
        if lyrics {
            // Right swipe — bring lyrics if not already showing.
            guard !self.playerService.showLyrics else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.playerService.showLyrics = true
                self.playerService.showQueue = false
            }
        } else {
            // Left swipe — bring queue if not already showing.
            guard !self.playerService.showQueue else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.playerService.showQueue = true
                self.playerService.showLyrics = false
            }
        }
        HapticService.toggle()
    }

    private func eventIsInsidePanel(_ event: NSEvent) -> Bool {
        guard self.hostFrame.width > 0 else { return false }
        guard let window = event.window else { return false }
        // SwiftUI `.global` uses top-left origin while NSEvent reports
        // window-local coordinates with a bottom-left origin. Flip Y to
        // compare apples-to-apples.
        let windowHeight = window.frame.height
        let flippedY = windowHeight - event.locationInWindow.y
        let panelLeft = self.hostFrame.minX
        let panelRight = self.hostFrame.maxX
        let panelTop = self.hostFrame.minY
        let panelBottom = self.hostFrame.maxY
        let x = event.locationInWindow.x
        return x >= panelLeft && x <= panelRight && flippedY >= panelTop && flippedY <= panelBottom
    }
}
