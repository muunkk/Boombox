import Foundation
import Testing
@testable import Kaset

@Suite(.serialized, .tags(.model), .timeLimit(.minutes(1)))
struct SectionLayoutTests {
    private func section(title: String, items: [HomeSectionItem]) -> HomeSection {
        HomeSection(id: title, title: title, items: items)
    }

    @Test("Quick Picks title classifies as quickPicks even with song items")
    func quickPicksByTitle() {
        let items = TestFixtures.makeSongs(count: 4).map { HomeSectionItem.song($0) }
        #expect(self.section(title: "Quick picks", items: items).layout == .quickPicks)
    }

    @Test("Predominantly non-song items classify as cardShelf")
    func cardShelfForNonSongs() {
        let items: [HomeSectionItem] = [
            .album(TestFixtures.makeAlbum(id: "a1")),
            .playlist(TestFixtures.makePlaylist(id: "p1")),
            .artist(TestFixtures.makeArtist(id: "ar1")),
        ]
        #expect(self.section(title: "Mixed for you", items: items).layout == .cardShelf)
    }

    @Test("Predominantly song items classify as songList")
    func songListForSongs() {
        let items = TestFixtures.makeSongs(count: 5).map { HomeSectionItem.song($0) }
        #expect(self.section(title: "Listen again", items: items).layout == .songList)
    }

    @Test("Equal song/non-song counts tie-break to songList")
    func tieBreakToSongList() {
        let items: [HomeSectionItem] = [
            .song(TestFixtures.makeSong(id: "s1")),
            .album(TestFixtures.makeAlbum(id: "a1")),
        ]
        #expect(self.section(title: "Mix", items: items).layout == .songList)
    }

    @Test("isQuickPicks is case-insensitive and substring-based")
    func isQuickPicksMatch() {
        #expect(self.section(title: "Your QUICK PICKS", items: []).isQuickPicks)
        #expect(!self.section(title: "Listen again", items: []).isQuickPicks)
    }
}
