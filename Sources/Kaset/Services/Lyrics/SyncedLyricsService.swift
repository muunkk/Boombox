import Foundation
import Observation

@MainActor
@Observable
final class SyncedLyricsService {
    private struct ResolvedLyrics {
        let result: LyricResult
        let activeProvider: String?
    }

    private struct ProviderResult {
        let provider: String
        let providerIndex: Int
        let result: LyricResult
    }

    /// Current lyrics result.
    var currentLyrics: LyricResult = .unavailable

    /// Which provider supplied the current lyrics.
    var activeProvider: String?

    /// Loading state.
    var isLoading = false

    /// All registered providers, ordered by priority.
    private let providers: [LyricsProvider]

    /// Romanization service for transliterating non-Latin lyrics.
    private let romanizationService = RomanizationService()

    /// In-memory cache keyed by videoId.
    private var cache: [String: LyricResult] = [:]

    /// Insertion order of `cache` keys, used to evict the oldest entries once
    /// the cache exceeds `Self.maxCacheEntries`. Prevents unbounded growth over
    /// a long listening session spanning many tracks.
    private var cacheOrder: [String] = []

    /// Maximum number of cached lyric results retained at once.
    private static let maxCacheEntries = 100

    /// Base synced lyrics before romanization is applied for display.
    private var currentBaseSyncedLyrics: SyncedLyrics?

    /// Monotonic identifier used to ignore stale in-flight searches.
    private var fetchGeneration = 0

    init(providers: [LyricsProvider] = [LRCLibProvider()]) {
        self.providers = providers
        self.observeRomanizationSetting()
    }

    /// Stores a lyric result in the bounded in-memory cache, evicting the oldest
    /// entries once the cache exceeds `Self.maxCacheEntries`.
    private func storeInCache(_ videoId: String, _ result: LyricResult) {
        if self.cache[videoId] == nil {
            self.cacheOrder.append(videoId)
        }
        self.cache[videoId] = result

        while self.cacheOrder.count > Self.maxCacheEntries {
            let oldest = self.cacheOrder.removeFirst()
            self.cache.removeValue(forKey: oldest)
        }
    }

    func fetchLyrics(for info: LyricsSearchInfo) async {
        self.fetchGeneration += 1
        let requestID = self.fetchGeneration
        let cached = self.cache[info.videoId]

        if let cached, case .synced = cached {
            self.applyResolvedLyrics(
                .init(
                    result: cached,
                    activeProvider: Self.cachedProviderName(for: cached)
                ),
                requestID: requestID
            )
            return
        }

        if let cached {
            self.currentBaseSyncedLyrics = nil
            self.currentLyrics = cached
            self.activeProvider = Self.cachedProviderName(for: cached)
        }

        self.isLoading = true

        // Don't clear currentLyrics immediately to prevent flicker, but reset state when done
        var allResults: [ProviderResult] = []

        // Fetch concurrently
        await withTaskGroup(of: ProviderResult?.self) { group in
            for (providerIndex, provider) in self.providers.enumerated() {
                group.addTask {
                    let result = await provider.search(info: info)
                    return ProviderResult(
                        provider: provider.name,
                        providerIndex: providerIndex,
                        result: result
                    )
                }
            }

            for await res in group {
                if let res {
                    allResults.append(res)
                }
            }
        }

        var best: ProviderResult?
        for candidate in allResults {
            guard let currentBest = best else {
                best = candidate
                continue
            }

            if self.isBetter(candidate, than: currentBest) {
                best = candidate
            }
        }

        let resolved = self.resolveLyrics(best: best, cached: cached, videoId: info.videoId)
        self.applyResolvedLyrics(resolved, requestID: requestID)
    }

    /// Fallback logic
    func fallbackToPlainLyrics(_ lyrics: Lyrics, videoId: String) {
        if case .synced = self.currentLyrics {
            // Already synced, don't overwrite with plain
            return
        }

        self.currentBaseSyncedLyrics = nil

        if lyrics.isAvailable {
            self.currentLyrics = .plain(lyrics)
            self.activeProvider = lyrics.source
            self.storeInCache(videoId, .plain(lyrics))
        } else {
            self.currentLyrics = .unavailable
            self.activeProvider = nil
            self.storeInCache(videoId, .unavailable)
        }
    }

