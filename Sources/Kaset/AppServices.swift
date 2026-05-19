import Foundation

// MARK: - AppServices

/// Builds and owns the app-wide service graph.
@MainActor
struct AppServices {
    let authService: AuthService
    let webKitManager: WebKitManager
    let playerService: PlayerService
    let sharedClient: any YTMusicClientProtocol
    let notificationService: NotificationService
    let favoritesManager: FavoritesManager
    let likeStatusManager: SongLikeStatusManager
    let accountService: AccountService
    let syncedLyricsService: SyncedLyricsService

    static func make() -> AppServices {
        let authService = AuthService()
        let webKitManager = WebKitManager.shared
        let playerService = PlayerService()
        let realClient = YTMusicClient(authService: authService, webKitManager: webKitManager)
        let sharedClient: YTMusicClientProtocol
        #if DEBUG
            if UITestConfig.isUITestMode {
                sharedClient = MockUITestYTMusicClient()
            } else {
                sharedClient = realClient
            }
        #else
            sharedClient = realClient
        #endif

        playerService.setYTMusicClient(sharedClient)
        SongLikeStatusManager.shared.setClient(sharedClient)

        let accountService = AccountService(ytMusicClient: sharedClient, authService: authService)
        realClient.brandIdProvider = { [weak accountService] in
            accountService?.currentBrandId
        }

        return AppServices(
            authService: authService,
            webKitManager: webKitManager,
            playerService: playerService,
            sharedClient: sharedClient,
            notificationService: NotificationService(playerService: playerService),
            favoritesManager: .shared,
            likeStatusManager: .shared,
            accountService: accountService,
            syncedLyricsService: SyncedLyricsService(providers: [
                YTMusicSyncedProvider(client: sharedClient),
                LRCLibProvider(),
            ])
        )
    }
}
