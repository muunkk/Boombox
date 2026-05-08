import Carbon.HIToolbox
import SwiftUI

// MARK: - HotkeyShortcut + SwiftUI

extension HotkeyShortcut {
    /// Maps the stored macOS virtual key code into a SwiftUI `KeyEquivalent`.
    /// Special keys (arrows, return, escape, etc.) use the canonical
    /// constants; printable keys fall back to the lowercased character we
    /// captured when the shortcut was recorded.
    var swiftUIKeyEquivalent: KeyEquivalent? {
        switch Int(self.keyCode) {
        case kVK_Return: return .return
        case kVK_Tab: return .tab
        case kVK_Space: return .space
        case kVK_Delete: return .delete
        case kVK_ForwardDelete: return .deleteForward
        case kVK_Escape: return .escape
        case kVK_LeftArrow: return .leftArrow
        case kVK_RightArrow: return .rightArrow
        case kVK_DownArrow: return .downArrow
        case kVK_UpArrow: return .upArrow
        case kVK_PageUp: return .pageUp
        case kVK_PageDown: return .pageDown
        case kVK_Home: return .home
        case kVK_End: return .end
        default:
            guard let first = self.keyLabel.first else { return nil }
            // SwiftUI matches keyboard input case-insensitively, but using
            // the lowercased form is the convention.
            return KeyEquivalent(Character(first.lowercased()))
        }
    }

    /// Carbon modifier mask → SwiftUI `EventModifiers`.
    var swiftUIEventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if self.carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if self.carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if self.carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if self.carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        return modifiers
    }
}

// MARK: - View.keyboardShortcut(for:)

extension View {
    /// Applies the active shortcut for a `ShortcutAction` (override or
    /// default). Reads from `KeyboardShortcutsManager.shared` so menus and
    /// hidden buttons re-bind whenever the user customizes a shortcut.
    @MainActor
    @ViewBuilder
    func keyboardShortcut(for action: ShortcutAction) -> some View {
        let shortcut = KeyboardShortcutsManager.shared.shortcut(for: action)
        if let key = shortcut.swiftUIKeyEquivalent {
            self.keyboardShortcut(key, modifiers: shortcut.swiftUIEventModifiers)
        } else {
            self
        }
    }
}
