import Foundation

nonisolated enum ImportSourceFormat: String, Codable, Sendable {
    case opml
    case overcastAllDataCSV = "overcast_all_data_csv"
    case sofaCSV = "sofa_csv"
}

nonisolated enum ImportedRecordKind: String, Codable, Sendable {
    case mediaItem = "media_item"
    case podcastSubscription = "podcast_subscription"
    case podcastEpisode = "podcast_episode"
    case unresolved
}

nonisolated enum ImportDisposition: String, Codable, Sendable {
    case ready
    case needsReview = "needs_review"
    case manualEntry = "manual_entry"
    case skipped
}

nonisolated enum ImportWarningSeverity: String, Codable, Sendable {
    case information
    case warning
}

nonisolated enum ImportWarningCode: String, Codable, Sendable {
    case duplicateSourceRow = "duplicate_source_row"
    case missingTitle = "missing_title"
    case unknownMediaType = "unknown_media_type"
    case ambiguousDate = "ambiguous_date"
    case unparseableDate = "unparseable_date"
    case normalizedRating = "normalized_rating"
    case invalidRating = "invalid_rating"
    case invalidURL = "invalid_url"
    case partialMetadata = "partial_metadata"
    case inferredValue = "inferred_value"
    case unsupportedField = "unsupported_field"
}

nonisolated struct ImportWarning: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = .init()
    var code: ImportWarningCode
    var severity: ImportWarningSeverity
    var message: String
    var field: String?
    var rawValue: String?
}

nonisolated struct ImportAmbiguity: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = .init()
    var field: String
    var message: String
    /// Human-readable alternatives for review; the adapter never silently picks one.
    var candidates: [String]
}

nonisolated struct ImportMatchCandidate: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var mediaKind: ArchiveMediaKind
    var confidence: Double
    var explanation: String
}

nonisolated struct ImportProgressProposal: Codable, Equatable, Sendable {
    var currentPage: Int?
    var totalPages: Int?
    var chapter: String?
    var elapsedMinutes: Double?
    var totalRuntimeMinutes: Double?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var volumeNumber: Int?
    var issueNumber: String?
    var playtimeMinutes: Double?
    var completionPercentage: Double?
}

nonisolated struct ImportConsumptionProposal: Codable, Equatable, Sendable {
    var consumedAt: Date?
    var completedAt: Date?
    var isCompletion: Bool
    var status: ArchiveLifecycleStatus?
    var rating: Double?
    var progress: ImportProgressProposal?
    var note: String?
}

nonisolated struct MediaItemImportProposal: Codable, Equatable, Sendable {
    var title: String
    var mediaKind: ArchiveMediaKind?
    var subtitle: String?
    var creators: [String] = []
    var releaseDate: Date?
    var addedAt: Date?
    var status: ArchiveLifecycleStatus?
    var rating: Double?
    var isFavorite: Bool = false
    var startDate: Date?
    var completionDate: Date?
    var note: String?
    var listNames: [String] = []
    var tags: [String] = []
    var history: ImportConsumptionProposal?
    var externalIdentifiers: [String: String] = [:]
}

nonisolated struct PodcastSubscriptionImportProposal: Codable, Equatable, Sendable {
    var title: String
    var author: String?
    var feedURL: String?
    var websiteURL: String?
    var listeningStyle: ArchivePodcastListeningStyle = .keepAround
    var status: ArchiveLifecycleStatus = .following
    var categoryPath: [String] = []
}

nonisolated struct PodcastEpisodeImportProposal: Codable, Equatable, Sendable {
    var podcastTitle: String?
    var feedURL: String?
    var episodeTitle: String
    var episodeURL: String?
    var enclosureURL: String?
    var publishedAt: Date?
    var durationMinutes: Double?
    var elapsedMinutes: Double?
    var completionPercentage: Double?
    var isCompleted: Bool
    var isNotable: Bool
    var note: String?
}

nonisolated struct UnresolvedImportProposal: Codable, Equatable, Sendable {
    var bestTitle: String?
    var reason: String
}

nonisolated enum ImportProposal: Codable, Equatable, Sendable {
    case mediaItem(MediaItemImportProposal)
    case podcastSubscription(PodcastSubscriptionImportProposal)
    case podcastEpisode(PodcastEpisodeImportProposal)
    case unresolved(UnresolvedImportProposal)

    var kind: ImportedRecordKind {
        switch self {
        case .mediaItem: .mediaItem
        case .podcastSubscription: .podcastSubscription
        case .podcastEpisode: .podcastEpisode
        case .unresolved: .unresolved
        }
    }
}

nonisolated struct StagedImportRow: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = .init()
    var sourceRowNumber: Int
    var rawFields: [String: String]
    var proposal: ImportProposal
    var confidence: Double
    var disposition: ImportDisposition
    var warnings: [ImportWarning] = []
    var ambiguities: [ImportAmbiguity] = []
    var matchCandidates: [ImportMatchCandidate] = []

    init(
        id: UUID = UUID(),
        sourceRowNumber: Int,
        rawFields: [String: String],
        proposal: ImportProposal,
        confidence: Double,
        warnings: [ImportWarning] = [],
        ambiguities: [ImportAmbiguity] = [],
        matchCandidates: [ImportMatchCandidate] = []
    ) {
        self.id = id
        self.sourceRowNumber = sourceRowNumber
        self.rawFields = rawFields
        self.proposal = proposal
        self.confidence = min(max(confidence, 0), 1)
        self.warnings = warnings
        self.ambiguities = ambiguities
        self.matchCandidates = matchCandidates
        if case .unresolved = proposal {
            disposition = .manualEntry
        } else if confidence >= 0.85, ambiguities.isEmpty {
            disposition = .ready
        } else {
            disposition = .needsReview
        }
    }
}

/// Transient review state. OPML proposals can contain a private feed URL and must not be persisted
/// or logged unencrypted before the accepted URL moves into Keychain.
nonisolated struct StagedImportBatch: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = .init()
    var source: ImportSourceFormat
    var sourceFilename: String?
    var stagedAt: Date = .now
    var rows: [StagedImportRow]
    var warnings: [ImportWarning] = []
}

nonisolated enum ImportStagingError: Error, Equatable, Sendable, LocalizedError {
    case invalidData(String)
    case unsupportedFormat(String)
    case tooManyRows(limit: Int)
    case fileTooLarge(limitBytes: Int)
    case parserFailure(String)

    var errorDescription: String? {
        switch self {
        case let .invalidData(message): message
        case let .unsupportedFormat(message): message
        case let .tooManyRows(limit): "The import exceeds the safety limit of \(limit) rows."
        case let .fileTooLarge(limitBytes): "The import exceeds the safety limit of \(limitBytes) bytes."
        case let .parserFailure(message): message
        }
    }
}
