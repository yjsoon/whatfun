import Foundation

nonisolated enum ArchiveMediaKind: String, Codable, CaseIterable, Sendable {
    case book
    case comic
    case movie
    case television
    case game
    case podcast
}

nonisolated enum ArchiveLifecycleStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case inProgress = "in_progress"
    case paused
    case completed
    case dropped
    case rereading
    case rewatching
    case replaying
    case following
    case archived
}

nonisolated enum ArchivePodcastListeningStyle: String, Codable, CaseIterable, Sendable {
    case everyEpisode = "every_episode"
    case selectedEpisodes = "selected_episodes"
    case keepAround = "keep_around"
}

nonisolated enum ArchiveUnitKind: String, Codable, CaseIterable, Sendable {
    case season
    case episode
    case volume
    case issue
}

nonisolated enum ArchiveCycleKind: String, Codable, CaseIterable, Sendable {
    case initial
    case installmentContinuation = "installment_continuation"
    case reread
    case rewatch
    case replay
    case repeatConsumption = "repeat_consumption"
}

nonisolated enum ArchiveEventKind: String, Codable, CaseIterable, Sendable {
    case created
    case started
    case statusChanged = "status_changed"
    case progressUpdated = "progress_updated"
    case markedCompleted = "marked_completed"
    case completionReversed = "completion_reversed"
    case archived
    case restored
    case movedToTrash = "moved_to_trash"
}

nonisolated enum ArchiveArtworkKind: String, Codable, CaseIterable, Sendable {
    case remote
    case userSelected = "user_selected"
    case generated
}

nonisolated enum ArchiveListKind: String, Codable, CaseIterable, Sendable {
    case manual
    case smart
}

nonisolated enum ArchiveSmartMatchMode: String, Codable, CaseIterable, Sendable {
    case all
    case any
}

nonisolated enum ArchiveReminderState: String, Codable, CaseIterable, Sendable {
    case pending
    case delivered
    case cancelled
}

/// The portable representation of one canonical library title.
///
/// Current status and dates are included as rebuildable projections for other apps. Cycles,
/// sessions, and event records remain the historical source of truth.
nonisolated struct ArchiveItemRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var mediaKind: ArchiveMediaKind
    var title: String
    var subtitle: String?
    var sortTitle: String?
    var originalTitle: String?
    var summary: String?
    var creators: [String] = []
    var genres: [String] = []
    var platforms: [String] = []
    var languageCode: String?
    var pageCount: Int?
    var runtimeMinutes: Double?
    var releaseDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    var isFavorite: Bool = false
    var comment: String?
    var projectedStatus: ArchiveLifecycleStatus = .planned
    var projectedRating: Double?
    var ratingOverride: Double?
    var projectedStartDate: Date?
    var projectedCompletionDate: Date?
    var projectedRepeatCount: Int = 0
    var artworkKind: ArchiveArtworkKind?
    var artworkURL: String?
    var artworkArchivePath: String?
    var podcastListeningStyle: ArchivePodcastListeningStyle?
    /// Opaque Keychain identifier only. A private feed URL must never be written here.
    var feedCredentialIdentifier: String?
    var feedURLIsPrivate: Bool = false
}

/// A nested season, episode, volume, or issue. `parentUnitID` forms the hierarchy.
nonisolated struct ArchiveUnitRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var parentUnitID: UUID?
    var kind: ArchiveUnitKind
    var title: String
    var summary: String?
    var guid: String?
    var canonicalURL: String?
    var sortIndex: Int
    var seasonNumber: Int?
    var episodeNumber: Int?
    var volumeNumber: Int?
    var issueNumber: String?
    var releasedAt: Date?
    var durationMinutes: Double?
    var pageCount: Int?
    var status: ArchiveLifecycleStatus = .planned
    var rating: Double?
    var completedAt: Date?
    var isNotable: Bool = false
    var comment: String?
    var artworkURL: String?
    var artworkArchivePath: String?
}

/// One intentional pass through an item or unit, such as an initial read or a replay.
nonisolated struct ArchiveCycleRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var unitID: UUID?
    var sequence: Int
    var kind: ArchiveCycleKind
    var status: ArchiveLifecycleStatus
    var startedAt: Date?
    var completedAt: Date?
    var rating: Double?
    var note: String?
    var currentPage: Int?
    var totalPages: Int?
    var elapsedMinutes: Double?
    var playtimeMinutes: Double?
    var completionPercentage: Double?
}

/// A timestamped consumption session. Progress fields are optional and deliberately shared
/// across media types so a session can be reconstructed without consulting app-specific state.
nonisolated struct ArchiveSessionRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var cycleID: UUID?
    var unitID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var loggedAt: Date
    var timeZoneIdentifier: String
    var durationMinutes: Double?
    var startPage: Int?
    var endPage: Int?
    var totalPages: Int?
    var chapter: String?
    var startElapsedMinutes: Double?
    var endElapsedMinutes: Double?
    var totalRuntimeMinutes: Double?
    var playtimeDeltaMinutes: Double?
    var cumulativePlaytimeMinutes: Double?
    var completionPercentage: Double?
    var isCompletion: Bool = false
    var rating: Double?
    var note: String?
}

/// An immutable lifecycle fact. `details` is for small, forward-compatible values only.
nonisolated struct ArchiveEventRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var cycleID: UUID?
    var unitID: UUID?
    var sessionID: UUID?
    var kind: ArchiveEventKind
    var occurredAt: Date
    var timeZoneIdentifier: String
    var previousStatus: ArchiveLifecycleStatus?
    var newStatus: ArchiveLifecycleStatus?
    var note: String?
    var details: [String: String] = [:]
}

