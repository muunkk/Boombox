import AppKit
import SwiftUI

// MARK: - HotkeyRecorderField

/// A single-row recorder for a keyboard shortcut. Click to start
/// recording, then press a modifier + key combo. Pressing Escape cancels.
///
/// `requireModifiers` defaults to `true` (global hotkeys must include a
/// modifier so Carbon can register them). Set to `false` for in-app
/// shortcuts so users can bind plain keys like Space.
@available(macOS 26.0, *)
struct HotkeyRecorderField: View {
    @Binding var shortcut: HotkeyShortcut?
    var requireModifiers: Bool = true
    var placeholder: String = .init(localized: "Set Shortcut")

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: self.toggleRecording) {
                Text(self.displayText)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 110)
                    .foregroundStyle(self.isRecording ? .red : .primary)
            }

            if !self.isRecording, self.shortcut != nil {
                Button("Clear") {
                    self.shortcut = nil
                }
                .buttonStyle(.borderless)
            }
        }
        .onDisappear {
            self.stopRecording()
        }
    }

    private var displayText: String {
        if self.isRecording {
            return String(localized: "Press shortcut…")
        }
        return self.shortcut?.displayString ?? self.placeholder
    }

    private func toggleRecording() {
        if self.isRecording {
            self.stopRecording()
        } else {
            self.startRecording()
        }
    }

    private func startRecording() {
        self.isRecording = true
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels (only when no modifiers held — otherwise it's a
            // valid shortcut to capture).
            if event.keyCode == 53,
               !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
               !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option),
               !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
               !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
            {
                Task { @MainActor in
                    self.stopRecording()
                }
                return nil
            }

            if let captured = HotkeyShortcut.from(event: event, requireModifiers: self.requireModifiers) {
                Task { @MainActor in
                    self.shortcut = captured
                    self.stopRecording()
                }
                // Swallow the event so the user's chord doesn't reach the app.
                return nil
            }

            // Insufficient input (no modifier, requireModifiers=true) — keep listening.
            return event
        }
    }

    private func stopRecording() {
        self.isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
