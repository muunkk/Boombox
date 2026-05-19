import Foundation

// MARK: - YTMusicAPIKeyProviding

/// Resolves the current YouTube Music internal API key at runtime.
@MainActor
protocol YTMusicAPIKeyProviding: AnyObject {
    func apiKey() async throws -> String
}

// MARK: - YTMusicAPIKeyProvider

/// Fetches YouTube Music bootstrap configuration and extracts the current internal API key.
@MainActor
final class YTMusicAPIKeyProvider: YTMusicAPIKeyProviding {
    static let shared = YTMusicAPIKeyProvider()

    private static let bootstrapURLString = "https://music.youtube.com/"

    private let session: URLSession
    private let logger = DiagnosticsLogger.api
    private var cachedAPIKey: String?
    private var apiKeyTask: Task<String, any Error>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func apiKey() async throws -> String {
        if let cachedAPIKey {
            return cachedAPIKey
        }

        if let apiKeyTask {
            return try await apiKeyTask.value
        }

        self.logger.debug("Resolving YouTube Music API key from bootstrap config")

        let apiKeyTask = Task { @MainActor in
            try await self.fetchAPIKey()
        }
        self.apiKeyTask = apiKeyTask

        do {
            let apiKey = try await apiKeyTask.value
            self.cachedAPIKey = apiKey
            self.apiKeyTask = nil
            return apiKey
        } catch {
            self.apiKeyTask = nil
            throw error
        }
    }

    private func fetchAPIKey() async throws -> String {
        guard let bootstrapURL = URL(string: Self.bootstrapURLString) else {
            throw YTMusicError.unknown(message: "Invalid YouTube Music bootstrap URL")
        }

        var request = URLRequest(url: bootstrapURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue(WebKitManager.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw YTMusicError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YTMusicError.networkError(underlying: URLError(.badServerResponse))
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw YTMusicError.apiError(
                message: "Bootstrap request failed",
                code: httpResponse.statusCode
            )
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw YTMusicError.parseError(message: "Unable to decode bootstrap response")
        }

        return try Self.extractAPIKey(from: html)
    }

    nonisolated static func extractAPIKey(from html: String) throws -> String {
        let patterns = [
            #""INNERTUBE_API_KEY"\s*:\s*"([^"]+)""#,
            #"\bINNERTUBE_API_KEY\b\s*=\s*"([^"]+)""#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex ..< html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: html)
            else {
                continue
            }

            let key = String(html[keyRange])
            guard !key.isEmpty else { continue }
            return key
        }

        throw YTMusicError.parseError(message: "Bootstrap response did not contain an API key")
    }
}
