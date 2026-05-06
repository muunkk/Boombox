import Foundation
import Observation

// MARK: - RecentSearchesStore

/// Persists a small bounded list of recent search queries in UserDefaults.
/// Newest entries are first; submitting an existing query promotes it to the
/// top instead of duplicating.
@MainActor
@Observable
final class RecentSearchesStore {
    static let shared = RecentSearchesStore()

    private static let key = "settings.recentSearches"
    private static let maxEntries = 10

    private(set) var recent: [String] = []

    private init() {
        self.recent = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Records a query, deduping case-insensitively and capping at `maxEntries`.
    /// Empty / whitespace-only strings are ignored.
    func record(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        var updated = self.recent.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        updated.insert(query, at: 0)
        if updated.count > Self.maxEntries {
            updated = Array(updated.prefix(Self.maxEntries))
        }
        self.recent = updated
        UserDefaults.standard.set(updated, forKey: Self.key)
    }

    /// Removes a single entry.
    func remove(_ query: String) {
        self.recent.removeAll { $0 == query }
        UserDefaults.standard.set(self.recent, forKey: Self.key)
    }

    /// Removes all entries.
    func clearAll() {
        self.recent.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
