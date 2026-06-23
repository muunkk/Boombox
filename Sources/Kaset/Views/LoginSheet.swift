import SwiftUI

/// Login sheet presented when authentication is required.
@available(macOS 26.0, *)
struct LoginSheet: View {
    @Environment(AuthService.self) private var authService
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(\.dismiss) private var dismiss

    private enum LoginMode {
        case embedded
        case safariFallback
    }

    @State private var isCheckingLogin = false
    @State private var pollTask: Task<Void, Never>?
    @State private var loginMode: LoginMode = .embedded

    var body: some View {
        VStack(spacing: 0) {
            self.headerView

            Divider()

            switch self.loginMode {
            case .embedded:
                self.embeddedLoginView
            case .safariFallback:
                SafariSignInFallbackView(
                    onImportCompleted: {
                        self.checkForSuccessfulLogin()
                    },
                    onUseEmbeddedSignIn: {
                        self.loginMode = .embedded
                    }
                )
            }
        }
        .frame(width: 520, height: 700)
        .onChange(of: self.webKitManager.cookiesDidChange) { _, _ in
            self.checkForSuccessfulLogin()
        }
        .onAppear {
            self.startPollingForLogin()
        }
        .onDisappear {
            self.pollTask?.cancel()
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sign in to YouTube Music")
                    .font(.headline)

                Spacer()

                if self.isCheckingLogin {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                        .frame(width: 13, height: 13)
                }
            }

            Text(self.loginHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var loginHelpText: LocalizedStringKey {
        switch self.loginMode {
        case .embedded:
            "Embedded sign-in may work for passwords, but Google passkeys usually need Safari for this private app."
        case .safariFallback:
            "Safari handles the passkey. This app only imports allowlisted auth cookies into local WebKit and Keychain storage."
        }
    }

    private var embeddedLoginView: some View {
        VStack(spacing: 0) {
            LoginWebView(onNavigationToYouTubeMusic: {
                self.checkForSuccessfulLogin()
            })

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Text("Passkey prompt missing or blocked?")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Use Safari sign-in") {
                    self.loginMode = .safariFallback
                }
            }
            .padding()
        }
    }

    /// Starts a periodic task to check for successful login.
    private func startPollingForLogin() {
        self.pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))

                if !Task.isCancelled {
                    await self.checkForSuccessfulLoginAsync()
                }
            }
        }
    }

    private func checkForSuccessfulLogin() {
        guard !self.isCheckingLogin else { return }

        Task {
            await self.checkForSuccessfulLoginAsync()
        }
    }

    private func checkForSuccessfulLoginAsync() async {
        guard !self.isCheckingLogin else { return }

        self.isCheckingLogin = true

        // Small delay to allow cookies to settle
        try? await Task.sleep(for: .milliseconds(300))

        if let sapisid = await webKitManager.getSAPISID() {
            // Force backup cookies immediately after login
            // This ensures persistence across app restarts even if WebKit loses data
            await self.webKitManager.forceBackupCookies()

            // Wait a moment longer to ensure all cookies are fully propagated
            // This prevents race conditions where API calls happen before cookies are ready
            try? await Task.sleep(for: .milliseconds(200))

            self.authService.completeLogin(sapisid: sapisid)
            self.pollTask?.cancel()
            self.dismiss()
        }

        self.isCheckingLogin = false
    }
}

#Preview {
    LoginSheet()
        .environment(AuthService())
        .environment(WebKitManager.shared)
}
