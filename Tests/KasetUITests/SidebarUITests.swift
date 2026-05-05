import XCTest

/// UI tests for sidebar navigation.
@MainActor
final class SidebarUITests: KasetUITestCase {
    // MARK: - Navigation Items Visible

    func testSidebarShowsAllNavigationItems() {
        launchDefault()

        // Verify all sidebar items are present via accessibility identifiers
        let searchItem = app.buttons[TestAccessibilityID.Sidebar.searchItem]
        let homeItem = app.buttons[TestAccessibilityID.Sidebar.homeItem]
        let exploreItem = app.buttons[TestAccessibilityID.Sidebar.exploreItem]
        let likedMusicItem = app.buttons[TestAccessibilityID.Sidebar.likedMusicItem]
        let playlistsItem = app.buttons[TestAccessibilityID.Sidebar.libraryItem]

        XCTAssertTrue(searchItem.waitForExistence(timeout: 10), "Search item should exist")
        XCTAssertTrue(homeItem.exists, "Home item should exist")
        XCTAssertTrue(exploreItem.exists, "Explore item should exist")
        XCTAssertTrue(likedMusicItem.exists, "Liked Music item should exist")
        XCTAssertTrue(playlistsItem.exists, "Playlists item should exist")
    }

    // MARK: - Navigation Selection

    func testNavigateToHome() {
        launchDefault()

        navigateToHome()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Home.container), "Home view should be visible")
    }

    func testNavigateToSearch() {
        launchDefault()

        navigateToSearch()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Search.container), "Search view should be visible")

        // Search field should be present
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.exists, "Search field should exist")
    }

    func testNavigateToExplore() {
        launchDefault()

        navigateToExplore()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Explore.container), "Explore view should be visible")
    }

    func testNavigateToLikedMusic() {
        launchDefault()

        navigateToLikedMusic()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.LikedMusic.container), "Liked Music view should be visible")
    }

    func testNavigateToLibrary() {
        launchDefault()

        navigateToLibrary()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Library.container), "Library view should be visible")
    }

    // MARK: - Navigation Persistence

    func testNavigationPersistsAfterSwitching() {
        launchDefault()

        // Navigate to Search
        navigateToSearch()
        XCTAssertTrue(waitForScreen(TestAccessibilityID.Search.container))

        // Navigate to Explore
        navigateToExplore()
        XCTAssertTrue(waitForScreen(TestAccessibilityID.Explore.container))

        // Navigate back to Home
        navigateToHome()
        XCTAssertTrue(waitForScreen(TestAccessibilityID.Home.container))
    }
}
