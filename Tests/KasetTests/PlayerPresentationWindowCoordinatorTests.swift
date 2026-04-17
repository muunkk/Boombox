import AppKit
import Testing
@testable import Kaset

@Suite("Player presentation window coordinator tests")
@MainActor
struct PlayerPresentationWindowCoordinatorTests {
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
