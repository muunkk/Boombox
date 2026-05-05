import AppKit
import Testing
@testable import Kaset

@Suite("Player presentation window coordinator tests")
@MainActor
struct PlayerPresentationWindowCoordinatorTests {
    @Test("Presentation chrome applies and restores cleanly")
    func presentationChromeRoundTrip() {
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.titlebarSeparatorStyle = .automatic
        window.styleMask.remove(.fullSizeContentView)

        let originalState = PlayerPresentationWindowCoordinator.captureChromeState(from: window)

        PlayerPresentationWindowCoordinator.applyPresentationChrome(to: window)

        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.isMovableByWindowBackground)
        #expect(window.titlebarSeparatorStyle == .none)
        #expect(window.styleMask.contains(.fullSizeContentView))

        PlayerPresentationWindowCoordinator.restoreChromeState(originalState, to: window)

        #expect(window.titleVisibility == .visible)
        #expect(window.titlebarAppearsTransparent == false)
        #expect(window.isMovableByWindowBackground == false)
        #expect(window.titlebarSeparatorStyle == .automatic)
        #expect(window.styleMask.contains(.fullSizeContentView) == false)
    }

    @Test("Compact frame uses the target size")
    func compactFrameUsesTargetSize() {
        let sourceFrame = NSRect(x: 120, y: 240, width: 960, height: 720)

        let compactFrame = PlayerPresentationWindowCoordinator.compactFrame(centeredAround: sourceFrame)

        #expect(compactFrame.size == PlayerPresentationWindowCoordinator.compactTargetSize)
    }

    @Test("Compact frame is centered around the source frame")
    func compactFrameIsCenteredAroundSourceFrame() {
        let sourceFrame = NSRect(x: 80, y: 120, width: 1180, height: 760)

        let compactFrame = PlayerPresentationWindowCoordinator.compactFrame(centeredAround: sourceFrame)

        #expect(compactFrame.midX == sourceFrame.midX)
        #expect(compactFrame.midY == sourceFrame.midY)
    }

    @Test("Compact minimum size matches Small Player requirements")
    func compactMinimumSizeMatchesRequirements() {
        #expect(PlayerPresentationWindowCoordinator.compactMinimumSize == NSSize(width: 360, height: 540))
    }
}
