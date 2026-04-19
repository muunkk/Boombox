import Foundation
import os

/// Centralized logging for Boombox.
enum DiagnosticsLogger {
    private static let subsystem = "com.melboonchan.boombox"

    /// Logger for authentication-related events.
    static let auth = Logger(subsystem: Self.subsystem, category: "Auth")

    /// Logger for API-related events.
    static let api = Logger(subsystem: Self.subsystem, category: "API")

    /// Logger for WebKit-related events.
    static let webKit = Logger(subsystem: Self.subsystem, category: "WebKit")

    /// Logger for player-related events.
    static let player = Logger(subsystem: Self.subsystem, category: "Player")

    /// Logger for UI-related events.
    static let ui = Logger(subsystem: Self.subsystem, category: "UI")

    /// Logger for notification-related events.
    static let notification = Logger(subsystem: Self.subsystem, category: "Notification")

    /// Logger for haptic feedback-related events.
    static let haptic = Logger(subsystem: Self.subsystem, category: "Haptic")

    /// Logger for network connectivity-related events.
    static let network = Logger(subsystem: Self.subsystem, category: "Network")

    /// Logger for app lifecycle events.
    static let app = Logger(subsystem: Self.subsystem, category: "App")

    /// Logger for AirPlay-related events.
    static let airplay = Logger(subsystem: Self.subsystem, category: "AirPlay")

    /// Logger for listening history-related events.
    static let history = Logger(subsystem: Self.subsystem, category: "History")
}
