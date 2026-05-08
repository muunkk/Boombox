import Foundation
import Observation

// MARK: - KeyboardShortcutsManager

/// Persistent registry of in-app keyboard shortcut overrides keyed by
/// `ShortcutAction`. Each action has a built-in default; users can replace
/// or clear any of them.
@MainActor
@Observable
final class KeyboardShortcutsManager {
    static let shared = KeyboardShortcutsManager()

    private static let storageKey = "settings.shortcutOverrides"

    /// User overrides per action. Missing entries fall back to the action's
    /// `defaultShortcut`.
    private(set) var overrides: [ShortcutAction: HotkeyShortcut] = [:]

    private init() {
        self.load()
    }

    /// Returns the currently active shortcut for an action.
    func shortcut(for action: ShortcutAction) -> HotkeyShortcut {
        self.overrides[action] ?? action.defaultShortcut
    }

    /// Returns the user override (or `nil` if defaulted).
    func override(for action: ShortcutAction) -> HotkeyShortcut? {
        self.overrides[action]
    }

    /// Replaces the override for an action, or clears it (passing `nil`
    /// reverts to the default).
    func setOverride(_ shortcut: HotkeyShortcut?, for action: ShortcutAction) {
        if let shortcut {
            self.overrides[action] = shortcut
        } else {
            self.overrides.removeValue(forKey: action)
        }
        self.save()
    }

    /// Resets every action to its built-in default.
    func resetAll() {
        self.overrides.removeAll()
        self.save()
    }

    /// Returns `true` if more than one action currently maps to `shortcut`,
    /// excluding the supplied action. Useful for surfacing conflicts in the
    /// settings UI.
    func conflict(for shortcut: HotkeyShortcut, excluding action: ShortcutAction) -> ShortcutAction? {
        for other in ShortcutAction.allCases where other != action {
            if self.shortcut(for: other) == shortcut {
                return other
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([ShortcutAction: HotkeyShortcut].self, from: data) else { return }
        self.overrides = decoded
    }

    private func save() {
        if self.overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(self.overrides) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
