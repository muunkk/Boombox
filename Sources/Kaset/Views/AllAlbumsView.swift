import SwiftUI

/// View displaying all albums for an artist in a responsive grid.
@available(macOS 26.0, *)
struct AllAlbumsView: View {
    @State var viewModel: AllAlbumsViewModel

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                if self.viewModel.albums.isEmpty {
                    LoadingView(String(localized: "Loading albums..."))
                } else {
                    self.albumsGridView
                        .overlay(alignment: .top) {
                            if self.viewModel.loadingState == .loading {
                                ProgressView()
                                    .controlSize(.regular)
                                    .frame(width: 20, height: 20)
                                    .padding()
                            }
                        }
                }
            case .loaded, .loadingMore:
                self.albumsGridView
            case let .error(error):
                ErrorView(error: error) {
                    Task {
                        await self.viewModel.load()
                    }
                }
            }
        }
        .localizedNavigationTitle("Albums")
        .toolbarBackgroundVisibility(.hidden, for: .automatic)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .error = self.viewModel.loadingState {} else {
                PlayerBar()
            }
        }
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
    }

    // MARK: - Views

    private var albumsGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16),
            ], spacing: 20) {
                ForEach(self.viewModel.albums) { album in
                    NavigationLink(value: album.asPlaylistDestination()) {
                        self.albumCard(album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }

    private func albumCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: album.thumbnailURL?.highQualityThumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "square.stack")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 140, height: 140)
            .clipShape(.rect(cornerRadius: 8))

            Text(album.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 140, alignment: .leading)

            if let year = album.year {
                Text(year)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 140, alignment: .leading)
            }
        }
    }
}

#Preview {
    let albums = (1 ... 8).map { i in
        Album(
            id: "MPRE\(i)",
            title: "Album \(i)",
            artists: nil,
            thumbnailURL: nil,
            year: "202\(i % 5)",
            trackCount: 10
        )
    }
    let destination = AllAlbumsDestination(
        artistId: "artist1",
        artistName: "Test Artist",
        albums: albums,
        albumsBrowseId: nil,
        albumsParams: nil
    )
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    AllAlbumsView(viewModel: AllAlbumsViewModel(destination: destination, client: client))
        .environment(PlayerService())
}
