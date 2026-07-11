import Foundation

enum MediaKind: String, CaseIterable, Codable, Sendable {
    case book
    case comic
    case movie
    case tvShow
    case game
    case podcast
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ContentUnitKind: String, CaseIterable, Codable, Sendable {
    case tvSeason
    case tvEpisode
    case comicVolume
    case comicIssue
    case podcastEpisode
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ConsumptionStatus: String, CaseIterable, Codable, Sendable {
    case planned
    case inProgress
    case paused
    case completed
    case dropped
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ConsumptionCycleKind: String, CaseIterable, Codable, Sendable {
    case initial
    case repeatConsumption
    case installmentContinuation
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ActivityEventKind: String, CaseIterable, Codable, Sendable {
    case created
    case statusSet
    case started
    case completed
    case reopened
    case archived
    case restored
    case trashed
    case recovered
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ActivityScope: String, CaseIterable, Codable, Sendable {
    case item
    case cycle
    case unit
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum RecordSource: String, CaseIterable, Codable, Sendable {
    case manual
    case metadataProvider
    case portableImport
    case sofa
    case overcast
    case opml
    case repair
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum PodcastFollowState: String, CaseIterable, Codable, Sendable {
    case following
    case paused
    case completed
    case dropped
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum PodcastListeningStyle: String, CaseIterable, Codable, Sendable {
    case everyEpisode
    case selectedEpisodes
    case keepAround
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum FacetKind: String, CaseIterable, Codable, Sendable {
    case tag
    case genre
    case platform
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ListKind: String, CaseIterable, Codable, Sendable {
    case manual
    case smart
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum SmartListMatchMode: String, CaseIterable, Codable, Sendable {
    case all
    case any
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ArtworkKind: String, CaseIterable, Codable, Sendable {
    case providerRemote
    case userImage
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}

enum ReminderState: String, CaseIterable, Codable, Sendable {
    case pending
    case delivered
    case cancelled
    case unknown

    nonisolated static func value(for rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .unknown
    }
}
