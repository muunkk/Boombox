import AppKit
import SwiftUI

// MARK: - HotkeyRecorderField

/// A single-row recorder for a global keyboard shortcut. Click to start
/// recording, then press a modifier + key combo. Pressing Escape cancels.
@available(macOS 26.0, *)
struct HotkeyRecorderField: View {
    @Binding var shortcut: HotkeyShortcut?

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
        return self.shortcut?.displayString ?? String(localized: "Set Shortcut")
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
            // Escape cancels.
            if event.keyCode == 53 {
                Task { @MainActor in
                    self.stopRecording()
                }
                return nil
            }

            if let captured = HotkeyShortcut.from(event: event) {
                Task { @MainActor in
                    self.shortcut = captured
                    self.stopRecording()
                }
                // Swallow the event so the user's chord doesn't reach the app.
                return nil
            }

            // No modifier — let the event pass through and stay in record mode.
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
