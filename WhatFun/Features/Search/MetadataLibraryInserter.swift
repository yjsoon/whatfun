import Foundation
import SwiftData

@MainActor
struct MetadataInsertionResult {
    let item: LibraryItem
    let wasInserted: Bool
}

@MainActor
struct MetadataLibraryInserter {
    private let context: ModelContext
    private let credentials: any CredentialStoring

    init(context: ModelContext, credentials: any CredentialStoring) {
        self.context = context
        self.credentials = credentials
    }

    func insert(
        result: MetadataSearchResult,
        details: MetadataItemDetails?,
        attribution: MetadataAttribution?,
        at date: Date = .now
    ) async throws -> MetadataInsertionResult {
        let draft = MetadataDomainMapper.makeDraft(
            result: result,
            details: details,
            attribution: attribution
        )

        if let existing = try existingItem(for: draft.duplicateKey) {
            return MetadataInsertionResult(item: existing, wasInserted: false)
        }

        let itemID = UUID()
        let privateCredentialKey = try await storePrivateFeedIfNeeded(
            draft.podcastFeed,
            itemID: itemID
        )
        let item = LibraryItem(
            id: itemID,
            mediaKind: draft.mediaKind,
            title: draft.title.isEmpty ? "Untitled" : draft.title,
            subtitle: draft.subtitle,
            createdAt: date
        )
        item.summary = draft.summary
        item.creatorLine = draft.creators.isEmpty ? nil : draft.creators.joined(separator: ", ")
        item.releaseYear = draft.releaseYear
        item.pageCount = draft.pageCount
        item.runtimeSeconds = draft.runtimeSeconds
        item.status = .planned
        item.metadataLastRefreshedAt = date
        item.updatedAt = date
        context.insert(item)

        var newlyCreatedFacets = [Facet]()
        var newlyCreatedMemberships = [ItemFacetMembership]()
        do {
            attachProviderReference(to: item, draft: draft, at: date)
            attachPodcastFeedReference(
                to: item,
                feed: draft.podcastFeed,
                privateCredentialKey: privateCredentialKey,
                at: date
            )
            attachArtwork(to: item, draft: draft, at: date)
            attachCredits(to: item, names: draft.creators, at: date)
            try attachFacets(
                to: item,
                facets: draft.facets,
                at: date,
                newlyCreatedFacets: &newlyCreatedFacets,
                newlyCreatedMemberships: &newlyCreatedMemberships
            )
            attachCreatedEvent(to: item, at: date)
            try context.save()
            return MetadataInsertionResult(item: item, wasInserted: true)
        } catch {
            for membership in newlyCreatedMemberships {
                context.delete(membership)
            }
            context.delete(item)
            for facet in newlyCreatedFacets {
                context.delete(facet)
            }
            if let privateCredentialKey {
                try? await credentials.removeValue(for: privateCredentialKey)
            }
            throw error
        }
    }

