import SwiftUI

// MARK: - CommandBarView

/// A floating command bar accessible via ⌘K that routes a query into the Search tab
/// and exposes a small palette of playback shortcuts.
@available(macOS 26.0, *)
struct CommandBarView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(\.navigationSelection) private var navigationSelection
    @Environment(\.searchFocusTrigger) private var searchFocusTrigger

    /// The YTMusicClient for search operations.
    let client: any YTMusicClientProtocol

    /// Binding to control visibility (used for dismiss).
    @Binding var isPresented: Bool

    /// Shared search view model used to route the query into the Search tab.
    let searchViewModel: SearchViewModel?

    /// The user's input text.
    @State private var inputText = ""

    /// Focus state for the text field.
    @FocusState private var isInputFocused: Bool

    @Namespace private var commandBarNamespace

    init(client: any YTMusicClientProtocol, isPresented: Binding<Bool>, searchViewModel: SearchViewModel? = nil) {
        self.client = client
        self._isPresented = isPresented
        self.searchViewModel = searchViewModel
    }

    /// Dismisses the command bar.
    private func dismissCommandBar() {
        self.isPresented = false
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                // Input field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.tint)

                    TextField(String(localized: "Search music…"), text: self.$inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused(self.$isInputFocused)
                        .accessibilityIdentifier(AccessibilityID.MainWindow.commandBarInput)
                        .onSubmit {
                            self.runSearch()
                        }

                    if !self.inputText.isEmpty {
                        Button {
                            self.inputText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Clear input"))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .opacity(0.3)

                self.quickActionsView
            }
            .frame(width: 500)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .glassEffectID("commandBar", in: self.commandBarNamespace)
        }
        .glassEffectTransition(.materialize)
        .accessibilityIdentifier(AccessibilityID.MainWindow.commandBar)
        .onAppear {
            self.isInputFocused = true
        }
        .onExitCommand {
            self.dismissCommandBar()
        }
    }

    // MARK: - Subviews

    private var quickActionsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                if self.playerService.isPlaying {
                    ActionChip(title: String(localized: "Pause"), systemImage: "pause.fill") {
                        Task { await self.playerService.pause() }
                        self.dismissCommandBar()
                    }
                } else {
                    ActionChip(title: String(localized: "Play"), systemImage: "play.fill") {
                        Task { await self.playerService.resume() }
                        self.dismissCommandBar()
                    }
                }

                ActionChip(title: String(localized: "Next"), systemImage: "forward.fill") {
                    Task { await self.playerService.next() }
                    self.dismissCommandBar()
                }

                ActionChip(title: String(localized: "Previous"), systemImage: "backward.fill") {
                    Task { await self.playerService.previous() }
                    self.dismissCommandBar()
                }

                ActionChip(title: String(localized: "Shuffle"), systemImage: "shuffle") {
                    self.playerService.toggleShuffle()
                    self.dismissCommandBar()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    /// Routes the current input into the Search tab and focuses its search field.
    private func runSearch() {
        let trimmedQuery = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.navigationSelection.wrappedValue = .search
        if let searchViewModel = self.searchViewModel {
            searchViewModel.selectedFilter = .all
            searchViewModel.query = trimmedQuery
            if !trimmedQuery.isEmpty {
                searchViewModel.search()
            }
        }
        self.dismissCommandBar()
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                self.searchFocusTrigger.wrappedValue = true
            }
        }
    }
}

// MARK: - ActionChip

@available(macOS 26.0, *)
private struct ActionChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Label(self.title, systemImage: self.systemImage)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var isPresented = true
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    CommandBarView(client: client, isPresented: $isPresented)
        .environment(PlayerService())
        .padding(40)
        .frame(width: 600, height: 300)
}
