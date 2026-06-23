import SwiftUI

// MARK: - HotkeysSettingsView

/// Settings tab listing every customizable in-app shortcut. Each row shows
/// the action's name, its current shortcut (with a recorder), and a "Reset"
/// button when the user has overridden the default.
@available(macOS 26.0, *)
struct HotkeysSettingsView: View {
    @State private var manager = KeyboardShortcutsManager.shared
    @State private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section {
                Text("In-app shortcuts only fire while Boombox is active. They cannot conflict with shortcuts in other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(ShortcutAction.Category.allCases, id: \.self) { category in
                Section(category.displayName) {
                    ForEach(self.actions(in: category)) { action in
                        self.row(for: action)
                    }
                }
            }

            Section(String(localized: "Global Hotkeys")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu Bar Player")
                        Text("Works system-wide while Boombox is running. Disabled until Show in Menu Bar is on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotkeyRecorderField(shortcut: self.$settings.menuBarHotkey)
                }
                .disabled(!self.settings.menuBarItemEnabled)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset All to Defaults") {
                        self.manager.resetAll()
                    }
                    .disabled(self.manager.overrides.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 480)
    }

    /// Command-only shortcuts reserved by standard macOS app/window behavior.
    /// Binding one of these to an in-app action silently overrides the system
    /// default (Quit/Close/Minimize/Hide/Settings) while Boombox is focused,
    /// which the project's "Preserve Standard macOS Shortcuts" rule discourages.
    private static let reservedShortcutStrings: Set<String> = ["⌘Q", "⌘W", "⌘M", "⌘H", "⌘,"]

    private func isReserved(_ shortcut: HotkeyShortcut) -> Bool {
        Self.reservedShortcutStrings.contains(shortcut.displayString)
    }

    private func actions(in category: ShortcutAction.Category) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.category == category }
    }

    private func row(for action: ShortcutAction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)

                if let conflict = self.manager.conflict(for: self.manager.shortcut(for: action), excluding: action) {
                    Text(String(localized: "Conflicts with \(conflict.displayName)"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if self.isReserved(self.manager.shortcut(for: action)) {
                    Text("Overrides a standard macOS shortcut")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            HotkeyRecorderField(
                shortcut: Binding(
                    get: { self.manager.override(for: action) ?? action.defaultShortcut },
                    set: { newValue in
                        self.manager.setOverride(newValue, for: action)
                    }
                ),
                requireModifiers: false,
                placeholder: action.defaultShortcut.displayString
            )

            if self.manager.override(for: action) != nil {
                Button("Reset") {
                    self.manager.setOverride(nil, for: action)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}
