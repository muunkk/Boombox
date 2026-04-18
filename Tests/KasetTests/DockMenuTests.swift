import AppKit
import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.service))
@MainActor
struct DockMenuTests {
    @Test("Dock menu renders now playing state and player actions")
    func dockMenuRendersNowPlayingStateAndPlayerActions() throws {
        let settings = SettingsManager.shared
        let originalSidebarPanelSetting = settings.showSidebarNowPlayingPanel
        defer { settings.showSidebarNowPlayingPanel = originalSidebarPanelSetting }

        let delegate = AppDelegate()
        let playerService = PlayerService()
        playerService.currentTrack = TestFixtures.makeSong(
            id: "night-drive",
            title: "Night Drive",
            artistName: "Mel"
        )
        playerService.currentTrackLikeStatus = .like
        playerService.showLyrics = true
        playerService.updatePlaybackState(isPlaying: true, progress: 12, duration: 180)
        settings.showSidebarNowPlayingPanel = true

        delegate.playerService = playerService
        delegate.currentPlayerPresentationMode = .focus

        let menu = try #require(delegate.applicationDockMenu(NSApplication.shared))

        #expect(menu.item(withTitle: "Night Drive")?.isEnabled == false)
        #expect(menu.item(withTitle: "Mel")?.isEnabled == false)
        #expect(menu.item(withTitle: "Pause")?.isEnabled == true)
        #expect(menu.item(withTitle: "Previous Track")?.isEnabled == true)
        #expect(menu.item(withTitle: "Next Track")?.isEnabled == true)
        #expect(menu.item(withTitle: "Unlike")?.state == .on)
        #expect(menu.item(withTitle: "Hide Lyrics")?.state == .on)
        #expect(menu.item(withTitle: "Show Queue")?.state == .off)
        #expect(menu.item(withTitle: "Exit Focus Player")?.state == .on)
        #expect(menu.item(withTitle: "Small Player")?.isEnabled == true)
        #expect(menu.item(withTitle: "Hide Now Playing Panel")?.state == .on)
    }

    @Test("Dock menu disables track-only actions when nothing is playing")
    func dockMenuDisablesTrackOnlyActionsWhenNothingIsPlaying() throws {
        let settings = SettingsManager.shared
        let originalSidebarPanelSetting = settings.showSidebarNowPlayingPanel
        defer { settings.showSidebarNowPlayingPanel = originalSidebarPanelSetting }

        let delegate = AppDelegate()
        let playerService = PlayerService()
        settings.showSidebarNowPlayingPanel = false

        delegate.playerService = playerService

        let menu = try #require(delegate.applicationDockMenu(NSApplication.shared))

        #expect(menu.item(withTitle: "No Track Playing")?.isEnabled == false)
        #expect(menu.item(withTitle: "Play")?.isEnabled == false)
        #expect(menu.item(withTitle: "Like")?.isEnabled == false)
        #expect(menu.item(withTitle: "Show Lyrics")?.isEnabled == false)
        #expect(menu.item(withTitle: "Show Queue")?.isEnabled == true)
        #expect(menu.item(withTitle: "Focus Player")?.isEnabled == false)
        #expect(menu.item(withTitle: "Small Player")?.isEnabled == false)
        #expect(menu.item(withTitle: "Show Now Playing Panel")?.state == .off)
    }
}
