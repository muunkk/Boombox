import Foundation

// MARK: - YTMusicError

/// Unified error type for YouTube Music operations.
enum YTMusicError: LocalizedError {
    /// Authentication has expired or is invalid.
    case authExpired
    /// No authentication credentials available.
    case notAuthenticated
    /// Network request failed.
    case networkError(underlying: Error)
    /// Failed to parse API response.
    case parseError(message: String)
    /// API returned an error.
    case apiError(message: String, code: Int?)
    /// Server rate-limited the request (HTTP 429). `retryAfter` carries the
    /// server's suggested wait (parsed from the Retry-After header) when present.
    case rateLimited(retryAfter: TimeInterval?)
    /// Playback error.
    case playbackError(message: String)
    /// Invalid input provided to an operation.
    case invalidInput(String)
    /// Unknown error.
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .authExpired:
            return "Your session has expired. Please sign in again."
        case .notAuthenticated:
            return "You're not signed in. Please sign in to continue."
        case let .networkError(underlying):
            return "Network error: \(underlying.localizedDescription)"
        case let .parseError(message):
            return "Failed to parse response: \(message)"
        case let .apiError(message, code):
            if let code {
                return "API error (\(code)): \(message)"
            }
            return "API error: \(message)"
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case let .playbackError(message):
            return "Playback error: \(message)"
        case let .invalidInput(message):
            return "Invalid input: \(message)"
        case let .unknown(message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authExpired, .notAuthenticated:
            "Sign in to your YouTube Music account."
        case .networkError:
            "Check your internet connection and try again."
        case .parseError, .apiError:
            "Try again. If the problem persists, the service may be temporarily unavailable."
        case .rateLimited:
            "Wait a moment before trying again."
        case .playbackError:
            "Try playing a different track."
        case .invalidInput:
            "Please check the input and try again."
        case .unknown:
            "Try again later."
        }
    }

    /// Whether this error should trigger a re-authentication flow.
    var requiresReauth: Bool {
        switch self {
        case .authExpired, .notAuthenticated:
            true
        default:
            false
        }
    }

    /// Whether this error can be resolved by retrying the operation.
    /// Retryable errors are typically transient (network, server issues).
    /// Non-retryable errors require user action (auth) or indicate permanent failure (parse errors).
    var isRetryable: Bool {
        switch self {
        case .authExpired, .notAuthenticated:
            // Auth errors need user to re-login, not retry
            return false
        case .networkError:
            // Network issues are often transient
            return true
        case let .apiError(_, code):
            // Server errors (5xx) are retryable, client errors (4xx) usually aren't
            if let code {
                return code >= 500
            }
            return true
        case .rateLimited:
            // Honor a single bounded retry that respects the Retry-After delay
            // (see RetryPolicy) rather than failing instantly or hammering.
            return true
        case .parseError:
            // Parse errors won't be fixed by retrying
            return false
        case .playbackError:
            // Playback errors might be transient
            return true
        case .invalidInput:
            // Invalid input won't be fixed by retrying
            return false
        case .unknown:
            // Unknown errors might be transient
            return true
        }
    }

    /// Whether this error should be *automatically* retried by `RetryPolicy`.
    ///
    /// This is intentionally stricter than ``isRetryable``: ``isRetryable`` also
    /// drives the user-facing "Retry" button (a confirmed-offline error should
    /// still let the user retry after reconnecting), whereas automatic retry
    /// should not burn the backoff budget on a confirmed-dead link that cannot
    /// recover within the retry window. Connectivity-fatal `URLError`s therefore
    /// fail fast instead of sleeping through ~3s+ of guaranteed-to-fail attempts.
    var isAutomaticallyRetryable: Bool {
        switch self {
        case let .networkError(underlying):
            if let urlError = underlying as? URLError {
                switch urlError.code {
                case .notConnectedToInternet,
                     .dataNotAllowed,
                     .cannotConnectToHost,
                     .cannotFindHost,
                     .dnsLookupFailed,
                     .internationalRoamingOff:
                    return false
                default:
                    return true
                }
            }
            return true
        default:
            // For every other case, automatic-retry eligibility matches the
            // general retryability rule.
            return self.isRetryable
        }
    }

    /// User-friendly title for displaying in error UI.
    var userFriendlyTitle: String {
        switch self {
        case .authExpired, .notAuthenticated:
            "Authentication Required"
        case .networkError:
            "Connection Error"
        case .apiError:
            "Server Error"
        case .rateLimited:
            "Too Many Requests"
        case .parseError:
            "Data Error"
        case .playbackError:
            "Playback Error"
        case .invalidInput:
            "Invalid Input"
        case .unknown:
            "Error"
        }
    }

    /// User-friendly message for displaying in error UI.
    var userFriendlyMessage: String {
        switch self {
        case .authExpired:
            "Your session has expired. Please sign in again."
        case .notAuthenticated:
            "Please sign in to access this content."
        case .networkError:
            "Unable to connect. Please check your internet connection."
        case let .apiError(_, code):
            if let code {
                "Something went wrong (Error \(code))."
            } else {
                "Something went wrong. Please try again."
            }
        case .rateLimited:
            "Too many requests. Please wait a moment before trying again."
        case .parseError:
            "Unable to load content. Please try again."
        case .playbackError:
            "Unable to play this track. Try a different one."
        case let .invalidInput(message):
            message
        case let .unknown(message):
            message
        }
    }
}

// MARK: CustomDebugStringConvertible

/// Make the underlying error's description accessible for logging
extension YTMusicError: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case let .networkError(underlying):
            "YTMusicError.networkError(\(underlying))"
        default:
            self.errorDescription ?? String(describing: self)
        }
    }
}
