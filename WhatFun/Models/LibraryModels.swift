import Foundation
import SwiftData

@Model
final class LibraryItem {
    #Index<LibraryItem>(
        [\.normalizedTitle],
        [\.mediaKindRaw, \.statusProjectionRaw],
        [\.lastSessionAt],
        [\.lastCompletedAt],
        [\.trashedAt]
    )

    var id: UUID = UUID()
    var mediaKindRaw: String = MediaKind.book.rawValue
    var title: String = ""
    var normalizedTitle: String = ""
    var sortTitle: String = ""
    var subtitle: String?
    var originalTitle: String?
    var summary: String?
    var creatorLine: String?
    var releaseDate: Date?
    var releaseYear: Int?
    var languageCode: String?
    var pageCount: Int?
    var runtimeSeconds: Int?
    var comment: String?
    var isFavorite: Bool = false

    var podcastFollowStateRaw: String?
    var podcastListeningStyleRaw: String?

    /// A user-entered rating where 1...10 represents 0.5...5 stars.
    var ratingOverrideHalfSteps: Int?
    /// A rebuildable projection, such as the average of season ratings.
    var derivedRatingHalfSteps: Int?
    /// The query-friendly effective value. It is always rebuildable.
    var effectiveRatingHalfSteps: Int?

    var statusProjectionRaw: String = ConsumptionStatus.planned.rawValue
    var firstStartedAt: Date?
    var lastCompletedAt: Date?
    var lastSessionAt: Date?
    var progressFraction: Double?
    var cycleCount: Int = 0
    var repeatCount: Int = 0
    var sessionCount: Int = 0
    var hasNewInstallment: Bool = false

    var userEditedFieldMask: Int64 = 0
    var metadataLastRefreshedAt: Date?
    var preferredArtworkID: UUID?

    var archivedAt: Date?
    var trashedAt: Date?
    var purgeAfter: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \ContentUnit.item)
    var units: [ContentUnit]?

    @Relationship(deleteRule: .cascade, inverse: \ConsumptionCycle.item)
    var cycles: [ConsumptionCycle]?

    @Relationship(deleteRule: .cascade, inverse: \ActivityEvent.item)
    var activityEvents: [ActivityEvent]?

    @Relationship(deleteRule: .cascade, inverse: \ArtworkAsset.ownerItem)
    var artworkAssets: [ArtworkAsset]?

    @Relationship(deleteRule: .cascade, inverse: \ExternalReference.ownerItem)
    var externalReferences: [ExternalReference]?

    @Relationship(deleteRule: .cascade, inverse: \Credit.ownerItem)
    var credits: [Credit]?

    @Relationship(deleteRule: .nullify, inverse: \ItemFacetMembership.item)
    var facetMemberships: [ItemFacetMembership]?

    @Relationship(deleteRule: .nullify, inverse: \ListMembership.item)
    var listMemberships: [ListMembership]?

    @Relationship(deleteRule: .cascade, inverse: \StartReminder.item)
    var reminders: [StartReminder]?

    init(
        id: UUID = UUID(),
        mediaKind: MediaKind,
        title: String,
        subtitle: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.mediaKindRaw = mediaKind.rawValue
        self.title = title
        self.normalizedTitle = Self.normalize(title)
        self.sortTitle = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.updatedAt = createdAt

        if mediaKind == .podcast {
            self.podcastFollowStateRaw = PodcastFollowState.following.rawValue
            self.podcastListeningStyleRaw = PodcastListeningStyle.selectedEpisodes.rawValue
        }
    }

    var mediaKind: MediaKind {
        get { MediaKind.value(for: mediaKindRaw) }
        set { mediaKindRaw = newValue.rawValue }
    }

    var status: ConsumptionStatus {
        get { ConsumptionStatus.value(for: statusProjectionRaw) }
        set { statusProjectionRaw = newValue.rawValue }
    }

    var podcastFollowState: PodcastFollowState? {
        get { podcastFollowStateRaw.map(PodcastFollowState.value(for:)) }
        set { podcastFollowStateRaw = newValue?.rawValue }
    }

    var podcastListeningStyle: PodcastListeningStyle? {
        get { podcastListeningStyleRaw.map(PodcastListeningStyle.value(for:)) }
        set { podcastListeningStyleRaw = newValue?.rawValue }
    }

    var isArchived: Bool { archivedAt != nil }
    var isTrashed: Bool { trashedAt != nil }

    var displayRating: Double? {
        effectiveRatingHalfSteps.map { Double($0) / 2 }
    }

    func setTitle(_ newValue: String) {
        title = newValue
        normalizedTitle = Self.normalize(newValue)
        updatedAt = .now
    }

    func setRating(halfSteps: Int?) {
        ratingOverrideHalfSteps = halfSteps.map { min(max($0, 1), 10) }
        effectiveRatingHalfSteps = ratingOverrideHalfSteps ?? derivedRatingHalfSteps
        updatedAt = .now
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

@Model
final class ContentUnit {
    #Index<ContentUnit>(
        [\.rootItemID, \.unitKindRaw, \.sortOrder],
        [\.publishedAt],
        [\.episodeGUIDHash]
    )

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var parentUnitID: UUID?
    var unitKindRaw: String = ContentUnitKind.unknown.rawValue
    var sortOrder: Int = 0
    var numberValue: Double?
    var numberLabel: String?
    var title: String = ""
    var summary: String?
    var releaseDate: Date?
    var pageCount: Int?
    var durationSeconds: Int?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeGUID: String?
    var episodeGUIDHash: String?
    var canonicalURLString: String?
    var publishedAt: Date?
    var isNotable: Bool = false
    var comment: String?
    var ratingHalfSteps: Int?

    var statusProjectionRaw: String = ConsumptionStatus.planned.rawValue
    var firstStartedAt: Date?
    var lastCompletedAt: Date?
    var lastSessionAt: Date?
    var progressFraction: Double?
    var sessionCount: Int = 0

    var userEditedFieldMask: Int64 = 0
    var preferredArtworkID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var item: LibraryItem?
    var parent: ContentUnit?

    @Relationship(deleteRule: .nullify, inverse: \ContentUnit.parent)
    var children: [ContentUnit]?

    @Relationship(deleteRule: .nullify, inverse: \ConsumptionCycle.targetUnit)
    var cycles: [ConsumptionCycle]?

    @Relationship(deleteRule: .nullify, inverse: \ConsumptionSession.targetUnit)
    var sessions: [ConsumptionSession]?

    @Relationship(deleteRule: .nullify, inverse: \ActivityEvent.targetUnit)
    var activityEvents: [ActivityEvent]?

    @Relationship(deleteRule: .cascade, inverse: \NotableQuote.episode)
    var notableQuotes: [NotableQuote]?

    @Relationship(deleteRule: .nullify, inverse: \ArtworkAsset.unit)
    var artworkAssets: [ArtworkAsset]?

    @Relationship(deleteRule: .nullify, inverse: \ExternalReference.unit)
    var externalReferences: [ExternalReference]?

    @Relationship(deleteRule: .nullify, inverse: \Credit.unit)
    var credits: [Credit]?

    init(
        id: UUID = UUID(),
        item: LibraryItem,
        kind: ContentUnitKind,
        title: String,
        sortOrder: Int = 0,
        parent: ContentUnit? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rootItemID = item.id
        self.parentUnitID = parent?.id
        self.unitKindRaw = kind.rawValue
        self.title = title
        self.sortOrder = sortOrder
        self.item = item
        self.parent = parent
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var unitKind: ContentUnitKind {
        get { ContentUnitKind.value(for: unitKindRaw) }
        set { unitKindRaw = newValue.rawValue }
    }

    var status: ConsumptionStatus {
        get { ConsumptionStatus.value(for: statusProjectionRaw) }
        set { statusProjectionRaw = newValue.rawValue }
    }

    var rating: Double? {
        ratingHalfSteps.map { Double($0) / 2 }
    }

    func setRating(halfSteps: Int?) {
        ratingHalfSteps = halfSteps.map { min(max($0, 1), 10) }
        updatedAt = .now
    }
}
