import Foundation
import Testing
@testable import Kaset

/// Pass-3 regression tests for persistence / lifecycle fixes.
///
/// Covers:
/// - P3F015: "Last Used" launch page mapping (NavigationItem -> LaunchPage).
/// - P3F040: tolerant favorites decode reports skipped entries (drives the
///   pre-overwrite backup on the next save).
/// - P3F016: FavoritesManager.clear() empties in-memory state on sign-out /
///   account teardown.
///
/// These tests never touch the shared singletons (FavoritesManager.shared,
/// SettingsManager.shared, SongLikeStatusManager.shared) or real on-disk data:
/// FavoritesManager is created with `skipLoad: true`, and the LaunchPage mapping
/// is pure enum logic with no instance state.
@Suite(.serialized, .tags(.service), .timeLimit(.minutes(1)))
@MainActor
struct Pass3PersistTests {
    // MARK: - P3F015: Last Used launch page mapping

    @Test("LaunchPage(navigationItem:) maps launch-eligible pages")
    func launchPageFromNavigationItemMapsEligiblePages() {
        #expect(SettingsManager.LaunchPage(navigationItem: .home) == .home)
        #expect(SettingsManager.LaunchPage(navigationItem: .explore) == .explore)
        #expect(SettingsManager.LaunchPage(navigationItem: .newReleases) == .newReleases)
        #expect(SettingsManager.LaunchPage(navigationItem: .likedMusic) == .likedMusic)
        // Library maps to the "Playlists" launch page.
        #expect(SettingsManager.LaunchPage(navigationItem: .library) == .playlists)
    }

    @Test("LaunchPage(navigationItem:) returns nil for non-launch pages")
    func launchPageFromNavigationItemRejectsNonLaunchPages() {
        // Search and History have no launch-page equivalent, so they must not
        // overwrite the persisted "Last Used" value.
        #expect(SettingsManager.LaunchPage(navigationItem: .search) == nil)
        #expect(SettingsManager.LaunchPage(navigationItem: .history) == nil)
    }

    @Test("LaunchPage navigationItem and back round-trips for eligible pages")
    func launchPageNavigationItemRoundTrips() {
        let roundTrippable: [SettingsManager.LaunchPage] = [
            .home, .explore, .newReleases, .likedMusic, .playlists,
        ]
        for page in roundTrippable {
            let nav = page.navigationItem
            #expect(SettingsManager.LaunchPage(navigationItem: nav) == page)
        }
    }

    // MARK: - P3F040: tolerant decode reports skipped entries

    @Test("decodeFavorites decodes a fully valid array with zero skipped")
    func decodeFavoritesAllValid() throws {
        let items = [
            FavoriteItem.from(TestFixtures.makeSong(id: "song-1")),
            FavoriteItem.from(TestFixtures.makeAlbum(id: "MPRE-album-1")),
        ]
        let data = try JSONEncoder().encode(items)

        let (decoded, skipped) = try FavoritesManager.decodeFavorites(from: data)

        #expect(decoded.count == 2)
        #expect(skipped == 0)
    }

    @Test("decodeFavorites skips an unreadable entry and reports the count")
    func decodeFavoritesSkipsUnreadableEntry() throws {
        // A valid favorite encoded alongside a structurally-incompatible element.
        // The tolerant decode must keep the valid one and report one skip — this
        // skipped count is what now flags the next save to back up the file
        // before overwriting it (P3F040).
        let validItem = FavoriteItem.from(TestFixtures.makeSong(id: "song-keep"))
        let validData = try JSONEncoder().encode([validItem])

        guard var array = try JSONSerialization.jsonObject(with: validData) as? [Any] else {
            Issue.record("Encoded favorites was not a JSON array")
            return
        }
        // Append an element that cannot decode as a FavoriteItem (missing fields).
        array.append(["totally": "unrelated"])
        let mixedData = try JSONSerialization.data(withJSONObject: array)

        let (decoded, skipped) = try FavoritesManager.decodeFavorites(from: mixedData)

        #expect(decoded.count == 1)
        #expect(decoded.first?.contentId == "song-keep")
        #expect(skipped == 1)
    }

    @Test("decodeFavorites throws on non-array data (total corruption)")
    func decodeFavoritesThrowsOnNonArray() {
        let garbage = Data("{ not even json ]".utf8)
        #expect(throws: (any Error).self) {
            _ = try FavoritesManager.decodeFavorites(from: garbage)
        }
    }

    // MARK: - P3F016: clear() empties favorites on sign-out / account teardown

    @Test("clear() empties in-memory favorites")
    func clearEmptiesFavorites() {
        let manager = FavoritesManager(skipLoad: true)
        manager.add(.from(TestFixtures.makeSong(id: "song-1")))
        manager.add(.from(TestFixtures.makeAlbum(id: "MPRE-album-1")))
        #expect(manager.items.count == 2)

        manager.clear()

        #expect(manager.items.isEmpty)
        #expect(manager.isVisible == false)
    }

    @Test("clear() is safe to call when already empty")
    func clearWhenEmptyIsNoOp() {
        let manager = FavoritesManager(skipLoad: true)
        #expect(manager.items.isEmpty)

        manager.clear()

        #expect(manager.items.isEmpty)
    }
}
