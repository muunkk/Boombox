import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.api))
struct YTMusicAPIKeyProviderTests {
    final class RequestCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var requestCount = 0

        var count: Int {
            self.lock.withLock {
                self.requestCount
            }
        }

        func increment() {
            self.lock.withLock {
                self.requestCount += 1
            }
        }
    }

    @Test("Extracts API key from quoted bootstrap config")
    func extractsAPIKeyFromQuotedBootstrapConfig() throws {
        let html = #"""
        <script>
        window.ytcfg.set({"INNERTUBE_API_KEY":"test-api-key","INNERTUBE_CLIENT_VERSION":"1.2.3"});
        </script>
        """#

        let key = try YTMusicAPIKeyProvider.extractAPIKey(from: html)

        #expect(key == "test-api-key")
    }

    @Test("Extracts API key from assignment-style bootstrap config")
    func extractsAPIKeyFromAssignmentStyleBootstrapConfig() throws {
        let html = #"""
        <script>
        var config = {};
        config.INNERTUBE_API_KEY = "assignment-style-key";
        </script>
        """#

        let key = try YTMusicAPIKeyProvider.extractAPIKey(from: html)

        #expect(key == "assignment-style-key")
    }

    @Test("Rejects bootstrap config without API key")
    func rejectsBootstrapConfigWithoutAPIKey() {
        let html = "<html><body>No bootstrap config here</body></html>"

        #expect(throws: YTMusicError.self) {
            _ = try YTMusicAPIKeyProvider.extractAPIKey(from: html)
        }
    }

    @Test("Caches concurrent bootstrap key lookups")
    @MainActor
    func cachesConcurrentBootstrapKeyLookups() async throws {
        let counter = RequestCounter()
        MockURLProtocol.requestHandler = { request in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)

            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: 200,
                      httpVersion: nil,
                      headerFields: ["Content-Type": "text/html"]
                  )
            else {
                throw MockURLProtocol.MockURLProtocolError.invalidResponse
            }

            let data = Data(#""INNERTUBE_API_KEY":"cached-test-key""#.utf8)
            return (response, data)
        }
        defer { MockURLProtocol.reset() }

        let provider = YTMusicAPIKeyProvider(session: MockURLProtocol.makeMockSession())

        async let firstKey = provider.apiKey()
        async let secondKey = provider.apiKey()
        let keys = try await [firstKey, secondKey]

        #expect(keys == ["cached-test-key", "cached-test-key"])
        #expect(counter.count == 1)

        let cachedKey = try await provider.apiKey()
        #expect(cachedKey == "cached-test-key")
        #expect(counter.count == 1)
    }
}
