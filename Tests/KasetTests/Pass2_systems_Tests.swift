import Foundation
import Testing
@testable import Kaset

// MARK: - CountingLyricsProvider

// Coverage for pass-2 systems fixes:
// - P2F049: `SyncedLyricsService` lyric cache is bounded (FIFO eviction).
// - P2F048: `ImageCache` in-flight de-duplication uses the composite (URL+size) key.
// - P2F017 / P2F051: previously-missing UI strings now localize for ar/tr.

/// A lyrics provider stub that records how many times it was searched for each
/// videoId, used to detect cache hits (no provider call) vs. misses (a call).
private actor CountingLyricsProvider: LyricsProvider {
    nonisolated let name = "Counting"
    private var counts: [String: Int] = [:]

    func search(info: LyricsSearchInfo) async -> LyricResult {
        self.counts[info.videoId, default: 0] += 1
        let line = SyncedLyricLine(
            timeInMs: 0,
            duration: 1000,
            text: "line for \(info.videoId)",
            words: nil
        )
        return .synced(SyncedLyrics(lines: [line], source: self.name))
    }

    func callCount(for videoId: String) -> Int {
        self.counts[videoId, default: 0]
    }
}

// MARK: - SyncedLyricsCacheBoundingTests

@Suite(.serialized, .tags(.service))
@MainActor
struct SyncedLyricsCacheBoundingTests {
    private func makeInfo(_ videoId: String) -> LyricsSearchInfo {
        LyricsSearchInfo(
            title: "Title \(videoId)",
            artist: "Artist",
            album: nil,
            duration: 100,
            videoId: videoId
        )
    }

    @Test("synced lyrics are served from cache on a repeat fetch")
    func cacheHitSkipsProvider() async {
        let provider = CountingLyricsProvider()
        let service = SyncedLyricsService(providers: [provider])

        await service.fetchLyrics(for: self.makeInfo("song-A"))
        await service.fetchLyrics(for: self.makeInfo("song-A"))

        // Second fetch should hit the cache and not call the provider again.
        #expect(await provider.callCount(for: "song-A") == 1)
    }

    @Test("oldest cache entries are evicted once the cap is exceeded")
    func evictsOldestBeyondCap() async {
        let provider = CountingLyricsProvider()
        let service = SyncedLyricsService(providers: [provider])

        // Fill the cache past its 100-entry cap so the first id is evicted.
        for index in 0 ..< 101 {
            await service.fetchLyrics(for: self.makeInfo("song-\(index)"))
        }

        // Each distinct id was fetched once so far.
        #expect(await provider.callCount(for: "song-0") == 1)
        #expect(await provider.callCount(for: "song-100") == 1)

        // The most-recent id is still cached: re-fetch must not call the provider.
        await service.fetchLyrics(for: self.makeInfo("song-100"))
        #expect(await provider.callCount(for: "song-100") == 1)

        // The oldest id (song-0) was evicted: re-fetch must call the provider again.
        await service.fetchLyrics(for: self.makeInfo("song-0"))
        #expect(await provider.callCount(for: "song-0") == 2)
    }
}

// MARK: - ImageCacheInFlightKeyingTests

@Suite(.tags(.service))
struct ImageCacheInFlightKeyingTests {
    private let url = URL(string: "https://example.com/art.jpg")!

    @Test("the in-flight de-dup key matches the memory cache key (URL + size)")
    func inFlightKeyMatchesMemoryKey() {
        // The in-flight map is now keyed by the same composite key as the memory
        // cache, so two requests for the same URL at different sizes get distinct
        // keys (and therefore distinct, correctly-sized fetches).
        let small = ImageCache.memoryCacheKey(for: self.url, targetSize: CGSize(width: 40, height: 40))
        let large = ImageCache.memoryCacheKey(for: self.url, targetSize: CGSize(width: 320, height: 320))
        #expect(small != large)

        // Same URL + same size still de-duplicates to a single key.
        let a = ImageCache.memoryCacheKey(for: self.url, targetSize: CGSize(width: 40, height: 40))
        #expect(small == a)
    }
}

// MARK: - Pass2LocalizationCoverageTests

@Suite(.serialized, .tags(.service))
struct Pass2LocalizationCoverageTests {
    private func localizedValue(key: String, localeIdentifier: String) -> String {
        guard let bundle = AppLocalization.bundle(forLocalization: localeIdentifier) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    @Test("previously-missing menu bar player strings localize in Arabic")
    func arabicMenuBarStrings() {
        for key in ["Open Boombox", "Nothing Playing", "Show Queue", "Audio Output"] {
            let value = self.localizedValue(key: key, localeIdentifier: "ar")
            #expect(value != key, "expected ar translation for \(key)")
        }
    }

    @Test("previously-missing hotkey/settings strings localize in Turkish")
    func turkishSettingsStrings() {
        for key in ["Global Hotkeys", "Reset All to Defaults", "Show in Menu Bar"] {
            let value = self.localizedValue(key: key, localeIdentifier: "tr")
            #expect(value != key, "expected tr translation for \(key)")
        }
    }

    @Test("REG-001 regression keys now localize in Arabic and Turkish")
    func reg001KeysLocalize() {
        let keys = [
            "Search songs, albums, artists...",
            "Episodes",
            "Show romanized text (romaji, pinyin, etc.) below non-Latin lyrics",
        ]
        for key in keys {
            #expect(self.localizedValue(key: key, localeIdentifier: "ar") != key, "ar missing \(key)")
            #expect(self.localizedValue(key: key, localeIdentifier: "tr") != key, "tr missing \(key)")
        }
    }

    @Test("interpolated VoiceOver labels keep their %@ placeholders in Arabic")
    func interpolatedLabelsPreservePlaceholders() {
        let nowPlaying = self.localizedValue(key: "Now playing: %@ by %@", localeIdentifier: "ar")
        #expect(nowPlaying != "Now playing: %@ by %@")
        // Both positional placeholders must survive translation.
        #expect(nowPlaying.components(separatedBy: "%@").count - 1 == 2)
    }
}
