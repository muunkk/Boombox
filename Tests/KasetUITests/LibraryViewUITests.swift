import XCTest

/// UI tests for the LibraryView.
@MainActor
final class LibraryViewUITests: KasetUITestCase {
    // MARK: - Basic Display

    func testLibraryViewDisplaysTitle() {
        launchDefault()

        navigateToLibrary()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Library.container), "Library view should be visible")
    }

    func testLibraryViewShowsLoadingState() {
        launchDefault()

        navigateToLibrary()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Library.container), "Library view should load")
    }

    // MARK: - Playlist Display

    func testLibraryViewWithMockPlaylists() {
        launchWithMockLibrary(playlistCount: 5)

        navigateToLibrary()

        // The view should show playlists
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(waitForElement(scrollView, timeout: 10))
    }

    func testLibraryViewIsScrollable() {
        launchWithMockLibrary(playlistCount: 20)

        navigateToLibrary()

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(waitForElement(scrollView))

        scrollView.swipeUp()
        scrollView.swipeDown()
    }

    // MARK: - Navigation Integration

    func testLibraryNavigationFromSidebar() {
        launchDefault()

        // Navigate to Library via sidebar using accessibility identifier
        navigateToLibrary()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Library.container), "Library view should be visible")
    }

    // MARK: - Player Bar Integration

    func testLibraryViewShowsPlayerBar() {
        launchWithMockPlayer(isPlaying: true)

        navigateToLibrary()

        let playPauseButton = app.buttons[TestAccessibilityID.PlayerBar.playPauseButton]
        XCTAssertTrue(waitForElement(playPauseButton, timeout: 10))
    }
}