nonisolated struct ArchiveQuoteRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var unitID: UUID?
    var sessionID: UUID?
    var text: String
    var timestampSeconds: Double?
    var comment: String?
    var capturedAt: Date
}

nonisolated struct ArchiveListRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var kind: ArchiveListKind = .manual
    var matchMode: ArchiveSmartMatchMode?
    var comment: String?
    var iconName: String?
    var colorHex: String?
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    var purgeAfter: Date?
}

/// A forward-compatible smart-list predicate using stable, nonlocalized field/operator names.
nonisolated struct ArchiveSmartListRuleRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var listID: UUID
    var sortIndex: Int
    var field: String
    var comparison: String
    var isNegated: Bool = false
    var createdAt: Date
    var updatedAt: Date
}

/// A typed smart-rule value. Separate records preserve ordering and UUID references without
/// encoding app-specific values into opaque CSV cells.
nonisolated struct ArchiveSmartListRuleValueRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var ruleID: UUID
    var sortIndex: Int
    var valueType: String
    var stringValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?
    var referenceID: UUID?
}

nonisolated struct ArchiveListMembershipRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var listID: UUID
    var itemID: UUID
    var positionRank: String?
    var addedAt: Date
    var note: String?
}

nonisolated struct ArchiveTagRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var colorHex: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct ArchiveTagMembershipRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var tagID: UUID
    var itemID: UUID
    var addedAt: Date
    var source: String?
    var sortIndex: Int?
}

/// One artwork source. Full JSON may carry user-owned image bytes; portable CSV points to a
/// checksummed file under `assets/artwork/`. Remote cache bytes are always rebuildable.
nonisolated struct ArchiveArtworkRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var unitID: UUID?
    var kind: ArchiveArtworkKind
    var remoteURL: String?
    var archivePath: String?
    var imageData: Data?
    var contentHash: String?
    var mimeType: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var aspectRatio: Double?
    var provider: String?
    var attributionText: String?
    var attributionURL: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct ArchiveCreditRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var unitID: UUID?
    var name: String
    var role: String
    var sortIndex: Int
    var externalPersonID: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct ArchiveReminderRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID
    var fireAt: Date
    var timeZoneIdentifier: String
    var state: ArchiveReminderState
    var createdAt: Date
    var updatedAt: Date
}

/// A provider identity can belong to a root item or a nested unit. Exactly one join should be present.
nonisolated struct ArchiveExternalReferenceRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var itemID: UUID?
    var unitID: UUID?
    var provider: String
    var recordKind: String
    var externalID: String
    var canonicalURL: String?
    var lastFetchedAt: Date?
    var etag: String?
    var lastModified: String?
    var payloadHash: String?
    var payloadVersion: String?
    var attributionText: String?
    var attributionURL: String?
    var isActiveFeed: Bool = false
    var isPrivateFeed: Bool = false
    /// Opaque lookup key; private feed contents are stored only in the encrypted block.
    var credentialKeychainID: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct ArchivePayload: Codable, Equatable, Sendable {
    var items: [ArchiveItemRecord] = []
    var units: [ArchiveUnitRecord] = []
    var cycles: [ArchiveCycleRecord] = []
    var sessions: [ArchiveSessionRecord] = []
    var events: [ArchiveEventRecord] = []
    var quotes: [ArchiveQuoteRecord] = []
    var lists: [ArchiveListRecord] = []
    var smartListRules: [ArchiveSmartListRuleRecord] = []
    var smartListRuleValues: [ArchiveSmartListRuleValueRecord] = []
    var listMemberships: [ArchiveListMembershipRecord] = []
    var tags: [ArchiveTagRecord] = []
    var tagMemberships: [ArchiveTagMembershipRecord] = []
    var artworks: [ArchiveArtworkRecord] = []
    var credits: [ArchiveCreditRecord] = []
    var reminders: [ArchiveReminderRecord] = []
    var externalReferences: [ArchiveExternalReferenceRecord] = []

    /// Stable ordering makes checksums and source-control diffs reproducible.
    func stablySorted() -> ArchivePayload {
        ArchivePayload(
            items: items.sorted(by: Self.idOrder),
            units: units.sorted(by: Self.idOrder),
            cycles: cycles.sorted(by: Self.idOrder),
            sessions: sessions.sorted(by: Self.idOrder),
            events: events.sorted(by: Self.idOrder),
            quotes: quotes.sorted(by: Self.idOrder),
            lists: lists.sorted(by: Self.idOrder),
            smartListRules: smartListRules.sorted(by: Self.idOrder),
            smartListRuleValues: smartListRuleValues.sorted(by: Self.idOrder),
            listMemberships: listMemberships.sorted(by: Self.idOrder),
            tags: tags.sorted(by: Self.idOrder),
            tagMemberships: tagMemberships.sorted(by: Self.idOrder),
            artworks: artworks.sorted(by: Self.idOrder),
            credits: credits.sorted(by: Self.idOrder),
            reminders: reminders.sorted(by: Self.idOrder),
            externalReferences: externalReferences.sorted(by: Self.idOrder),
        )
    }

    private static func idOrder<T: Identifiable>(_ lhs: T, _ rhs: T) -> Bool where T.ID == UUID {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
