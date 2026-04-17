import AppKit

// MARK: - PlayerPresentationWindowCoordinator

/// Applies same-window sizing for alternate player presentation modes.
@MainActor
final class PlayerPresentationWindowCoordinator {
    static let compactTargetSize = NSSize(width: 420, height: 640)
    static let compactMinimumSize = NSSize(width: 360, height: 540)

    private static let mainWindowAutosaveName = "YTMPrivateMainWindow"

    private weak var managedWindow: NSWindow?
    private var storedStandardFrame: NSRect?
    private var storedMinimumSize: NSSize?
    private var storedContentMinimumSize: NSSize?
    private var targetMode: PlayerPresentationMode = .standard
    private var transitionGeneration = 0

    func transition(from oldMode: PlayerPresentationMode, to newMode: PlayerPresentationMode) {
        guard oldMode != newMode else { return }

        self.targetMode = newMode
        self.transitionGeneration += 1

        if newMode == .compact {
            self.captureStandardWindowFrameIfNeeded()

            let generation = self.transitionGeneration
            Task { @MainActor in
                await Task.yield()

                guard self.targetMode == .compact, self.transitionGeneration == generation else { return }
                self.applyCompactWindowFrame()
            }
        } else if oldMode == .compact {
            self.restoreStandardWindowFrame()
        }
    }

    static func compactFrame(centeredAround sourceFrame: NSRect) -> NSRect {
        NSRect(
            x: sourceFrame.midX - Self.compactTargetSize.width / 2,
            y: sourceFrame.midY - Self.compactTargetSize.height / 2,
            width: Self.compactTargetSize.width,
            height: Self.compactTargetSize.height
        ).integral
    }

    private func captureStandardWindowFrameIfNeeded() {
        guard self.storedStandardFrame == nil, let window = self.mainWindow() else { return }

        self.managedWindow = window
        self.storedStandardFrame = window.frame
        self.storedMinimumSize = window.minSize
        self.storedContentMinimumSize = window.contentMinSize
    }

    private func applyCompactWindowFrame() {
        guard let window = self.managedWindow ?? self.mainWindow() else { return }

        if self.storedStandardFrame == nil {
            self.managedWindow = window
            self.storedStandardFrame = window.frame
            self.storedMinimumSize = window.minSize
            self.storedContentMinimumSize = window.contentMinSize
        }

        guard let storedStandardFrame else { return }

        self.managedWindow = window
        window.minSize = Self.compactMinimumSize
        window.contentMinSize = Self.compactMinimumSize
        window.setFrame(Self.compactFrame(centeredAround: storedStandardFrame), display: true, animate: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func restoreStandardWindowFrame() {
        guard let window = self.managedWindow ?? self.mainWindow() else {
            self.clearStoredWindowState()
            return
        }

        if let storedMinimumSize {
            window.minSize = storedMinimumSize
        }

        if let storedContentMinimumSize {
            window.contentMinSize = storedContentMinimumSize
        }

        if let storedStandardFrame {
            window.setFrame(storedStandardFrame, display: true, animate: true)
        }

        self.clearStoredWindowState()
    }

    private func clearStoredWindowState() {
        self.managedWindow = nil
        self.storedStandardFrame = nil
        self.storedMinimumSize = nil
        self.storedContentMinimumSize = nil
    }

    private func mainWindow() -> NSWindow? {
        if let managedWindow, managedWindow.canBecomeMain {
            return managedWindow
        }

        if let window = NSApplication.shared.windows.first(where: { $0.frameAutosaveName == Self.mainWindowAutosaveName }) {
            return window
        }

        if let keyWindow = NSApplication.shared.keyWindow, keyWindow.canBecomeMain {
            return keyWindow
        }

        return NSApplication.shared.windows.first(where: \.canBecomeMain)
    }
}
