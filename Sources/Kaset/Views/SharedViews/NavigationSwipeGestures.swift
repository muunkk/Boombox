import AppKit
import SwiftUI

// MARK: - NavigationSwipeGestures

/// Adds two-finger / three-finger trackpad swipe navigation to a view that
/// owns a `NavigationPath`. Right swipe pops the stack (back), left swipe
/// restores the most recently popped state if its destinations were Codable.
@available(macOS 26.0, *)
struct NavigationSwipeGestures: ViewModifier {
    @Binding var path: NavigationPath

    @State private var monitor: Any?
    @State private var forwardStack: [NavigationPath.CodableRepresentation] = []
    @State private var isRestoringForward = false

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
        guard self.monitor == nil else { return }
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { event in
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

    private func stopMonitoring() {
        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
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

@available(macOS 26.0, *)
extension View {
    /// Attaches two-finger trackpad swipe navigation to the receiving view,
    /// driving the supplied `NavigationPath` for back/forward.
    func navigationSwipeGestures(path: Binding<NavigationPath>) -> some View {
        modifier(NavigationSwipeGestures(path: path))
    }
}
