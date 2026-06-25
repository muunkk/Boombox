import SwiftUI

/// "Check for Updates…" menu item, enabled only when a check is allowed.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let onCheck: () -> Void

    init(viewModel: CheckForUpdatesViewModel, onCheck: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCheck = onCheck
    }

    var body: some View {
        Button("Check for Updates…", action: self.onCheck)
            .disabled(!self.viewModel.canCheckForUpdates)
    }
}
