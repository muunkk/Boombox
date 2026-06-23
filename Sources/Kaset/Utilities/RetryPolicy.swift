import Foundation

/// Configurable retry policy with exponential backoff.
struct RetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: 1.0, maxDelay: 8.0)

    /// Calculates the deterministic exponential-backoff ceiling for a given
    /// attempt (`baseDelay * 2^attempt`, capped at `maxDelay`). This is the upper
    /// bound used by ``jitteredDelay(for:)`` — the actual sleep applies jitter so
    /// concurrent retries do not synchronize.
    func delay(for attempt: Int) -> TimeInterval {
        min(self.baseDelay * pow(2.0, Double(attempt)), self.maxDelay)
    }

    /// The deterministic backoff with equal jitter applied: a random value in
    /// `[delay/2, delay]`. Jitter de-correlates concurrent retries so a burst of
    /// requests that fail at the same instant (e.g. on a brief connectivity drop
    /// during launch/tab-switch) does not re-fire in lockstep against the server
    /// (a thundering herd). The result still grows exponentially and stays bounded
    /// by `maxDelay`.
    func jitteredDelay(for attempt: Int) -> TimeInterval {
        let capped = self.delay(for: attempt)
        let half = capped / 2
        return half + Double.random(in: 0 ... half)
    }

    /// Executes an operation with retry logic.
    @MainActor
    func execute<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 0 ..< self.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Cancellation is never retryable — rethrow immediately so callers
                // that special-case `catch is CancellationError` see it as a clean
                // cancel rather than a spurious network error.
                if error is CancellationError {
                    throw error
                }
                if let ytError = error as? YTMusicError,
                   case let .networkError(underlying) = ytError,
                   (underlying as? URLError)?.code == .cancelled
                {
                    throw CancellationError()
                }

                // Don't retry non-retryable errors (auth, parse, invalid input)
                // or confirmed-dead connectivity failures. `isAutomaticallyRetryable`
                // is stricter than `isRetryable` (which also gates the user-facing
                // Retry button) so the backoff budget is not spent on a link that
                // cannot recover within the retry window.
                if let ytError = error as? YTMusicError, !ytError.isAutomaticallyRetryable {
                    throw error
                }

                // Don't retry on last attempt
                if attempt < self.maxAttempts - 1 {
                    // Honor the server's Retry-After hint for rate-limit (429)
                    // responses (bounded by maxDelay) instead of the default
                    // jittered backoff; otherwise use exponential backoff.
                    let delayTime: TimeInterval = if let ytError = error as? YTMusicError,
                                                     case let .rateLimited(retryAfter) = ytError,
                                                     let retryAfter
                    {
                        min(retryAfter, self.maxDelay)
                    } else {
                        self.jitteredDelay(for: attempt)
                    }
                    try await Task.sleep(for: .seconds(delayTime))
                }
            }
        }

        throw lastError ?? YTMusicError.unknown(message: "Unknown error after retries")
    }
}
