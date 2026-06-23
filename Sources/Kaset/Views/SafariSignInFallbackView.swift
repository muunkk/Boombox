import AppKit
import SwiftUI

/// Safari-based sign-in fallback for Google passkey flows that embedded WebViews cannot complete.
@available(macOS 26.0, *)
struct SafariSignInFallbackView: View {
    @Environment(WebKitManager.self) private var webKitManager

    let onImportCompleted: () -> Void
    let onUseEmbeddedSignIn: () -> Void

    @State private var cookieText = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isImporting = false

    private var canImportCookies: Bool {
        !self.cookieText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.isImporting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use Safari for passkey sign-in")
                .font(.headline)

            Text("Google passkeys require Safari for this private app. Sign in there, then paste only the allowlisted YouTube or Google auth cookie rows here. They are imported locally into WebKit and Keychain, then the paste box is cleared.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open YouTube Music in Safari") {
                self.openYouTubeMusicInSafari()
            }
            .buttonStyle(.glassProminent)

            VStack(alignment: .leading, spacing: 8) {
                Text("Safari cookie rows or Cookie header")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: self.$cookieText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator, lineWidth: 1)
                    }
                    .disabled(self.isImporting)
            }

            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Use embedded sign-in") {
                    self.onUseEmbeddedSignIn()
                }

                Spacer()

                Button {
                    self.importCookies()
                } label: {
                    if self.isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Import Cookies")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!self.canImportCookies)
            }
        }
        .padding()
        .onDisappear {
            self.cookieText = ""
        }
    }

    private func openYouTubeMusicInSafari() {
        guard let url = URL(string: WebKitManager.origin) else { return }

        guard let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            NSWorkspace.shared.open(url)
            return
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: safariURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    private func importCookies() {
        guard self.canImportCookies else { return }

        self.isImporting = true
        self.statusMessage = nil
        self.errorMessage = nil

        Task {
            do {
                let result = try await self.webKitManager.importAuthCookies(from: self.cookieText)
                self.cookieText = ""
                self.statusMessage = String(
                    localized: "Imported \(result.importedCount) auth cookies locally. Checking login…"
                )
                self.onImportCompleted()
            } catch {
                self.errorMessage = error.localizedDescription
            }

            self.isImporting = false
        }
    }
}

#Preview {
    SafariSignInFallbackView(
        onImportCompleted: {},
        onUseEmbeddedSignIn: {}
    )
    .environment(WebKitManager.shared)
    .frame(width: 500, height: 650)
}
