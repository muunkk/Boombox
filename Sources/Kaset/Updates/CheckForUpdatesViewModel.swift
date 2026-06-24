import Combine
import SwiftUI

/// Publishes whether the user may currently trigger an update check.
/// Decoupled from Sparkle via an injected publisher so it is unit-testable
/// without a live updater.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool

    private var cancellable: AnyCancellable?

    init(initialValue: Bool = false, canCheckPublisher: AnyPublisher<Bool, Never>) {
        self.canCheckForUpdates = initialValue
        self.cancellable = canCheckPublisher.sink { [weak self] value in
            self?.canCheckForUpdates = value
        }
    }
}
