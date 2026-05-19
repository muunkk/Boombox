import Testing
@testable import Kaset

@Suite(.tags(.service))
@MainActor
struct AppServicesTests {
    @Test("Factory wires shared client into playback and account services")
    func factoryWiresSharedClientIntoPlaybackAndAccountServices() {
        let services = AppServices.make()

        #expect(services.playerService.ytMusicClient != nil)
        #expect(services.accountService.currentBrandId == nil)
    }
}
