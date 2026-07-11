import Foundation
import Observation

@Observable
final class AppServices {
    @ObservationIgnored let artwork: any ArtworkLoading
    @ObservationIgnored let credentials: any CredentialStoring
    @ObservationIgnored let reminders: any ReminderScheduling
    @ObservationIgnored let metadata: MetadataServiceBundle

    init(
        artwork: any ArtworkLoading,
        credentials: any CredentialStoring,
        reminders: any ReminderScheduling,
        metadata: MetadataServiceBundle
    ) {
        self.artwork = artwork
        self.credentials = credentials
        self.reminders = reminders
        self.metadata = metadata
    }

    static func live() throws -> AppServices {
        AppServices(
            artwork: try ArtworkRepository(location: .applicationSupport()),
            credentials: KeychainCredentialStore(),
            reminders: LocalReminderScheduler(),
            metadata: MetadataServiceFactory.live()
        )
    }

    static var preview: AppServices {
        AppServices(
            artwork: PreviewArtworkLoader(),
            credentials: InMemoryCredentialStore(),
            reminders: InMemoryReminderScheduler(),
            metadata: MetadataServiceBundle(
                catalog: MetadataProviderCatalog(providers: []),
                podcastFeeds: PreviewPodcastFeedRefresher()
            )
        )
    }
}

nonisolated private struct PreviewArtworkLoader: ArtworkLoading {
    func data(for remoteURL: URL, cacheKey: String?) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }
}

nonisolated private struct PreviewPodcastFeedRefresher: PodcastFeedRefreshing {
    func refresh(_ request: PodcastFeedRefreshRequest) async throws -> PodcastFeedRefreshResult {
        throw URLError(.notConnectedToInternet)
    }
}
