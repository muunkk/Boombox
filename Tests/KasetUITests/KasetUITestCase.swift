@preconcurrency import XCTest

// MARK: - TestAccessibilityID

/// Accessibility identifiers matching those in AccessibilityID enum.
/// Duplicated here to avoid import issues with the app target.
enum TestAccessibilityID {
    enum Sidebar {
        static let container = "sidebar"
        static let searchItem = "sidebar.search"
        static let homeItem = "sidebar.home"
        static let exploreItem = "sidebar.explore"
        static let likedMusicItem = "sidebar.likedMusic"
        static let libraryItem = "sidebar.library"
        static let nowPlayingPanel = "sidebar.nowPlayingPanel"
        static let nowPlayingArtwork = "sidebar.nowPlayingArtwork"
        static let nowPlayingFocusButton = "sidebar.nowPlayingFocusButton"
        static let nowPlayingHideButton = "sidebar.nowPlayingHideButton"
    }

    enum PlayerBar {
        static let playPauseButton = "playerBar.playPause"
        static let previousButton = "playerBar.previous"
        static let nextButton = "playerBar.next"
        static let shuffleButton = "playerBar.shuffle"
        static let repeatButton = "playerBar.repeat"
        static let likeButton = "playerBar.like"
        static let lyricsButton = "playerBar.lyrics"
        static let nowPlayingPanelToggle = "playerBar.nowPlayingPanelToggle"
        static let seekSlider = "playerBar.seekSlider"
        static let trackTitle = "playerBar.trackTitle"
    }

    enum Home {
        static let container = "homeView"
    }

    enum Explore {
        static let container = "exploreView"
    }

    enum Search {
        static let container = "searchView"
    }

    enum Library {
        static let container = "libraryView"
    }

    enum LikedMusic {
        static let container = "likedMusicView"
    }

    enum MainWindow {
        static let container = "mainWindow"
        static let commandBar = "mainWindow.commandBar"
        static let commandBarOverlay = "mainWindow.commandBarOverlay"
        static let commandBarInput = "mainWindow.commandBarInput"
    }

    // MARK: - Sidebar Profile

    enum SidebarProfile {
        static let container = "sidebarProfile"
        static let profileButton = "sidebarProfile.profileButton"
        static let loadingState = "sidebarProfile.loading"
        static let loggedOutState = "sidebarProfile.loggedOut"
    }

    // MARK: - Account Switcher

    enum AccountSwitcher {
        static let container = "accountSwitcher"
        static let header = "accountSwitcher.header"
        static let accountsList = "accountSwitcher.accountsList"

        static func accountRow(index: Int) -> String {
            "accountSwitcher.account.\(index)"
        }
    }
}

// MARK: - MockFavoriteItem

/// Helper type for creating mock favorites in UI tests.
struct MockFavoriteItem {
    let id: String
    let pinnedAt: Date
    let type: MockFavoriteType

    enum MockFavoriteType {
        case song(videoId: String, title: String, artist: String)
        case album(id: String, title: String, artist: String)
        case playlist(id: String, title: String, author: String)
        case artist(id: String, name: String)
    }

    init(id: String = UUID().uuidString, pinnedAt: Date = Date(), type: MockFavoriteType) {
        self.id = id
        self.pinnedAt = pinnedAt
        self.type = type
    }

    /// Creates a mock song favorite.
    static func song(videoId: String, title: String, artist: String) -> MockFavoriteItem {
        MockFavoriteItem(type: .song(videoId: videoId, title: title, artist: artist))
    }

    /// Creates a mock album favorite.
    static func album(id: String, title: String, artist: String) -> MockFavoriteItem {
        MockFavoriteItem(type: .album(id: id, title: title, artist: artist))
    }

    /// Creates a mock playlist favorite.
    static func playlist(id: String, title: String, author: String) -> MockFavoriteItem {
        MockFavoriteItem(type: .playlist(id: id, title: title, author: author))
    }

