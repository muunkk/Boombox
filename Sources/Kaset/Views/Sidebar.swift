import AppKit
import SwiftUI

// MARK: - Sidebar

/// Sidebar navigation for the main window, styled like Apple Music.
@available(macOS 26.0, *)
struct Sidebar: View {
    @Binding var selection: NavigationItem?

    /// Namespace for glass effect morphing.
    @Namespace private var sidebarNamespace

    @State private var settings = SettingsManager.shared

    /// Whether the user is currently holding ⌘ — used to overlay the
    /// Cmd-number badges on each navigation row.
    @State private var isCommandHeld = false
    @State private var modifierMonitor: Any?

    /// Order of top-level navigation items. Cmd+1 maps to index 0, Cmd+2 to
    /// index 1, etc. Keep this in sync with the rendered list below and the
    /// shortcuts declared in `KasetApp.swift`.
    static let cmdOrder: [NavigationItem] = [
        .search,
        .home,
        .library,
        .likedMusic,
        .explore,
        .newReleases,
        .history,
    ]

    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 0) {
                List(selection: self.$selection) {
                    Section {
                        self.row(.search, accessibility: AccessibilityID.Sidebar.searchItem)
                        self.row(.home, accessibility: AccessibilityID.Sidebar.homeItem)
                    }

                    Section(String(localized: "Library")) {
                        self.row(.library, accessibility: AccessibilityID.Sidebar.libraryItem)
                        self.row(.likedMusic, accessibility: AccessibilityID.Sidebar.likedMusicItem)
                    }

                    Section(String(localized: "Discover")) {
                        self.row(.explore, accessibility: AccessibilityID.Sidebar.exploreItem)
                        self.row(.newReleases, accessibility: AccessibilityID.Sidebar.newReleasesItem)
                    }

                    Section(String(localized: "Activity")) {
                        self.row(.history, accessibility: AccessibilityID.Sidebar.historyItem)
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier(AccessibilityID.Sidebar.container)
                .onChange(of: self.selection) { _, newValue in
                    if newValue != nil {
                        HapticService.navigation()
                    }
                }
            }

            Divider()
                .opacity(0.3)

            if self.settings.showSidebarNowPlayingPanel {
                NowPlayingSidebarPanel()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Divider()
                    .opacity(0.3)
            }

            // Profile section at bottom
            SidebarProfileView()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .onAppear {
            self.startCommandKeyMonitor()
        }
        .onDisappear {
            self.stopCommandKeyMonitor()
        }
    }

    private func row(_ item: NavigationItem, accessibility: String) -> some View {
        NavigationLink(value: item) {
            Label(item.displayName, systemImage: item.icon)
        }
        .accessibilityIdentifier(accessibility)
        .overlay(alignment: .trailing) {
            if let badgeNumber = self.cmdNumber(for: item), self.isCommandHeld {
                CmdShortcutBadge(number: badgeNumber)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: self.isCommandHeld)
    }

    private func cmdNumber(for item: NavigationItem) -> Int? {
        guard let index = Self.cmdOrder.firstIndex(of: item), index < 9 else { return nil }
        return index + 1
    }

    private func startCommandKeyMonitor() {
        guard self.modifierMonitor == nil else { return }
        self.modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let isHeld = event.modifierFlags.contains(.command)
            Task { @MainActor in
                if self.isCommandHeld != isHeld {
                    self.isCommandHeld = isHeld
                }
            }
            return event
        }
    }

    private func stopCommandKeyMonitor() {
        if let monitor = self.modifierMonitor {
            NSEvent.removeMonitor(monitor)
            self.modifierMonitor = nil
        }
        self.isCommandHeld = false
    }
}

// MARK: - CmdShortcutBadge

/// Small "⌘N" pill drawn on a sidebar row when the user holds Command,
/// modeled after Ghostty's tab number indicator.
@available(macOS 26.0, *)
private struct CmdShortcutBadge: View {
    let number: Int

    var body: some View {
        Text("⌘\(self.number)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.tertiary, lineWidth: 0.5)
                    }
            }
            .accessibilityHidden(true)
    }
}

@available(macOS 26.0, *)
#Preview {
    Sidebar(selection: .constant(.home))
        .frame(width: 220)
}
