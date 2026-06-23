import Foundation
import Observation

// MARK: - FailableDecodable

/// Decodes a single element, yielding `nil` instead of throwing when that element
/// is incompatible. Lets an array decode skip a corrupt/outdated entry rather than
/// failing wholesale.
private struct FailableDecodable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(Wrapped.self)
    }
}

// MARK: - FavoritesManager

/// Manages Favorites persistence and state.
@MainActor
@Observable
final class FavoritesManager {
    /// Shared singleton instance.
    static let shared = FavoritesManager()

    /// Current pinned items (ordered).
    private(set) var items: [FavoriteItem] = []

    /// Whether Favorites section should be visible.
    var isVisible: Bool {
        !self.items.isEmpty
    }

    /// Whether this instance should skip persistence (for testing).
    private let skipPersistence: Bool

    // MARK: - Persistence

    /// File URL for persisted data.
    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let appDir = appSupport.appendingPathComponent("Boombox", isDirectory: true)
        return appDir.appendingPathComponent("favorites.json")
    }

    /// Task for the current save operation - cancelled when new save is triggered.
    private var saveTask: Task<Void, Never>?

    /// Set when the persisted file existed but could not be decoded at all. Guards
    /// against the next save silently overwriting recoverable data.
    private var loadFailed = false

    // MARK: - Initialization

    private init() {
        // In UI test mode, use mock data and skip persistence to avoid touching live data
        if UITestConfig.isUITestMode {
            self.skipPersistence = true
            self.loadMockData()
        } else {
            self.skipPersistence = false
            self.load()
        }
    }

    /// Internal initializer for testing that skips auto-loading and persistence.
    /// Test instances never read from or write to disk, ensuring user data is never affected.
    init(skipLoad: Bool) {
        self.skipPersistence = skipLoad // When skipLoad is true, also skip persistence
        if !skipLoad {
            self.load()
        }
    }

    // MARK: - Decoding

    /// Decodes favorites tolerantly: a single incompatible/corrupt element is skipped
    /// rather than failing the entire array decode. Throws only when the data is not a
    /// decodable array at all (total corruption), which the caller treats as a failure.
    /// - Returns: The successfully decoded items and the count that were skipped.
    static func decodeFavorites(from data: Data) throws -> (items: [FavoriteItem], skipped: Int) {
        let containers = try JSONDecoder().decode([FailableDecodable<FavoriteItem>].self, from: data)
        let decoded = containers.compactMap(\.value)
        return (decoded, containers.count - decoded.count)
    }

    // MARK: - Load & Save

    /// Loads items from disk (called once at init, runs synchronously on main thread).
    /// This is acceptable because it only happens once at app launch.
    func load() {
        do {
            guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
                DiagnosticsLogger.ui.debug("Favorites file does not exist, starting fresh")
                return
            }
            let data = try Data(contentsOf: self.fileURL)
            let (decoded, skipped) = try Self.decodeFavorites(from: data)
            self.items = decoded
            if skipped > 0 {
                DiagnosticsLogger.ui.error("Skipped \(skipped) unreadable favorite item(s) during load")
            }
            DiagnosticsLogger.ui.info("Loaded \(decoded.count) favorite items")
        } catch {
            // Total decode failure (not a JSON array, truncated file, etc.). Flag it
            // so the next save backs up the existing file instead of destroying it.
            DiagnosticsLogger.ui.error("Failed to load favorites: \(error.localizedDescription)")
            self.items = []
            self.loadFailed = true
        }
    }

    /// Saves items to disk asynchronously on a background thread.
    /// Captures current state and writes without blocking the main thread.
    /// Cancels any pending save and debounces to coalesce rapid changes.
    /// Test instances (skipPersistence=true) never write to disk.
    private func save() {
        // Skip persistence for test instances to avoid overwriting user data
        guard !self.skipPersistence else { return }

        // Cancel any pending save to avoid race conditions
        self.saveTask?.cancel()

        // Capture current state for background write
        let itemsSnapshot = self.items
        let targetURL = self.fileURL

        // If the previous load could not decode the existing file, preserve it as a
        // backup before this save overwrites it. Only back up once.
        let shouldBackupCorruptFile = self.loadFailed
        self.loadFailed = false

        // Perform disk I/O off the main actor with debounce.
        // Slight delay coalesces rapid successive saves.
        self.saveTask = Task(priority: .utility) {
            // Debounce: wait briefly to coalesce rapid changes
            try? await Task.sleep(for: .milliseconds(100))

            // Check if cancelled (a newer save superseded this one)
            guard !Task.isCancelled else { return }

            do {
                // Ensure directory exists
                let directory = targetURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                if shouldBackupCorruptFile, FileManager.default.fileExists(atPath: targetURL.path) {
                    let backupURL = targetURL.appendingPathExtension("bak")
                    try? FileManager.default.removeItem(at: backupURL)
                    try? FileManager.default.copyItem(at: targetURL, to: backupURL)
                    DiagnosticsLogger.ui.info("Backed up unreadable favorites file to \(backupURL.lastPathComponent)")
                }

                let data = try JSONEncoder().encode(itemsSnapshot)
                try data.write(to: targetURL, options: .atomic)
                DiagnosticsLogger.ui.debug("Saved \(itemsSnapshot.count) favorite items")
            } catch {
                DiagnosticsLogger.ui.error("Failed to save favorites: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Actions

    /// Adds an item to Favorites if not already present.
    func add(_ item: FavoriteItem) {
        guard !self.isPinned(contentId: item.contentId) else {
            DiagnosticsLogger.ui.debug("Item already in favorites: \(item.contentId)")
            return
        }
        self.items.insert(item, at: 0) // New items go to the front
        self.save()
        DiagnosticsLogger.ui.info("Added to favorites: \(item.title)")
    }

    /// Removes an item by content ID (videoId or browseId).
    func remove(contentId: String) {
        guard let index = items.firstIndex(where: { $0.contentId == contentId }) else {
            DiagnosticsLogger.ui.debug("Item not in favorites: \(contentId)")
            return
        }
        let removed = self.items.remove(at: index)
        self.save()
        DiagnosticsLogger.ui.info("Removed from favorites: \(removed.title)")
    }

    /// Toggles an item in/out of Favorites.
    func toggle(_ item: FavoriteItem) {
        if self.isPinned(contentId: item.contentId) {
            self.remove(contentId: item.contentId)
        } else {
            self.add(item)
        }
    }

    /// Moves an item to a new position.
    func move(from source: IndexSet, to destination: Int) {
        self.items.move(fromOffsets: source, toOffset: destination)
        self.save()
    }

    /// Moves an item to the beginning of the list.
    func moveToTop(contentId: String) {
        guard let index = items.firstIndex(where: { $0.contentId == contentId }) else { return }
        let item = self.items.remove(at: index)
        self.items.insert(item, at: 0)
        self.save()
    }

    /// Moves an item to the end of the list.
    func moveToEnd(contentId: String) {
        guard let index = items.firstIndex(where: { $0.contentId == contentId }) else { return }
        let item = self.items.remove(at: index)
        self.items.append(item)
        self.save()
    }

    /// Checks if an item is pinned by content ID.
    func isPinned(contentId: String) -> Bool {
        self.items.contains { $0.contentId == contentId }
    }

    // MARK: - Convenience Methods

    /// Checks if a song is pinned.
    func isPinned(song: Song) -> Bool {
        self.isPinned(contentId: song.videoId)
    }

    /// Checks if an album is pinned.
    func isPinned(album: Album) -> Bool {
        self.isPinned(contentId: album.id)
    }

    /// Checks if a playlist is pinned.
    func isPinned(playlist: Playlist) -> Bool {
        self.isPinned(contentId: playlist.id)
    }

    /// Checks if an artist is pinned.
    func isPinned(artist: Artist) -> Bool {
        self.isPinned(contentId: artist.id)
    }

    /// Checks if a podcast show is pinned.
    func isPinned(podcastShow: PodcastShow) -> Bool {
        self.isPinned(contentId: podcastShow.id)
    }

    /// Toggles a song in/out of Favorites.
    func toggle(song: Song) {
        self.toggle(.from(song))
    }

    /// Toggles an album in/out of Favorites.
    func toggle(album: Album) {
        self.toggle(.from(album))
    }

    /// Toggles a playlist in/out of Favorites.
    func toggle(playlist: Playlist) {
        self.toggle(.from(playlist))
    }

    /// Toggles an artist in/out of Favorites.
    func toggle(artist: Artist) {
        self.toggle(.from(artist))
    }

    /// Toggles a podcast show in/out of Favorites.
    func toggle(podcastShow: PodcastShow) {
        self.toggle(.from(podcastShow))
    }

    // MARK: - Testing Support

    /// Loads mock favorites data from environment variable (for UI testing).
    /// This never touches disk, ensuring live user data is protected.
    private func loadMockData() {
        guard let jsonString = UITestConfig.environmentValue(for: UITestConfig.mockFavoritesKey),
              let data = jsonString.data(using: .utf8)
        else {
            DiagnosticsLogger.ui.debug("No mock favorites data provided")
            self.items = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([FavoriteItem].self, from: data)
            self.items = decoded
            DiagnosticsLogger.ui.info("Loaded \(decoded.count) mock favorite items")
        } catch {
            DiagnosticsLogger.ui.error("Failed to decode mock favorites: \(error.localizedDescription)")
            self.items = []
        }
    }

    /// Clears all favorites (for testing).
    func clearAll() {
        self.items.removeAll()
        self.save()
    }

    /// Resets the manager with new items (for testing).
    func reset(with items: [FavoriteItem]) {
        self.items = items
        self.save()
    }
}
