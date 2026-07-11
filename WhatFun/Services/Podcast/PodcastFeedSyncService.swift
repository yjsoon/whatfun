import Foundation
import SwiftData

struct PodcastFeedSyncReport: Sendable, Equatable {
    let addedEpisodes: Int
    let updatedEpisodes: Int
    let wasModified: Bool
}

enum PodcastFeedSyncError: Error, Equatable, LocalizedError {
    case notPodcast
    case missingFeed
    case missingPrivateCredential

    var errorDescription: String? {
        switch self {
        case .notPodcast:
            "Only podcast items can refresh an RSS feed."
        case .missingFeed:
            "This podcast does not have an active RSS feed."
        case .missingPrivateCredential:
            "The private feed address is no longer available in Keychain."
        }
    }

    var recoverySuggestion: String? {
        "Edit the podcast to update its feed address, or keep tracking episodes manually."
    }
}

@MainActor
struct PodcastFeedSyncService {
    let context: ModelContext
    let credentials: any CredentialStoring
    let refresher: any PodcastFeedRefreshing

    func refresh(_ item: LibraryItem) async throws -> PodcastFeedSyncReport {
        guard item.mediaKind == .podcast else {
            throw PodcastFeedSyncError.notPodcast
        }
        guard let reference = (item.externalReferences ?? []).first(where: {
            $0.providerRaw == MetadataProviderID.rss.rawValue && $0.isActiveFeed
        }) else {
            throw PodcastFeedSyncError.missingFeed
        }

        let feedURL: URL
        if reference.isPrivateFeed {
            guard let key = reference.credentialKeychainID,
                  let value = try await credentials.value(for: key),
                  let url = URL(string: value) else {
                throw PodcastFeedSyncError.missingPrivateCredential
            }
            feedURL = url
        } else {
            guard let value = reference.canonicalURLString, let url = URL(string: value) else {
                throw PodcastFeedSyncError.missingFeed
            }
            feedURL = url
        }

        let result = try await refresher.refresh(
            PodcastFeedRefreshRequest(
                feedURL: feedURL,
                eTag: reference.etag,
                lastModified: reference.lastModified
            )
        )

        switch result {
        case let .notModified(eTag, lastModified):
            reference.etag = eTag
            reference.lastModified = lastModified
            reference.lastFetchedAt = .now
            reference.updatedAt = .now
            try context.save()
            return PodcastFeedSyncReport(addedEpisodes: 0, updatedEpisodes: 0, wasModified: false)

        case let .updated(feed, eTag, lastModified):
            let report = merge(feed, into: item, privateFeed: reference.isPrivateFeed)
            reference.etag = eTag
            reference.lastModified = lastModified
            reference.lastFetchedAt = .now
            reference.updatedAt = .now
            item.metadataLastRefreshedAt = .now
            item.updatedAt = .now
            ActivityProjection.rebuild(item)
            try context.save()
            return report
        }
    }

    private func merge(
        _ feed: PodcastFeed,
        into item: LibraryItem,
        privateFeed: Bool
    ) -> PodcastFeedSyncReport {
        if item.creatorLine?.isEmpty != false { item.creatorLine = feed.author }
        if item.summary?.isEmpty != false { item.summary = feed.summary }
        if item.languageCode?.isEmpty != false { item.languageCode = feed.languageCode }

        var units = item.units ?? []
        let existingByGUID = Dictionary(
            units
                .filter { $0.unitKind == .podcastEpisode }
                .compactMap { unit in unit.episodeGUIDHash.map { ($0, unit) } },
            uniquingKeysWith: { first, _ in first }
        )
        var added = 0
        var updated = 0

        for (index, episode) in feed.episodes.enumerated() {
            let guidHash = ArtworkRepository.hash(episode.id)
            let unit: ContentUnit
            if let existing = existingByGUID[guidHash] {
                unit = existing
                updated += 1
            } else {
                unit = ContentUnit(
                    item: item,
                    kind: .podcastEpisode,
                    title: episode.title,
                    sortOrder: index
                )
                context.insert(unit)
                units.append(unit)
                added += 1
            }

            unit.episodeGUID = privateFeed ? nil : episode.id
            unit.episodeGUIDHash = guidHash
            unit.title = episode.title
            unit.summary = episode.summary
            unit.publishedAt = episode.publishedAt
            unit.releaseDate = episode.publishedAt
            unit.durationSeconds = episode.durationSeconds
            unit.seasonNumber = episode.seasonNumber
            unit.episodeNumber = episode.episodeNumber
            unit.numberValue = episode.episodeNumber.map(Double.init)
            unit.sortOrder = index
            unit.canonicalURLString = privateFeed ? nil : episode.webpageURL?.absoluteString
            unit.updatedAt = .now

            if !privateFeed,
               unit.preferredArtworkID == nil,
               let imageURL = episode.imageURL {
                let artwork = ArtworkAsset(
                    ownerItem: item,
                    unit: unit,
                    kind: .providerRemote,
                    remoteURLString: imageURL.absoluteString
                )
                artwork.cacheKey = ArtworkRepository.hash(imageURL.absoluteString)
                artwork.providerRaw = MetadataProviderID.rss.rawValue
                artwork.aspectRatio = 1
                context.insert(artwork)
                unit.artworkAssets = (unit.artworkAssets ?? []) + [artwork]
                unit.preferredArtworkID = artwork.id
            }
        }

        item.units = units
        return PodcastFeedSyncReport(
            addedEpisodes: added,
            updatedEpisodes: updated,
            wasModified: true
        )
    }
}
