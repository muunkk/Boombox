import Foundation

/// App-level player presentation modes.
enum PlayerPresentationMode: String, CaseIterable, Identifiable {
    /// Standard app layout with navigation content and bottom player bar.
    case standard

    /// Full-window now-playing experience.
    case focus

    /// Compact same-window now-playing experience.
    case compact

    var id: String {
        self.rawValue
    }

    var displayName: String {
        switch self {
        case .standard:
            String(localized: "Full App")
        case .focus:
            String(localized: "Focus Player")
        case .compact:
            String(localized: "Small Player")
        }
    }
}
