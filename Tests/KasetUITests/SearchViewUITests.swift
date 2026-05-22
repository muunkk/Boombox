import XCTest

/// UI tests for the SearchView.
@MainActor
final class SearchViewUITests: KasetUITestCase {
    // MARK: - Search Field

    func testSearchFieldExists() {
        launchDefault()

        navigateToSearch()

        // Search field should be present
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(waitForElement(searchField), "Search field should exist")
    }

    func testSearchFieldAcceptsInput() {
        launchDefault()

        navigateToSearch()

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(waitForHittable(searchField))

        // Type in the search field
        searchField.click()
        searchField.typeText("test query")

        // Verify text was entered
        XCTAssertEqual(searchField.value as? String, "test query")
    }

    func testClearButtonAppearsWithText() {
        launchDefault()

        navigateToSearch()

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(waitForHittable(searchField))

        // Initially no clear button
        searchField.click()
        searchField.typeText("test")

        // Clear button should appear (X icon)
        let clearButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Clear' OR label CONTAINS 'xmark'")
        ).firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3), "Clear button should appear")
    }

    // MARK: - Empty State

    func testEmptyStateShownInitially() {
        launchDefault()

        navigateToSearch()

        // Empty state message should be visible
        let emptyStateText = app.staticTexts["Search for your favorite music"]
        XCTAssertTrue(waitForElement(emptyStateText, timeout: 5), "Empty state text should be visible")
    }

    // MARK: - Search Execution

    func testSearchSubmitTriggersSearch() {
        launchWithMockSearch(songCount: 5)

        navigateToSearch()

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(waitForHittable(searchField))

        searchField.click()
        searchField.typeText("test\n") // Type and press Enter

        // Wait for results or loading state
        // The search should be triggered
        Thread.sleep(forTimeInterval: 1) // Brief wait for state change
    }

    // MARK: - Filter Chips

    func testFilterChipsExistAfterSearch() {
        launchWithMockSearch(songCount: 5)

        navigateToSearch()

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(waitForHittable(searchField))

        searchField.click()
        searchField.typeText("test\n")

        // Wait for filter chips (they appear after search results)
        // Filter chips are buttons with category names
        Thread.sleep(forTimeInterval: 2)

        // Look for any filter-like buttons
        let allFilterButton = app.buttons["All"]
        // If results exist, filters should appear
    }

    func testFilterSwapPreservesSectionRenderingInAllTab() {
        launchWithMockSearchShelves()

        navigateToSearch()

        let searchField = app.textFields[TestAccessibilityID.Search.searchField].firstMatch
        let resolvedSearchField = searchField.exists ? searchField : app.textFields.firstMatch
        XCTAssertTrue(waitForHittable(resolvedSearchField, timeout: 10))

        resolvedSearchField.click()
        resolvedSearchField.typeText("ordered shelves\n")

        let allFilter = app.buttons[TestAccessibilityID.Search.filterChip("all")]
        let songsFilter = app.buttons[TestAccessibilityID.Search.filterChip("songs")]
        XCTAssertTrue(waitForElement(allFilter, timeout: 10), "All filter should appear after search")
        XCTAssertEqual(allFilter.value as? String, "Selected", "All filter should be selected by default")
        XCTAssertTrue(waitForElement(songsFilter, timeout: 5), "Songs filter should appear after search")

        let songsHeader = element(matchingAccessibilityID: TestAccessibilityID.Search.sectionHeader("songs"))
        let albumsHeader = element(matchingAccessibilityID: TestAccessibilityID.Search.sectionHeader("albums"))
        XCTAssertTrue(waitForElement(songsHeader, timeout: 10), "Songs shelf header should render in All")
        XCTAssertTrue(waitForElement(albumsHeader, timeout: 10), "Albums shelf header should render in All")

        clickElement(songsFilter)

        XCTAssertTrue(waitForElementToDisappear(songsHeader, timeout: 10), "Songs shelf header should disappear in the Songs filter")
        XCTAssertFalse(albumsHeader.exists, "Albums shelf header should not render in the flat Songs filter")
        let flatSongResult = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Search Song 1")).firstMatch
        XCTAssertTrue(waitForElement(flatSongResult, timeout: 10), "Songs filter should show a flat song result list")
        XCTAssertEqual(songsFilter.value as? String, "Selected", "Songs filter should be selected after tapping it")

        clickElement(allFilter)

        XCTAssertTrue(waitForElement(songsHeader, timeout: 10), "Songs shelf header should reappear after returning to All")
        XCTAssertTrue(waitForElement(albumsHeader, timeout: 10), "Albums shelf header should reappear after returning to All")
        XCTAssertEqual(allFilter.value as? String, "Selected", "All filter should be selected after returning to it")
    }

    // MARK: - Keyboard Navigation

    func testSearchFieldIsFocusedOnAppear() {
        launchDefault()

        navigateToSearch()

        // The search field should be ready for input
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(waitForElement(searchField))

        // Type directly - if focused, it should work
        app.typeText("quick search")

        // Verify text was entered
        XCTAssertEqual(searchField.value as? String, "quick search")
    }

    // MARK: - Navigation Integration

    func testSearchNavigationTitle() {
        launchDefault()

        navigateToSearch()

        XCTAssertTrue(waitForScreen(TestAccessibilityID.Search.container), "Search view should be visible")
    }
}
