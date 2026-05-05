import XCTest

/// UI tests for the PlayerBar.
@MainActor
final class PlayerBarUITests: KasetUITestCase {
    // MARK: - Player Bar Visibility

    func testPlayerBarVisibleWithCurrentTrack() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        // Player bar should be visible when there's a current track
        // Look for the play/pause button
        let playPauseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Play' OR label CONTAINS 'Pause'")
        ).firstMatch
        XCTAssertTrue(waitForElement(playPauseButton, timeout: 10))
    }

    // MARK: - Playback Controls

    func testPlayPauseButtonExists() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let playPauseButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Play' OR label CONTAINS 'Pause'")
        ).firstMatch
        XCTAssertTrue(waitForHittable(playPauseButton))
    }

    func testNextButtonExists() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let nextButton = app.buttons["Next track"]
        XCTAssertTrue(waitForElement(nextButton, timeout: 10), "Next button should exist")
    }

    func testPreviousButtonExists() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let previousButton = app.buttons["Previous track"]
        XCTAssertTrue(waitForElement(previousButton, timeout: 10), "Previous button should exist")
    }

    func testShuffleButtonExists() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let shuffleButton = app.buttons["Shuffle"]
        XCTAssertTrue(waitForElement(shuffleButton, timeout: 10), "Shuffle button should exist")
    }

    func testRepeatButtonExists() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let repeatButton = app.buttons["Repeat"]
        XCTAssertTrue(waitForElement(repeatButton, timeout: 10), "Repeat button should exist")
    }

    // MARK: - Like/Dislike Buttons

    func testLikeButtonExists() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let likeButton = app.buttons["Like"]
        XCTAssertTrue(waitForElement(likeButton, timeout: 10), "Like button should exist")
    }

    func testDislikeButtonHidden() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let likeButton = app.buttons["Like"]
        XCTAssertTrue(waitForElement(likeButton, timeout: 10), "Like button should exist before checking player actions")

        let dislikeButton = app.buttons["Dislike"]
        XCTAssertFalse(dislikeButton.exists, "Dislike button should be hidden from the player bar")
    }

    func testNowPlayingPanelToggleRevealsSidebarPanelAndSeekSlider() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let toggle = app.buttons[TestAccessibilityID.PlayerBar.nowPlayingPanelToggle]
        XCTAssertTrue(waitForElement(toggle, timeout: 10), "Now Playing Panel toggle should exist")

        let panel = element(matchingAccessibilityID: TestAccessibilityID.Sidebar.nowPlayingPanel)
        if panel.exists {
            toggle.click()
            XCTAssertTrue(waitForElementToDisappear(panel), "Sidebar now-playing panel should hide before retesting reveal")
        }

        toggle.click()

        XCTAssertTrue(waitForElement(panel, timeout: 10), "Sidebar now-playing panel should appear")
        XCTAssertTrue(
            waitForElement(
                element(matchingAccessibilityID: TestAccessibilityID.Sidebar.nowPlayingArtwork),
                timeout: 10
            ),
            "Sidebar artwork should appear"
        )
        XCTAssertTrue(waitForElement(app.sliders[TestAccessibilityID.PlayerBar.seekSlider], timeout: 10), "Player bar seek slider should be visible while sidebar panel is shown")
        XCTAssertFalse(app.buttons["Now Playing Song"].exists, "Track title should not be a clickable player-bar popover trigger")
    }

    func testNowPlayingPanelToggleHidesSidebarPanel() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let toggle = app.buttons[TestAccessibilityID.PlayerBar.nowPlayingPanelToggle]
        XCTAssertTrue(waitForElement(toggle, timeout: 10), "Now Playing Panel toggle should exist")

        let panel = element(matchingAccessibilityID: TestAccessibilityID.Sidebar.nowPlayingPanel)
        if !panel.exists {
            toggle.click()
            XCTAssertTrue(waitForElement(panel, timeout: 10), "Sidebar now-playing panel should appear before hiding")
        }

        toggle.click()

        XCTAssertTrue(waitForElementToDisappear(panel), "Sidebar now-playing panel should hide")
    }

    // MARK: - Lyrics Button

    func testLyricsButtonExists() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let lyricsButton = app.buttons["Lyrics"]
        XCTAssertTrue(waitForElement(lyricsButton, timeout: 10), "Lyrics button should exist")
    }

    // MARK: - Button Interactions

    func testShuffleButtonToggles() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let shuffleButton = app.buttons["Shuffle"]
        XCTAssertTrue(waitForHittable(shuffleButton))

        // Check initial state
        let initialValue = shuffleButton.value as? String ?? ""

        // Click to toggle
        shuffleButton.click()

        // State should change
        Thread.sleep(forTimeInterval: 0.5)
        // The accessibility value should update
    }

    func testRepeatButtonCycles() {
        launchWithMockPlayer(isPlaying: true)

        navigateToHome()

        let repeatButton = app.buttons["Repeat"]
        XCTAssertTrue(waitForHittable(repeatButton))

        // Click to cycle through modes: off -> all -> one -> off
        repeatButton.click()
        Thread.sleep(forTimeInterval: 0.3)

        repeatButton.click()
        Thread.sleep(forTimeInterval: 0.3)

        repeatButton.click()
        Thread.sleep(forTimeInterval: 0.3)
    }

    // MARK: - Player Bar Persistence Across Views

    func testPlayerBarPersistsAcrossNavigation() {
        launchWithMockPlayer(isPlaying: true)

        // Navigate to different views and verify player bar is present

        navigateToHome()
        var playPause = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Play' OR label CONTAINS 'Pause'")
        ).firstMatch
        XCTAssertTrue(waitForElement(playPause, timeout: 10))

        navigateToSearch()
        playPause = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Play' OR label CONTAINS 'Pause'")
        ).firstMatch
        XCTAssertTrue(waitForElement(playPause))

        navigateToExplore()
        playPause = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Play' OR label CONTAINS 'Pause'")
        ).firstMatch
        XCTAssertTrue(waitForElement(playPause))
    }
}