    /// Creates a mock artist favorite.
    static func artist(id: String, name: String) -> MockFavoriteItem {
        MockFavoriteItem(type: .artist(id: id, name: name))
    }
}

// MARK: - KasetUITestCase

/// Base class for Kaset UI tests.
/// Provides common setup, launch configuration, and helper methods.
@MainActor
class KasetUITestCase: XCTestCase {
    /// The application under test.
    var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Stop immediately when a failure occurs
        continueAfterFailure = false

        // Create new app instance pointing to installed Boombox.app
        let appURL = URL(fileURLWithPath: "/Applications/Boombox.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            self.app = XCUIApplication(url: appURL)
        } else {
            self.app = XCUIApplication(bundleIdentifier: "com.melboonchan.boombox")
        }

        // Add UI test mode arguments
        self.app.launchArguments.append("-UITestMode")
        self.app.launchArguments.append("-SkipAuth")

        // Also set via environment (more reliable with XCUIApplication(url:))
        self.app.launchEnvironment["UI_TEST_MODE"] = "1"
        self.app.launchEnvironment["SKIP_AUTH"] = "1"

        // Disable animations for faster, more reliable tests
        self.app.launchArguments.append("-UIAnimationsDisabled")
    }

    override func tearDownWithError() throws {
        self.app = nil
        try super.tearDownWithError()
    }

    // MARK: - Launch Helpers

    /// Launches the app with mock home sections.
    func launchWithMockHome(sectionCount: Int = 3, itemsPerSection: Int = 5) {
        let sections = (0 ..< sectionCount).map { sectionIndex in
            [
                "id": "section-\(sectionIndex)",
                "title": "Test Section \(sectionIndex)",
                "items": (0 ..< itemsPerSection).map { itemIndex in
                    [
                        "type": "song",
                        "id": "song-\(sectionIndex)-\(itemIndex)",
                        "title": "Song \(itemIndex)",
                        "artist": "Artist \(itemIndex)",
                        "videoId": "video-\(sectionIndex)-\(itemIndex)",
                    ]
                },
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: sections),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.app.launchEnvironment["MOCK_HOME_SECTIONS"] = jsonString
        }

        self.app.launch()
    }

    /// Launches the app with mock search results.
    func launchWithMockSearch(songCount: Int = 5) {
        let songs = (0 ..< songCount).map { index in
            [
                "id": "search-song-\(index)",
                "title": "Search Result \(index)",
                "artist": "Search Artist \(index)",
                "videoId": "search-video-\(index)",
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: ["songs": songs]),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.app.launchEnvironment["MOCK_SEARCH_RESULTS"] = jsonString
        }

        self.app.launch()
    }

    /// Launches the app with mock library playlists.
    func launchWithMockLibrary(playlistCount: Int = 3) {
        let playlists = (0 ..< playlistCount).map { index in
            [
                "id": "playlist-\(index)",
                "title": "Playlist \(index)",
                "trackCount": 10 + index,
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: playlists),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.app.launchEnvironment["MOCK_PLAYLISTS"] = jsonString
        }

        self.app.launch()
    }

    /// Launches the app with a mock current track (player has something playing).
    func launchWithMockPlayer(isPlaying: Bool = true) {
        let track: [String: Any] = [
            "id": "current-track",
            "title": "Now Playing Song",
            "artist": "Current Artist",
            "videoId": "current-video",
            "duration": 180,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: track),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.app.launchEnvironment["MOCK_CURRENT_TRACK"] = jsonString
        }
        self.app.launchEnvironment["MOCK_IS_PLAYING"] = isPlaying ? "true" : "false"

        self.app.launch()
    }

    /// Launches the app with mock favorites.
    /// - Parameter items: Array of favorite item configurations.
    func launchWithMockFavorites(_ items: [MockFavoriteItem]) {
        let favorites = items.map { item -> [String: Any] in
            var dict: [String: Any] = [
                "id": item.id,
                "pinnedAt": ISO8601DateFormatter().string(from: item.pinnedAt),
            ]

            // Encode the itemType based on type
            switch item.type {
            case let .song(videoId, title, artist):
                dict["itemType"] = [
                    "song": [
                        "_0": [
                            "id": videoId,
                            "title": title,
                            "artists": [["id": "artist-\(videoId)", "name": artist]],
                            "videoId": videoId,
                        ],
                    ],
                ]
            case let .album(albumId, title, artist):
                dict["itemType"] = [
                    "album": [
                        "_0": [
                            "id": albumId,
                            "title": title,
                            "artists": [["id": "artist-\(albumId)", "name": artist]],
                        ],
                    ],
                ]
            case let .playlist(playlistId, title, author):
                dict["itemType"] = [
                    "playlist": [
                        "_0": [
                            "id": playlistId,
                            "title": title,
                            "author": author,
                        ],
                    ],
                ]
            case let .artist(artistId, name):
                dict["itemType"] = [
                    "artist": [
                        "_0": [
                            "id": artistId,
                            "name": name,
                        ],
                    ],
                ]
            }

            return dict
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: favorites),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.app.launchEnvironment["MOCK_FAVORITES"] = jsonString
        }

        self.app.launch()
    }

    /// Launches the app with mock player state and mock favorites.
    func launchWithMockPlayerAndFavorites(
        isPlaying: Bool = true,
        favorites: [MockFavoriteItem] = []
    ) {
        let track: [String: Any] = [
            "id": "current-track",
            "title": "Now Playing Song",
            "artist": "Current Artist",
            "videoId": "current-video",
            "duration": 180,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: track),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.app.launchEnvironment["MOCK_CURRENT_TRACK"] = jsonString
        }
        self.app.launchEnvironment["MOCK_IS_PLAYING"] = isPlaying ? "true" : "false"

        // Add mock favorites
        let favoritesArray = favorites.map { item -> [String: Any] in
            var dict: [String: Any] = [
                "id": item.id,
                "pinnedAt": ISO8601DateFormatter().string(from: item.pinnedAt),
            ]

            switch item.type {
            case let .song(videoId, title, artist):
                dict["itemType"] = [
                    "song": [
                        "_0": [
                            "id": videoId,
                            "title": title,
                            "artists": [["id": "artist-\(videoId)", "name": artist]],
                            "videoId": videoId,
                        ],
                    ],
                ]
            case let .album(albumId, title, artist):
                dict["itemType"] = [
                    "album": [
                        "_0": [
                            "id": albumId,
                            "title": title,
                            "artists": [["id": "artist-\(albumId)", "name": artist]],
                        ],
                    ],
                ]
            case let .playlist(playlistId, title, author):
                dict["itemType"] = [
                    "playlist": [
                        "_0": [
                            "id": playlistId,
                            "title": title,
                            "author": author,
                        ],
                    ],
                ]
            case let .artist(artistId, name):
                dict["itemType"] = [
                    "artist": [
                        "_0": [
                            "id": artistId,
                            "name": name,
                        ],
                    ],
                ]
            }

            return dict
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: favoritesArray),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.app.launchEnvironment["MOCK_FAVORITES"] = jsonString
        }

        self.app.launch()
    }

    /// Launches the app with default configuration (logged in, no specific mock data).
    func launchDefault() {
        self.app.launch()
    }

    // MARK: - Wait Helpers

    /// Finds an element by accessibility identifier without assuming its accessibility element type.
    func element(matchingAccessibilityID accessibilityID: String) -> XCUIElement {
        self.app.descendants(matching: .any)[accessibilityID].firstMatch
    }

    /// Waits for a screen root to exist by stable accessibility identifier.
    @discardableResult
    func waitForScreen(
        _ accessibilityID: String,
        timeout: TimeInterval = 10,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        self.waitForElement(
            self.element(matchingAccessibilityID: accessibilityID),
            timeout: timeout,
            file: file,
            line: line
        )
    }

    /// Waits for an element to exist with a timeout.
    @discardableResult
    func waitForElement(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail("Timed out waiting for element: \(element)", file: file, line: line)
            return false
        }
        return true
    }

    /// Waits for an element to be hittable (visible and interactable).
    @discardableResult
    func waitForHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail("Timed out waiting for element to be hittable: \(element)", file: file, line: line)
            return false
        }
        return true
    }

    /// Clicks an element that exists, falling back to a centered coordinate click when
    /// macOS accessibility reports a visible SwiftUI control as not hittable in CI.
    @discardableResult
    func clickElement(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        guard self.waitForElement(element, timeout: timeout, file: file, line: line) else {
            return false
        }

        if element.isHittable {
            element.click()
            return true
        }

        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else {
            XCTFail("Element exists but has no clickable frame: \(element)", file: file, line: line)
            return false
        }

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        return true
    }

    /// Waits for element count to match expected value.
    @discardableResult
    func waitForElementCount(
        _ query: XCUIElementQuery,
        count: Int,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "count == \(count)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail(
                "Timed out waiting for element count. Expected: \(count), Actual: \(query.count)",
                file: file,
                line: line
            )
            return false
        }
        return true
    }

    /// Waits for an element to disappear with a timeout.
    @discardableResult
    func waitForElementToDisappear(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail("Timed out waiting for element to disappear: \(element)", file: file, line: line)
            return false
        }
        return true
    }

    // MARK: - Navigation Helpers

    /// Navigates to a sidebar item by accessibility identifier.
    func navigateToSidebarItem(_ accessibilityID: String) {
        // Find by accessibility identifier first, fall back to label
        var sidebarItem = self.app.buttons[accessibilityID].firstMatch
        if !sidebarItem.exists {
            // Try other element types
            sidebarItem = self.app.cells[accessibilityID].firstMatch
        }

        // First wait for element to exist
        let existsPredicate = NSPredicate(format: "exists == true")
        let existsExpectation = XCTNSPredicateExpectation(predicate: existsPredicate, object: sidebarItem)
        let existsResult = XCTWaiter().wait(for: [existsExpectation], timeout: 15)

        guard existsResult == .completed else {
            XCTFail("Sidebar item '\(accessibilityID)' never appeared")
            return
        }

        self.clickElement(sidebarItem, timeout: 10)
    }

    /// Navigates to a sidebar item by label text.
    func navigateToSidebarItemByLabel(_ label: String) {
        // Wait for sidebar to be ready with extended timeout for UI test startup
        let sidebarItem = self.app.staticTexts[label].firstMatch

        // First wait for element to exist
        let existsPredicate = NSPredicate(format: "exists == true")
        let existsExpectation = XCTNSPredicateExpectation(predicate: existsPredicate, object: sidebarItem)
        let existsResult = XCTWaiter().wait(for: [existsExpectation], timeout: 15)

        guard existsResult == .completed else {
            XCTFail("Sidebar item '\(label)' never appeared")
            return
        }

        self.clickElement(sidebarItem, timeout: 10)
    }

    /// Navigates to Home via sidebar.
    func navigateToHome() {
        self.navigateToSidebarItem(TestAccessibilityID.Sidebar.homeItem)
    }

    /// Navigates to Search via sidebar.
    func navigateToSearch() {
        self.navigateToSidebarItem(TestAccessibilityID.Sidebar.searchItem)
    }

    /// Navigates to Explore via sidebar.
    func navigateToExplore() {
        self.navigateToSidebarItem(TestAccessibilityID.Sidebar.exploreItem)
    }

    /// Navigates to Library via sidebar.
    func navigateToLibrary() {
        self.navigateToSidebarItem(TestAccessibilityID.Sidebar.libraryItem)
    }

    /// Navigates to Liked Music via sidebar.
    func navigateToLikedMusic() {
        self.navigateToSidebarItem(TestAccessibilityID.Sidebar.likedMusicItem)
    }
}