    private func existingItem(for key: MetadataDuplicateKey) throws -> LibraryItem? {
        let providerRaw = key.providerRaw
        let descriptor = FetchDescriptor<ExternalReference>(
            predicate: #Predicate { reference in
                reference.providerRaw == providerRaw
            }
        )
        return try context.fetch(descriptor)
            .first {
                key.matches(
                    providerRaw: $0.providerRaw,
                    recordKindRaw: $0.recordKindRaw,
                    externalID: $0.externalID
                )
            }?
            .ownerItem
    }

    private func storePrivateFeedIfNeeded(
        _ feed: PodcastFeedDraft?,
        itemID: UUID
    ) async throws -> String? {
        guard let feed, feed.privacy == .privateCredential else { return nil }
        let key = "podcast-feed.\(itemID.uuidString.lowercased())"
        try await credentials.set(feed.url.absoluteString, for: key)
        return key
    }

    private func attachProviderReference(
        to item: LibraryItem,
        draft: MetadataItemDraft,
        at date: Date
    ) {
        let reference = ExternalReference(
            ownerItem: item,
            providerRaw: draft.duplicateKey.providerRaw,
            recordKindRaw: draft.duplicateKey.recordKindRaw,
            externalID: draft.duplicateKey.externalID,
            canonicalURLString: draft.sourceURL?.absoluteString,
            createdAt: date
        )
        reference.lastFetchedAt = date
        reference.attributionText = draft.attribution?.label
        reference.attributionURLString = draft.attribution?.url.absoluteString
        context.insert(reference)
        if !(item.externalReferences ?? []).contains(where: { $0.id == reference.id }) {
            item.externalReferences = (item.externalReferences ?? []) + [reference]
        }
    }

    private func attachPodcastFeedReference(
        to item: LibraryItem,
        feed: PodcastFeedDraft?,
        privateCredentialKey: String?,
        at date: Date
    ) {
        guard let feed else { return }
        let isPrivate = feed.privacy == .privateCredential
        let reference = ExternalReference(
            ownerItem: item,
            providerRaw: MetadataProviderID.rss.rawValue,
            recordKindRaw: "podcastFeed",
            externalID: isPrivate ? "private.\(item.id.uuidString.lowercased())" : feed.opaqueID,
            canonicalURLString: isPrivate ? nil : feed.url.absoluteString,
            createdAt: date
        )
        reference.isActiveFeed = true
        reference.isPrivateFeed = isPrivate
        reference.credentialKeychainID = privateCredentialKey
        context.insert(reference)
        if !(item.externalReferences ?? []).contains(where: { $0.id == reference.id }) {
            item.externalReferences = (item.externalReferences ?? []) + [reference]
        }
    }

    private func attachArtwork(
        to item: LibraryItem,
        draft: MetadataItemDraft,
        at date: Date
    ) {
        guard let url = draft.artworkURL else { return }
        let artwork = ArtworkAsset(
            ownerItem: item,
            kind: .providerRemote,
            remoteURLString: url.absoluteString,
            createdAt: date
        )
        artwork.cacheKey = ArtworkRepository.hash(url.absoluteString)
        artwork.providerRaw = draft.provider.rawValue
        artwork.attributionText = draft.attribution?.label
        artwork.attributionURLString = draft.attribution?.url.absoluteString
        if draft.mediaKind == .podcast {
            artwork.aspectRatio = 1
        }
        context.insert(artwork)
        if !(item.artworkAssets ?? []).contains(where: { $0.id == artwork.id }) {
            item.artworkAssets = (item.artworkAssets ?? []) + [artwork]
        }
        item.preferredArtworkID = artwork.id
    }

    private func attachCredits(to item: LibraryItem, names: [String], at date: Date) {
        let credits = names.enumerated().map { index, name in
            Credit(
                ownerItem: item,
                name: name,
                roleRaw: "creator",
                sortOrder: index,
                createdAt: date
            )
        }
        for credit in credits {
            context.insert(credit)
        }
        let missingCredits = credits.filter { credit in
            !(item.credits ?? []).contains(where: { $0.id == credit.id })
        }
        if !missingCredits.isEmpty {
            item.credits = (item.credits ?? []) + missingCredits
        }
    }

    private func attachFacets(
        to item: LibraryItem,
        facets: [MetadataFacetDraft],
        at date: Date,
        newlyCreatedFacets: inout [Facet],
        newlyCreatedMemberships: inout [ItemFacetMembership]
    ) throws {
        var memberships = [ItemFacetMembership]()

        for (index, facetDraft) in facets.enumerated() {
            let kindRaw = facetDraft.kind.rawValue
            let normalizedName = LibraryItem.normalize(facetDraft.name)
            var descriptor = FetchDescriptor<Facet>(
                predicate: #Predicate { facet in
                    facet.kindRaw == kindRaw && facet.normalizedName == normalizedName
                }
            )
            descriptor.fetchLimit = 1

            let facet: Facet
            if let existing = try context.fetch(descriptor).first {
                facet = existing
            } else {
                facet = Facet(kind: facetDraft.kind, name: facetDraft.name, createdAt: date)
                context.insert(facet)
                newlyCreatedFacets.append(facet)
            }

            let membership = ItemFacetMembership(
                item: item,
                facet: facet,
                source: .metadataProvider,
                sortOrder: index,
                createdAt: date
            )
            context.insert(membership)
            memberships.append(membership)
            newlyCreatedMemberships.append(membership)
            if !(facet.memberships ?? []).contains(where: { $0.id == membership.id }) {
                facet.memberships = (facet.memberships ?? []) + [membership]
            }
        }

        let missingMemberships = memberships.filter { membership in
            !(item.facetMemberships ?? []).contains(where: { $0.id == membership.id })
        }
        if !missingMemberships.isEmpty {
            item.facetMemberships = (item.facetMemberships ?? []) + missingMemberships
        }
    }

    private func attachCreatedEvent(to item: LibraryItem, at date: Date) {
        let event = ActivityEvent(
            item: item,
            scope: .item,
            kind: .created,
            toStatus: .planned,
            effectiveAt: date,
            source: .metadataProvider
        )
        context.insert(event)
        if !(item.activityEvents ?? []).contains(where: { $0.id == event.id }) {
            item.activityEvents = (item.activityEvents ?? []) + [event]
        }
    }
}
