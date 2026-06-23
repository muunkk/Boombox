import Foundation
import Testing
@testable import Kaset

// Coverage for the confirmed Pass-3 security/persistence batch findings:
// - P3F001: playback WebView navigation policy allowlist (`Coordinator.isAllowedPlaybackURL`)
//   pins the authenticated playback WebView to https YouTube/Google origins and rejects
//   arbitrary third-party / non-https top-level navigations.
// - P3F039: sign-out clears the persisted playback queue so the previous account's queue is
//   not auto-restored on next launch, and clears recent searches.
//
// P3F002 (frame/origin validation of the singletonPlayer JS bridge) and P3F008 (off-main-actor
// Keychain writes) are exercised at runtime; their non-trivial dependencies (WKScriptMessage /
// real Keychain I/O) are not unit-mockable here, so they are validated by the surrounding suites
// and manual smoke tests rather than asserted directly.

@Suite(.serialized, .tags(.service))
@MainActor
struct Pass3SecurityTests {
    // MARK: - P3F001: playback navigation allowlist

    @Test("Allowlist permits the YouTube Music https origin")
    func allowsMusicYouTubeOrigin() throws {
        let url = URL(string: "https://music.youtube.com/watch?v=abc123")
        #expect(url != nil)
        #expect(try SingletonPlayerWebView.Coordinator.isAllowedPlaybackURL(#require(url)))
    }

    @Test("Allowlist permits the Google accounts origin (login refresh / OAuth bounce)")
    func allowsGoogleAccountsOrigin() throws {
        let url = URL(string: "https://accounts.google.com/ServiceLogin")
        #expect(url != nil)
        #expect(try SingletonPlayerWebView.Coordinator.isAllowedPlaybackURL(#require(url)))
    }

    @Test("Allowlist permits YouTube/Google playback sub-origins")
    func allowsPlaybackSubOrigins() {
        let allowed = [
            "https://www.youtube.com/",
            "https://r1---sn-abc.googlevideo.com/videoplayback",
            "https://yt3.ggpht.com/avatar.jpg",
            "https://i.ytimg.com/vi/abc/hqdefault.jpg",
            "https://lh3.googleusercontent.com/photo.jpg",
            "https://www.gstatic.com/script.js",
            "https://youtu.be/abc123",
        ]
        for raw in allowed {
            guard let url = URL(string: raw) else {
                Issue.record("Could not build URL: \(raw)")
                continue
            }
            #expect(
                SingletonPlayerWebView.Coordinator.isAllowedPlaybackURL(url),
                "Expected allowlist to permit \(raw)"
            )
        }
    }

    @Test("Allowlist rejects arbitrary third-party origins")
    func rejectsThirdPartyOrigins() {
        let rejected = [
            "https://evil.example.com/phish",
            "https://attacker.io/",
            "https://youtube.com.evil.com/",
            "https://notgoogle.com/",
        ]
        for raw in rejected {
            guard let url = URL(string: raw) else {
                Issue.record("Could not build URL: \(raw)")
                continue
            }
            #expect(
                !SingletonPlayerWebView.Coordinator.isAllowedPlaybackURL(url),
                "Expected allowlist to reject \(raw)"
            )
        }
    }

    @Test("Allowlist rejects non-https schemes on allowed hosts")
    func rejectsNonHTTPSScheme() throws {
        let httpURL = URL(string: "http://music.youtube.com/watch?v=abc")
        #expect(httpURL != nil)
        #expect(try !SingletonPlayerWebView.Coordinator.isAllowedPlaybackURL(#require(httpURL)))

        let fileURL = URL(string: "file:///etc/passwd")
        #expect(fileURL != nil)
        #expect(try !SingletonPlayerWebView.Coordinator.isAllowedPlaybackURL(#require(fileURL)))
    }

    @Test("Allowlist suffix match does not allow look-alike hosts")
    func rejectsLookAlikeSuffix() throws {
        // ".youtube.com" must not match "evilyoutube.com" — only a true label boundary.
        let lookAlike = URL(string: "https://evilyoutube.com/")
        #expect(lookAlike != nil)
        #expect(try !SingletonPlayerWebView.Coordinator.isAllowedPlaybackURL(#require(lookAlike)))
    }

    // MARK: - P3F039: sign-out clears persisted user-scoped data

    @Test("Sign-out clears the persisted playback queue keys")
    func signOutClearsSavedQueue() async {
        let defaults = UserDefaults.standard
        let queueKey = "boombox.saved.queue"
        let indexKey = "boombox.saved.queueIndex"
        let sessionKey = "boombox.saved.playbackSession"

        // Snapshot to restore after the test (shared UserDefaults).
        let previousQueue = defaults.data(forKey: queueKey)
        let previousIndex = defaults.object(forKey: indexKey)
        let previousSession = defaults.data(forKey: sessionKey)
        func restore(_ value: Any?, forKey key: String) {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defer {
            restore(previousQueue, forKey: queueKey)
            restore(previousIndex, forKey: indexKey)
            restore(previousSession, forKey: sessionKey)
        }

        // Seed persisted-queue payloads as if a previous user left a restorable queue.
        defaults.set(Data([0x01, 0x02, 0x03]), forKey: queueKey)
        defaults.set(2, forKey: indexKey)
        defaults.set(Data([0x04, 0x05]), forKey: sessionKey)

        let mock = MockWebKitManager()
        let auth = AuthService(webKitManager: mock)
        await auth.signOut()

        #expect(defaults.data(forKey: queueKey) == nil)
        #expect(defaults.object(forKey: indexKey) == nil)
        #expect(defaults.data(forKey: sessionKey) == nil)
    }

    @Test("Sign-out clears recent searches")
    func signOutClearsRecentSearches() async {
        let store = RecentSearchesStore.shared
        // Snapshot to restore after the test (shared singleton).
        let previous = store.recent
        defer {
            store.clearAll()
            for query in previous.reversed() {
                store.record(query)
            }
        }

        store.clearAll()
        store.record("previous user query")
        #expect(!store.recent.isEmpty)

        let mock = MockWebKitManager()
        let auth = AuthService(webKitManager: mock)
        await auth.signOut()

        #expect(store.recent.isEmpty)
    }
}
