import Carbon.HIToolbox
import Foundation

// MARK: - ShortcutAction

/// All customizable in-app keyboard shortcuts. Each case has a default
/// `HotkeyShortcut`; the user can override any of them via Settings.
///
/// These are *in-app* shortcuts: SwiftUI's `.keyboardShortcut` only fires
/// while Boombox is the active app, so they cannot collide with shortcuts
/// in other apps.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    // Playback
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case toggleShuffle
    case cycleRepeat
    case toggleLyrics
    case toggleFocusPlayer
    case toggleSmallPlayer

    // Navigation
    case goToSearch
    case goToHome
    case goToLibrary
    case goToLikedMusic
    case goToExplore
    case goToNewReleases
    case goToHistory
    case focusSearchField
    case openCommandBar
    case refreshPage
    case showMainWindow

    /// Window
    case toggleSidebar

    var id: String {
        rawValue
    }

    enum Category: String, CaseIterable {
        case playback
        case navigation
        case window

        var displayName: String {
            switch self {
            case .playback: String(localized: "Playback")
            case .navigation: String(localized: "Navigation")
            case .window: String(localized: "Window")
            }
        }
    }

    var category: Category {
        switch self {
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown,
             .toggleShuffle, .cycleRepeat, .toggleLyrics, .toggleFocusPlayer,
             .toggleSmallPlayer:
            .playback
        case .goToSearch, .goToHome, .goToLibrary, .goToLikedMusic,
             .goToExplore, .goToNewReleases, .goToHistory, .focusSearchField,
             .openCommandBar, .refreshPage, .showMainWindow:
            .navigation
        case .toggleSidebar:
            .window
        }
    }

    var displayName: String {
        switch self {
        case .playPause: String(localized: "Play / Pause")
        case .nextTrack: String(localized: "Next Track")
        case .previousTrack: String(localized: "Previous Track")
        case .volumeUp: String(localized: "Volume Up")
        case .volumeDown: String(localized: "Volume Down")
        case .toggleShuffle: String(localized: "Toggle Shuffle")
        case .cycleRepeat: String(localized: "Cycle Repeat")
        case .toggleLyrics: String(localized: "Toggle Lyrics")
        case .toggleFocusPlayer: String(localized: "Toggle Focus Player")
        case .toggleSmallPlayer: String(localized: "Toggle Small Player")
        case .goToSearch: String(localized: "Go to Search")
        case .goToHome: String(localized: "Go to Home")
        case .goToLibrary: String(localized: "Go to Library")
        case .goToLikedMusic: String(localized: "Go to Liked Music")
        case .goToExplore: String(localized: "Go to Explore")
        case .goToNewReleases: String(localized: "Go to New Releases")
        case .goToHistory: String(localized: "Go to History")
        case .focusSearchField: String(localized: "Focus Search Field")
        case .openCommandBar: String(localized: "Open Command Bar")
        case .refreshPage: String(localized: "Refresh Page")
        case .showMainWindow: String(localized: "Show Main Window")
        case .toggleSidebar: String(localized: "Toggle Sidebar")
        }
    }

    /// Built-in default shortcut for this action. Always returns a shortcut;
    /// `nil` means "no default" — currently every action has one.
    var defaultShortcut: HotkeyShortcut {
        switch self {
        case .playPause:
            HotkeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: 0, keyLabel: "Space")
        case .nextTrack:
            HotkeyShortcut(keyCode: UInt32(kVK_RightArrow), carbonModifiers: UInt32(cmdKey), keyLabel: "→")
        case .previousTrack:
            HotkeyShortcut(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(cmdKey), keyLabel: "←")
        case .volumeUp:
            HotkeyShortcut(keyCode: UInt32(kVK_UpArrow), carbonModifiers: UInt32(cmdKey), keyLabel: "↑")
        case .volumeDown:
            HotkeyShortcut(keyCode: UInt32(kVK_DownArrow), carbonModifiers: UInt32(cmdKey), keyLabel: "↓")
        case .toggleShuffle:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey), keyLabel: "S")
        case .cycleRepeat:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(cmdKey | optionKey), keyLabel: "R")
        case .toggleLyrics:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_Y), carbonModifiers: UInt32(cmdKey), keyLabel: "Y")
        case .toggleFocusPlayer:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: UInt32(cmdKey | shiftKey), keyLabel: "F")
        case .toggleSmallPlayer:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey | shiftKey), keyLabel: "M")
        case .goToSearch:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(cmdKey), keyLabel: "1")
        case .goToHome:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(cmdKey), keyLabel: "2")
        case .goToLibrary:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(cmdKey), keyLabel: "3")
        case .goToLikedMusic:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: UInt32(cmdKey), keyLabel: "4")
        case .goToExplore:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: UInt32(cmdKey), keyLabel: "5")
        case .goToNewReleases:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_6), carbonModifiers: UInt32(cmdKey), keyLabel: "6")
        case .goToHistory:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_7), carbonModifiers: UInt32(cmdKey), keyLabel: "7")
        case .focusSearchField:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: UInt32(cmdKey), keyLabel: "F")
        case .openCommandBar:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_L), carbonModifiers: UInt32(cmdKey), keyLabel: "L")
        case .refreshPage:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(cmdKey), keyLabel: "R")
        case .showMainWindow:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_0), carbonModifiers: UInt32(cmdKey), keyLabel: "0")
        case .toggleSidebar:
            HotkeyShortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(cmdKey | controlKey), keyLabel: "S")
        }
    }
}
