import Foundation
import Observation
import os

/// Manages authentication state for YouTube Music.
@MainActor
@Observable
final class AuthService: AuthServiceProtocol {
    /// Authentication states.
    enum State: Equatable {
        case initializing
        case loggedOut
        case loggingIn
        case loggedIn(sapisid: String)

        var isLoggedIn: Bool {
            if case .loggedIn = self { return true }
            return false
        }

        var isInitializing: Bool {
            self == .initializing
        }
    }

    /// Current authentication state.
    private(set) var state: State

    /// Flag indicating whether re-authentication is needed.
    var needsReauth: Bool = false

    private let webKitManager: WebKitManagerProtocol
    private let logger = DiagnosticsLogger.auth

    init(webKitManager: WebKitManagerProtocol = WebKitManager.shared) {
        self.webKitManager = webKitManager
        // In UI test mode with skip auth, start in logged-in state immediately
        // This avoids async delays that can cause UI test flakiness
        let isUITest = UITestConfig.isUITestMode
        let skipAuth = UITestConfig.shouldSkipAuth
        let forceLoggedOut = UITestConfig.environmentValue(for: UITestConfig.mockLoggedOutKey) == "true"
        self.logger.debug("AuthService init: isUITestMode=\(isUITest), shouldSkipAuth=\(skipAuth)")
        if isUITest, forceLoggedOut {
            self.logger.info("UI Test mode: forcing logged-out state")
            self.state = .loggedOut
        } else if isUITest, skipAuth {
            self.logger.info("UI Test mode with SkipAuth: starting in logged-in state")
            self.state = .loggedIn(sapisid: "mock-sapisid-for-ui-tests")
        } else {
            self.state = .initializing
        }
    }

    /// Starts the login flow by presenting the login sheet.
    func startLogin() {
        self.logger.info("Starting login flow")
        self.state = .loggingIn
    }

    /// Checks if the user is logged in based on existing cookies.
    /// Waits for the initial Keychain restore before reading WebKit cookies.
    func checkLoginStatus() async {
        // In UI test mode with skip auth, immediately set logged in state
        if UITestConfig.isUITestMode, UITestConfig.environmentValue(for: UITestConfig.mockLoggedOutKey) == "true" {
            self.logger.info("UI Test mode: forcing logged out state")
            self.state = .loggedOut
            return
        }

        if UITestConfig.isUITestMode, UITestConfig.shouldSkipAuth {
            self.logger.info("UI Test mode: skipping auth check, assuming logged in")
            self.state = .loggedIn(sapisid: "mock-sapisid-for-ui-tests")
            return
        }

        self.logger.debug("Checking login status from cookies")

        await self.webKitManager.waitForInitialCookieRestore()
        self.logger.debug("Initial cookie restore completed, checking auth cookies")

        // Log detailed cookie info for debugging
        #if DEBUG
            await self.webKitManager.logAuthCookies()
        #endif

        if let sapisid = await self.webKitManager.getSAPISID() {
            self.logger.info("Found SAPISID cookie after initial restore, user is logged in")
            self.state = .loggedIn(sapisid: sapisid)
            self.needsReauth = false
            return
        }

        self.logger.info("No SAPISID cookie found after initial restore, user is logged out")
        self.state = .loggedOut
    }

    /// Called when a session expires (e.g., 401/403 from API).
    func sessionExpired() {
        self.logger.warning("Session expired, requiring re-authentication")
        Self.clearAccountScopedCaches()
        self.state = .loggedOut
        self.needsReauth = true
    }

    /// Signs out the user by clearing all cookies and data.
    func signOut() async {
        self.logger.info("Signing out user")

        await self.webKitManager.clearAllData()
        Self.clearAccountScopedCaches()

        // Clear account-scoped on-disk/in-memory user data so it is never surfaced to
        // the next account/user on a shared machine.
        FavoritesManager.shared.clear()
        RecentSearchesStore.shared.clearAll()
        Self.clearSavedPlaybackQueue()

        self.state = .loggedOut
        self.needsReauth = false

        self.logger.info("User signed out successfully")
    }

    /// Clears account-scoped API/URL caches so one account's data can never be
    /// served after sign-out or session expiry. This is part of the auth
    /// lifecycle rather than relying solely on a View observing account-id
    /// transitions, which never fires if account resolution fails.
    private static func clearAccountScopedCaches() {
        APICache.shared.invalidateAll()
        URLCache.shared.removeAllCachedResponses()
    }

    /// Removes the persisted playback queue so the previous account's queue is not auto-restored
    /// (via `restoreQueueFromPersistence`) on the next launch for a different user/session.
    ///
    /// These keys mirror `PlayerService`'s persisted-queue keys. Clearing the on-disk payload here is
    /// the high-value privacy fix; tearing down the *live* in-memory queue still requires the active
    /// `PlayerService` instance (see follow-up note), which `AuthService` does not hold.
    private static func clearSavedPlaybackQueue() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "boombox.saved.queue")
        defaults.removeObject(forKey: "boombox.saved.queueIndex")
        defaults.removeObject(forKey: "boombox.saved.playbackSession")
    }

    /// Called when login completes successfully (from LoginSheet observation).
    func completeLogin(sapisid: String) {
        self.logger.info("Login completed successfully")
        self.state = .loggedIn(sapisid: sapisid)
        self.needsReauth = false
    }
}
