import SwiftUI

// MARK: - CommandBarView

/// A floating command bar accessible via ⌘L that routes a query into the Search tab
/// and exposes a small palette of playback shortcuts.
@available(macOS 26.0, *)
struct CommandBarView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(GlobalNavigationCoordinator.self) private var globalNavigation
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

    /// Search suggestions for the current input.
    @State private var suggestions: [SearchSuggestion] = []

    /// Whether the palette is loading autocomplete suggestions.
    @State private var isLoadingSuggestions = false

    /// Index of the currently selected suggestion for keyboard navigation.
    @State private var selectedSuggestionIndex = -1

    /// Debounced autocomplete task.
    @State private var suggestionsTask: Task<Void, Never>?

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
                            self.submitSearch()
                        }
                        .onKeyPress(.downArrow) {
                            guard !self.visibleSuggestions.isEmpty else { return .ignored }
                            self.selectedSuggestionIndex = min(
                                self.selectedSuggestionIndex + 1,
                                self.visibleSuggestions.count - 1
                            )
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            guard !self.visibleSuggestions.isEmpty else { return .ignored }
                            self.selectedSuggestionIndex = max(self.selectedSuggestionIndex - 1, -1)
                            return .handled
                        }

                    if !self.inputText.isEmpty {
                        Button {
                            self.inputText = ""
                            self.clearSuggestions()
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

                if self.trimmedInput.isEmpty {
                    self.quickActionsView
                } else {
                    self.searchSuggestionsView
                }
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
        .onChange(of: self.inputText) { _, _ in
            self.fetchSuggestions()
        }
        .onDisappear {
            self.suggestionsTask?.cancel()
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

    private var searchSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Suggestions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                if self.isLoadingSuggestions {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 13, height: 13)
                }
            }

            if self.visibleSuggestions.isEmpty {
                Button {
                    self.runSearch(query: self.trimmedInput)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "return")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        Text("Search \"\(self.trimmedInput)\"")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(Array(self.visibleSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    self.suggestionRow(suggestion, index: index)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionRow(_ suggestion: SearchSuggestion, index: Int) -> some View {
        Button {
            self.runSearch(query: suggestion.query)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(suggestion.query)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(index == self.selectedSuggestionIndex ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(index == self.selectedSuggestionIndex ? .isSelected : [])
    }

    // MARK: - Actions

    private var trimmedInput: String {
        self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleSuggestions: [SearchSuggestion] {
        Array(self.suggestions.prefix(6))
    }

    private func submitSearch() {
        if self.selectedSuggestionIndex >= 0,
           self.selectedSuggestionIndex < self.visibleSuggestions.count
        {
            self.runSearch(query: self.visibleSuggestions[self.selectedSuggestionIndex].query)
        } else {
            self.runSearch(query: self.trimmedInput)
        }
    }

    /// Routes the current input into the Search tab and focuses its search field.
    private func runSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.navigationSelection.wrappedValue = .search
        // Reset SearchView's NavigationStack so the user lands on the search root,
        // not whatever detail page they pushed onto the stack from a previous search.
        self.globalNavigation.popSearchToRoot()
        self.clearSuggestions()

        if let searchViewModel = self.searchViewModel {
            searchViewModel.selectedFilter = .all
            searchViewModel.query = trimmedQuery
            if !trimmedQuery.isEmpty {
                Task {
                    await searchViewModel.searchImmediately()
                }
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

    private func fetchSuggestions() {
        self.suggestionsTask?.cancel()
        self.selectedSuggestionIndex = -1

        let query = self.trimmedInput
        guard !query.isEmpty else {
            self.clearSuggestions()
            return
        }

        self.isLoadingSuggestions = true
        self.suggestionsTask = Task {
            try? await Task.sleep(for: .milliseconds(150))

            guard !Task.isCancelled else { return }

            do {
                let fetchedSuggestions = try await self.client.getSearchSuggestions(query: query)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.trimmedInput == query else { return }
                    self.suggestions = fetchedSuggestions
                    self.isLoadingSuggestions = false
                }
            } catch {
                await MainActor.run {
                    guard self.trimmedInput == query else { return }
                    self.suggestions = []
                    self.isLoadingSuggestions = false
                }
            }
        }
    }

    private func clearSuggestions() {
        self.suggestionsTask?.cancel()
        self.suggestions = []
        self.isLoadingSuggestions = false
        self.selectedSuggestionIndex = -1
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
        .environment(GlobalNavigationCoordinator())
        .padding(40)
        .frame(width: 600, height: 300)
}
