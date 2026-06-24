import Combine
import Sparkle
import SwiftUI

/// Owns the Sparkle updater for the lifetime of the app.
/// This is the only type that talks to Sparkle directly (besides the menu view).
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true → Sparkle checks on its own schedule using the
        // SUFeedURL / SUPublicEDKey baked into the app's Info.plist.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater {
        self.controller.updater
    }

    /// Emits whether a manual check is currently allowed.
    var canCheckPublisher: AnyPublisher<Bool, Never> {
        self.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    func checkForUpdates() {
        self.updater.checkForUpdates()
    }
}
