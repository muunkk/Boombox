import Combine
import Sparkle
import SwiftUI

/// Owns the Sparkle updater for the lifetime of the app.
/// This is the only type that talks to Sparkle directly (besides the menu view).
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        // Only auto-start when a real feed is configured (the bundled Info.plist
        // injects SUFeedURL). Under `swift run` there is no app-bundle feed, so
        // starting the updater would just emit Sparkle feed errors; gate it off.
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let hasFeed = !(feedURL ?? "").isEmpty
        self.controller = SPUStandardUpdaterController(
            startingUpdater: hasFeed,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater {
        self.controller.updater
    }

    /// Emits whether a manual check is currently allowed. `.receive(on:)` makes the
    /// main-thread delivery explicit rather than relying on Sparkle's KVO contract.
    var canCheckPublisher: AnyPublisher<Bool, Never> {
        self.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func checkForUpdates() {
        self.updater.checkForUpdates()
    }
}
