import AppKit
import Carbon.HIToolbox
import Foundation

// MARK: - HotkeyShortcut

/// A user-recorded global keyboard shortcut.
/// Stores Carbon-style modifiers and the macOS virtual key code, plus a
/// human-readable character used to render the shortcut in the UI without
/// needing a full keymap table.
struct HotkeyShortcut: Codable, Equatable {
    /// macOS virtual key code (matches `NSEvent.keyCode`).
    let keyCode: UInt32

    /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    let carbonModifiers: UInt32

    /// Display string captured at recording time (e.g. "B", "Space", "←").
    let keyLabel: String

    var displayString: String {
        var result = ""
        if self.carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if self.carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if self.carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if self.carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += self.keyLabel
        return result
    }
}

extension HotkeyShortcut {
    /// Builds a shortcut from an `NSEvent` produced during recording.
    /// `requireModifiers` is on by default: global hotkeys (Carbon) need a
    /// modifier to be system-registrable. In-app shortcuts can opt out so
    /// users can bind plain keys like Space.
    static func from(event: NSEvent, requireModifiers: Bool = true) -> HotkeyShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        if requireModifiers, carbon == 0 { return nil }

        return HotkeyShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbon,
            keyLabel: Self.label(for: event)
        )
    }

    private static func label(for event: NSEvent) -> String {
        // Prefer a printable character when available.
        if let chars = event.charactersIgnoringModifiers, let first = chars.first {
            switch first {
            case " ": return "Space"
            case "\r": return "Return"
            case "\t": return "Tab"
            case "\u{1B}": return "Esc"
            case "\u{7F}": return "Delete"
            case "\u{F700}": return "↑"
            case "\u{F701}": return "↓"
            case "\u{F702}": return "←"
            case "\u{F703}": return "→"
            default:
                if first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol {
                    return String(first).uppercased()
                }
            }
        }
        return "Key \(event.keyCode)"
    }
}
