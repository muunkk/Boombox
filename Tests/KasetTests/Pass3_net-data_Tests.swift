import Foundation
import Testing
@testable import Kaset

// MARK: - Pass3RetryPolicyBackoffTests

// Pass-3 network-resilience and data-pagination fix coverage.
//
// Covers:
// - P3F019 / P3F042: RetryPolicy exponential backoff now carries equal jitter
//   (de-correlated retries) while staying bounded by `maxDelay`.
// - P3F022: RetryPolicy honors a server `Retry-After` for `.rateLimited`, and
//   `YTMusicError.rateLimited` surfaces rate-limit-specific messaging.
// - P3F020: connectivity-fatal `URLError`s are treated as non-retryable so the
//   retry budget is not burned on a known-dead link.
// - P3F043: a failed continuation page clears `hasMore` so the scroll sentinel
//   stops re-firing the same failing request in a tight loop (PlaylistDetail +
//   LikedMusic view models).

@Suite(.tags(.api))
struct Pass3RetryPolicyBackoffTests {
    @Test("jitteredDelay stays within the equal-jitter band [capped/2, capped]")
    func jitteredDelayWithinEqualJitterBand() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 1.0, maxDelay: 8.0)

        for attempt in 0 ..< 6 {
            let capped = min(1.0 * pow(2.0, Double(attempt)), 8.0)
            let lower = capped / 2
            // Sample repeatedly to exercise the random component.
            for _ in 0 ..< 200 {
                let delay = policy.jitteredDelay(for: attempt)
                #expect(delay >= lower, "delay \(delay) below band lower \(lower) at attempt \(attempt)")
                #expect(delay <= capped, "delay \(delay) above cap \(capped) at attempt \(attempt)")
            }
        }
    }

    @Test("jitteredDelay never exceeds maxDelay even for large attempt counts")
    func jitteredDelayNeverExceedsMaxDelay() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 1.0, maxDelay: 8.0)
        for attempt in 0 ..< 10 {
            for _ in 0 ..< 50 {
                #expect(policy.jitteredDelay(for: attempt) <= 8.0)
            }
        }
    }

    @Test("jitteredDelay produces varied values (jitter is present, not deterministic)")
    func jitteredDelayIsJittered() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 1.0, maxDelay: 8.0)
        // At attempt 2 the capped value is 4.0, so the band is [2.0, 4.0] — wide
        // enough that 50 samples will not all collapse to one value.
        let samples = Set((0 ..< 50).map { _ in policy.jitteredDelay(for: 2) })
        #expect(samples.count > 1, "Expected jittered delays, got a single value: \(samples)")
    }

    @Test("delay() remains deterministic (unchanged contract for existing callers)")
    func delayRemainsDeterministic() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0, maxDelay: 16.0)
        #expect(policy.delay(for: 0) == 1.0)
        #expect(policy.delay(for: 1) == 2.0)
        #expect(policy.delay(for: 2) == 4.0)
        #expect(policy.delay(for: 3) == 8.0)
    }
}

// MARK: - Pass3NetworkErrorTests

@Suite(.tags(.api))
struct Pass3NetworkErrorTests {
    @Test("Connectivity-fatal URLErrors are not automatically retried (but stay user-retryable)")
    func connectivityFatalErrorsAreNotAutoRetried() {
        let fatalCodes: [URLError.Code] = [
            .notConnectedToInternet,
            .dataNotAllowed,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .internationalRoamingOff,
        ]
        for code in fatalCodes {
            let error = YTMusicError.networkError(underlying: URLError(code))
            // RetryPolicy must not burn its budget on a confirmed-dead link…
            #expect(error.isAutomaticallyRetryable == false, "URLError \(code) should not auto-retry")
            // …but the user-facing Retry button must still be offered so a manual
            // retry works once connectivity returns (existing UX contract).
            #expect(error.isRetryable == true, "URLError \(code) should remain user-retryable")
        }
    }

    @Test("Transient URLErrors are automatically retried")
    func transientErrorsAreAutoRetried() {
        let transientCodes: [URLError.Code] = [.timedOut, .networkConnectionLost, .badServerResponse]
        for code in transientCodes {
            let error = YTMusicError.networkError(underlying: URLError(code))
            #expect(error.isAutomaticallyRetryable == true, "URLError \(code) should auto-retry")
            #expect(error.isRetryable == true, "URLError \(code) should be retryable")
        }
    }

