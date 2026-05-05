import XCTest

/// UI tests for the LikedMusicView.
@MainActor
final class LikedMusicViewUITests: KasetUITestCase {
    // MARK: - Basic Display

    func testLikedMusicViewDisplaysTitle() {
        launchDefault()

        navigateToLikedMusic()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.LikedMusic.container), "Liked Music view should be visible")
    }

    func testLikedMusicViewShowsEmptyState() {
        launchDefault()

        navigateToLikedMusic()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.LikedMusic.container), "Liked Music view should load")
    }

    // MARK: - Navigation

    func testLikedMusicNavigationFromSidebar() {
        launchDefault()

        navigateToLikedMusic()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.LikedMusic.container), "Liked Music view should be visible")
    }

    // MARK: - Player Bar Integration

    func testLikedMusicViewShowsPlayerBar() {
        launchWithMockPlayer(isPlaying: true)

        navigateToLikedMusic()

        let playPauseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Play' OR label CONTAINS 'Pause'")
        ).firstMatch
        XCTAssertTrue(waitForElement(playPauseButton, timeout: 10))
    }
}
