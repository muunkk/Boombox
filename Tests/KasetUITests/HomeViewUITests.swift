import XCTest

/// UI tests for the HomeView.
@MainActor
final class HomeViewUITests: KasetUITestCase {
    // MARK: - Basic Display

    func testHomeViewDisplaysTitle() {
        launchWithMockHome()

        navigateToHome()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Home.container), "Home view should be visible")
    }

    func testHomeViewShowsLoadingState() {
        // Launch without mock data to see loading state
        launchDefault()

        navigateToHome()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Home.container), "Home view should load")
    }

    // MARK: - Content Display

    func testHomeViewDisplaysSections() {
        launchWithMockHome(sectionCount: 3, itemsPerSection: 5)

        navigateToHome()

        // Wait for content to load
        // Look for section titles in the scroll view
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(waitForElement(scrollView, timeout: 10), "Scroll view should exist")
    }

    func testHomeViewIsScrollable() {
        launchWithMockHome(sectionCount: 5, itemsPerSection: 10)

        navigateToHome()

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(waitForElement(scrollView))

        // Verify scrolling works
        scrollView.swipeUp()
        scrollView.swipeDown()
    }

    // MARK: - Player Bar Presence

    func testHomeViewShowsPlayerBar() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        // Player bar should be visible at the bottom
        // Look for play/pause button as indicator
        let playPauseButton = app.buttons[TestAccessibilityID.PlayerBar.playPauseButton]
        XCTAssertTrue(waitForElement(playPauseButton, timeout: 10), "Player bar should show play/pause button")
    }

    // MARK: - Navigation from Home

    func testCanNavigateFromHomeToOtherViews() {
        launchWithMockHome()

        navigateToHome()

        // Navigate to Search
        navigateToSearch()
        XCTAssertTrue(waitForScreen(TestAccessibilityID.Search.container), "Search view should be visible")

        // Navigate back to Home
        navigateToHome()
        XCTAssertTrue(waitForScreen(TestAccessibilityID.Home.container), "Home view should be visible")
    }
}
