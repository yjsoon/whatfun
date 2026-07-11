import Observation

@Observable
final class AppServices {
    @ObservationIgnored let artwork: ArtworkRepository
    @ObservationIgnored let credentials: any CredentialStoring
    @ObservationIgnored let reminders: any ReminderScheduling
    @ObservationIgnored let metadata: MetadataServiceBundle

    init(
        artwork: ArtworkRepository,
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
}
