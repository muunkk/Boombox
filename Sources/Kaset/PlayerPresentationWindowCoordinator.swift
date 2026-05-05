import AppKit

// MARK: - PlayerPresentationWindowCoordinator

/// Applies same-window sizing for alternate player presentation modes.
@MainActor
final class PlayerPresentationWindowCoordinator {
    struct WindowChromeState {
        let titleVisibility: NSWindow.TitleVisibility
        let titlebarAppearsTransparent: Bool
        let isMovableByWindowBackground: Bool
        let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
        let hasFullSizeContentView: Bool
    }

    static let compactTargetSize = NSSize(width: 420, height: 640)
    static let compactMinimumSize = NSSize(width: 360, height: 540)

    private static let mainWindowAutosaveName = "BoomboxMainWindow"

    private weak var managedWindow: NSWindow?
    private var storedStandardFrame: NSRect?
    private var storedMinimumSize: NSSize?
    private var storedContentMinimumSize: NSSize?
    private var storedChromeState: WindowChromeState?
    private var targetMode: PlayerPresentationMode = .standard
    private var transitionGeneration = 0

    func transition(from oldMode: PlayerPresentationMode, to newMode: PlayerPresentationMode) {
        guard oldMode != newMode else { return }

        self.targetMode = newMode
        self.transitionGeneration += 1

        if newMode != .standard {
            self.captureStandardChromeStateIfNeeded()
        }

        if newMode == .compact || (oldMode == .standard && newMode == .focus) {
            self.captureCurrentWindowFrameState()
        }

        let generation = self.transitionGeneration
        Task { @MainActor in
            await Task.yield()

            guard self.targetMode == newMode, self.transitionGeneration == generation else { return }
            self.applyTransition(from: oldMode, to: newMode)
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

    static func captureChromeState(from window: NSWindow) -> WindowChromeState {
        WindowChromeState(
            titleVisibility: window.titleVisibility,
            titlebarAppearsTransparent: window.titlebarAppearsTransparent,
            isMovableByWindowBackground: window.isMovableByWindowBackground,
            titlebarSeparatorStyle: window.titlebarSeparatorStyle,
            hasFullSizeContentView: window.styleMask.contains(.fullSizeContentView)
        )
    }

    static func applyPresentationChrome(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
    }

    static func restoreChromeState(_ state: WindowChromeState, to window: NSWindow) {
        window.titleVisibility = state.titleVisibility
        window.titlebarAppearsTransparent = state.titlebarAppearsTransparent
        window.isMovableByWindowBackground = state.isMovableByWindowBackground
        window.titlebarSeparatorStyle = state.titlebarSeparatorStyle

        if state.hasFullSizeContentView {
            window.styleMask.insert(.fullSizeContentView)
        } else {
            window.styleMask.remove(.fullSizeContentView)
        }
    }

    private func applyTransition(from oldMode: PlayerPresentationMode, to newMode: PlayerPresentationMode) {
        guard let window = self.managedWindow ?? self.mainWindow() else { return }

        self.managedWindow = window

        if newMode != .standard {
            Self.applyPresentationChrome(to: window)
        }

        if oldMode == .compact, newMode != .compact {
            self.restoreStoredWindowFrame(on: window)
        }

        if newMode == .compact {
            self.applyCompactWindowFrame(on: window)
        }

        if newMode == .standard {
            self.restoreStoredChrome(on: window)
            self.clearStoredFrameState()
            self.clearStoredChromeState()
        }

        window.makeKeyAndOrderFront(nil)
    }

    private func captureCurrentWindowFrameState() {
        guard let window = self.mainWindow() else { return }

        self.managedWindow = window
        self.storedStandardFrame = window.frame
        self.storedMinimumSize = window.minSize
        self.storedContentMinimumSize = window.contentMinSize
    }

    private func captureStandardChromeStateIfNeeded() {
        guard self.storedChromeState == nil, let window = self.mainWindow() else { return }

        self.managedWindow = window
        self.storedChromeState = Self.captureChromeState(from: window)
    }

    private func applyCompactWindowFrame(on window: NSWindow) {
        guard let storedStandardFrame else { return }

        window.minSize = Self.compactMinimumSize
        window.contentMinSize = Self.compactMinimumSize
        window.setFrame(Self.compactFrame(centeredAround: storedStandardFrame), display: true, animate: true)
    }

    private func restoreStoredWindowFrame(on window: NSWindow) {
        if let storedMinimumSize {
            window.minSize = storedMinimumSize
        }

        if let storedContentMinimumSize {
            window.contentMinSize = storedContentMinimumSize
        }

        if let storedStandardFrame {
            window.setFrame(storedStandardFrame, display: true, animate: true)
        }
    }

    private func clearStoredFrameState() {
        self.storedStandardFrame = nil
        self.storedMinimumSize = nil
        self.storedContentMinimumSize = nil
    }

    private func restoreStoredChrome(on window: NSWindow) {
        guard let storedChromeState else { return }
        Self.restoreChromeState(storedChromeState, to: window)
    }

    private func clearStoredChromeState() {
        self.storedChromeState = nil
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