    @Test("Non-URLError network failures are automatically retried")
    func nonURLErrorNetworkFailuresAreAutoRetried() {
        struct DummyError: Error {}
        let error = YTMusicError.networkError(underlying: DummyError())
        #expect(error.isAutomaticallyRetryable == true)
        #expect(error.isRetryable == true)
    }

    @Test("rateLimited is retryable and has rate-limit-specific messaging")
    func rateLimitedMessaging() {
        let error = YTMusicError.rateLimited(retryAfter: 30)
        #expect(error.isRetryable == true)
        #expect(error.isAutomaticallyRetryable == true)
        #expect(error.userFriendlyTitle == "Too Many Requests")
        #expect(error.userFriendlyMessage.localizedCaseInsensitiveContains("too many"))
        // Must not reuse the generic apiError "Server Error" title.
        #expect(error.userFriendlyTitle != "Server Error")
        #expect(error.requiresReauth == false)
    }

    @Test("rateLimited with nil retryAfter is still well-formed")
    func rateLimitedNilRetryAfter() {
        let error = YTMusicError.rateLimited(retryAfter: nil)
        #expect(error.isRetryable == true)
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.recoverySuggestion?.isEmpty == false)
    }
}

// MARK: - Pass3ContinuationFailureTests

@Suite(.serialized, .tags(.viewModel), .timeLimit(.minutes(1)))
@MainActor
struct Pass3ContinuationFailureTests {
    @Test("PlaylistDetail continuation failure clears hasMore so the sentinel stops")
    func playlistContinuationFailureClearsHasMore() async {
        let mockClient = MockYTMusicClient()
        let playlist = TestFixtures.makePlaylist(id: "VL-test-playlist", title: "Test Playlist")
        let viewModel = PlaylistDetailViewModel(playlist: playlist, client: mockClient)

        mockClient.playlistDetails["VL-test-playlist"] = TestFixtures.makePlaylistDetail(
            playlist: playlist,
            trackCount: 5
        )
        // Provide a continuation page so the initial load reports hasMore == true.
        mockClient.playlistContinuationTracks["VL-test-playlist"] = [
            [TestFixtures.makeSong(id: "cont-1")],
        ]

        await viewModel.load()
        #expect(viewModel.hasMore == true)

        // Now make the continuation request fail (transient network error).
        mockClient.shouldThrowError = YTMusicError.networkError(underlying: URLError(.timedOut))
        await viewModel.loadMore()

        // hasMore must be cleared so the per-row .task guard stops re-firing.
        #expect(viewModel.hasMore == false)
        #expect(viewModel.loadingState == .loaded)
        let firstCallCount = mockClient.getPlaylistContinuationCallCount
        #expect(firstCallCount == 1)

        // A subsequent sentinel-driven loadMore is a no-op (guard hasMore == false).
        await viewModel.loadMore()
        #expect(mockClient.getPlaylistContinuationCallCount == firstCallCount)
    }

    @Test("LikedMusic continuation failure clears hasMore so the sentinel stops")
    func likedContinuationFailureClearsHasMore() async {
        let mockClient = MockYTMusicClient()
        let viewModel = LikedMusicViewModel(client: mockClient)

        mockClient.likedSongs = TestFixtures.makeSongs(count: 3)
        // Provide a continuation page so the initial load reports hasMore == true.
        mockClient.likedSongsContinuationSongs = [
            [TestFixtures.makeSong(id: "more-1")],
        ]

        await viewModel.load()
        #expect(viewModel.hasMore == true)

        mockClient.shouldThrowError = YTMusicError.networkError(underlying: URLError(.timedOut))
        await viewModel.loadMore()

        #expect(viewModel.hasMore == false)
        #expect(viewModel.loadingState == .loaded)
        let firstCallCount = mockClient.getLikedSongsContinuationCallCount
        #expect(firstCallCount == 1)

        await viewModel.loadMore()
        #expect(mockClient.getLikedSongsContinuationCallCount == firstCallCount)
    }
}