    private func observeRomanizationSetting() {
        withObservationTracking {
            _ = SettingsManager.shared.romanizationEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshCurrentRomanization()
                self?.observeRomanizationSetting()
            }
        }
    }

    private func refreshCurrentRomanization() {
        guard let baseLyrics = self.currentBaseSyncedLyrics else { return }
        self.applySyncedDisplay(from: baseLyrics, requestID: self.fetchGeneration)
    }

    /// Applies a synced result to `currentLyrics`. The base lyrics are shown
    /// immediately so resolving/toggling never blocks the UI. When romanization
    /// is enabled, the per-line script detection + tokenization
    /// (NLLanguageRecognizer / CFStringTokenizer) is performed off the MainActor
    /// and the romanized annotation is overlaid once it's ready. `romanizedText`
    /// is a separate per-line field, so the base lyrics are correct on their own.
    private func applySyncedDisplay(from synced: SyncedLyrics, requestID: Int) {
        self.currentLyrics = .synced(synced)

        guard self.romanizationService.isEnabled else { return }

        let lineTexts = synced.lines.map { (id: $0.id, text: $0.text) }
        Task { [weak self] in
            let romanized = await Task.detached(priority: .userInitiated) {
                Self.romanizeLines(lineTexts)
            }.value

            guard let self else { return }
            // Drop stale results, a disabled toggle, or an empty romanization.
            guard requestID == self.fetchGeneration,
                  self.romanizationService.isEnabled,
                  !romanized.isEmpty,
                  case .synced = self.currentLyrics
            else { return }

            self.currentLyrics = .synced(Self.merge(romanized, into: synced))
        }
    }

    /// Merges a `lineID → romanized text` map into a copy of `synced`.
    private static func merge(_ romanized: [UUID: String], into synced: SyncedLyrics) -> SyncedLyrics {
        var updatedLines = synced.lines
        for index in updatedLines.indices {
            updatedLines[index].romanizedText = romanized[updatedLines[index].id]
        }
        return SyncedLyrics(lines: updatedLines, source: synced.source)
    }

    /// Romanizes each line off the MainActor. Mirrors `RomanizationService`
    /// `romanize(_:)` dispatch using the same nonisolated romanizers; kept here
    /// (rather than reusing the MainActor-isolated service) so the heavy work
    /// can run on a background executor. Dedupes repeated line texts locally.
    nonisolated static func romanizeLines(_ lines: [(id: UUID, text: String)]) -> [UUID: String] {
        var results: [UUID: String] = [:]
        var cache: [String: String?] = [:]
        for line in lines {
            let romanized: String?
            if let cached = cache[line.text] {
                romanized = cached
            } else {
                romanized = Self.romanize(line.text)
                cache[line.text] = romanized
            }
            if let romanized {
                results[line.id] = romanized
            }
        }
        return results
    }

    nonisolated static func romanize(_ text: String) -> String? {
        if ScriptDetector.isLatinOnly(text) { return nil }

        let result: String? = switch ScriptDetector.dominantScript(text) {
        case .japanese: JapaneseRomanizer.romanize(text)
        case .korean: KoreanRomanizer.romanize(text)
        case .chinese: ChineseRomanizer.romanize(text)
        case .thai: ThaiRomanizer.romanize(text)
        case .bengali: BengaliRomanizer.romanize(text)
        case .hindi: HindiRomanizer.romanize(text)
        default: nil
        }

        let canonicalized = result.map { TextCanonicalizer.canonicalize($0) }
        return (canonicalized != nil && canonicalized != text) ? canonicalized : nil
    }

    private func resultRank(_ result: LyricResult) -> Int {
        switch result {
        case .synced:
            2
        case .plain:
            1
        case .unavailable:
            0
        }
    }

    private func isBetter(_ candidate: ProviderResult, than currentBest: ProviderResult) -> Bool {
        let candidateRank = self.resultRank(candidate.result)
        let currentRank = self.resultRank(currentBest.result)
        if candidateRank != currentRank {
            return candidateRank > currentRank
        }

        if case .plain = candidate.result,
           case .plain = currentBest.result
        {
            let candidateIsYTMusic = candidate.provider == "YTMusic"
            let currentIsYTMusic = currentBest.provider == "YTMusic"
            if candidateIsYTMusic != currentIsYTMusic {
                return candidateIsYTMusic
            }
        }

        return candidate.providerIndex < currentBest.providerIndex
    }

    private func resolveLyrics(
        best: ProviderResult?,
        cached: LyricResult?,
        videoId: String
    ) -> ResolvedLyrics {
        if let best {
            switch best.result {
            case .synced:
                self.storeInCache(videoId, best.result)
                return .init(result: best.result, activeProvider: best.provider)
            case .plain:
                if case let .plain(cachedPlain)? = cached {
                    return .init(result: .plain(cachedPlain), activeProvider: cachedPlain.source)
                }

                self.storeInCache(videoId, best.result)
                return .init(result: best.result, activeProvider: best.provider)
            case .unavailable:
                break
            }
        }

        if case let .plain(cachedPlain)? = cached {
            return .init(result: .plain(cachedPlain), activeProvider: cachedPlain.source)
        }

        self.storeInCache(videoId, .unavailable)
        return .init(result: .unavailable, activeProvider: nil)
    }

    private func applyResolvedLyrics(_ resolved: ResolvedLyrics, requestID: Int) {
        guard requestID == self.fetchGeneration else { return }

        if case let .synced(synced) = resolved.result {
            self.currentBaseSyncedLyrics = synced
            self.applySyncedDisplay(from: synced, requestID: requestID)
        } else {
            self.currentBaseSyncedLyrics = nil
            self.currentLyrics = resolved.result
        }

        self.activeProvider = resolved.activeProvider
        self.isLoading = false
    }

    private static func cachedProviderName(for result: LyricResult) -> String? {
        switch result {
        case let .synced(lyrics):
            lyrics.source
        case let .plain(lyrics):
            lyrics.source
        case .unavailable:
            nil
        }
    }
}
