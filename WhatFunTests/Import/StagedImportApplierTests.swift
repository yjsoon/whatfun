import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("Staged import application")
@MainActor
struct StagedImportApplierTests {
    @Test("Repeated Sofa rows become distinct sessions on one canonical item")
    func sofaRowsPreserveEverySession() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let firstDate = Date(timeIntervalSince1970: 1_710_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_710_086_400)
        let rows = [
            mediaRow(rowNumber: 2, consumedAt: firstDate, note: "Matinee"),
            mediaRow(rowNumber: 3, consumedAt: secondDate, note: "With friends"),
        ]
        let batch = StagedImportBatch(
            source: .sofaCSV,
            sourceFilename: "sofa.csv",
            stagedAt: Date(timeIntervalSince1970: 1_720_000_000),
            rows: rows
        )
        let service = StagedImportApplier(
            context: context,
            credentials: InMemoryCredentialStore()
        )

        let report = try await service.apply(
            batch,
            selection: ImportApplicationSelection(acceptedRowIDs: Set(rows.map(\.id)))
        )

        let items = try context.fetch(FetchDescriptor<LibraryItem>())
        let sessions = try context.fetch(FetchDescriptor<ConsumptionSession>())
            .sorted { $0.occurredAt < $1.occurredAt }

        #expect(report.acceptedRows == 2)
        #expect(report.appliedRows == 2)
        #expect(report.createdItems == 1)
        #expect(report.createdSessions == 2)
        #expect(items.count == 1)
        #expect(items.first?.sessionCount == 2)
        #expect(sessions.map(\.occurredAt) == [firstDate, secondDate])
        #expect(Set(sessions.map(\.id)).count == 2)
        #expect(sessions.allSatisfy { $0.source == .sofa })
        #expect(sessions.map(\.note) == ["Matinee", "With friends"])
    }

    @Test("Podcast subscriptions and Overcast episodes retain history without persisting private URLs")
    func podcastImportsProtectPrivateFeed() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let credentials = InMemoryCredentialStore()
        let privateURL = "https://premium.example.com/feed.xml?token=top-secret"
        let publicURL = "https://public.example.com/feed.xml"
        let privateRow = podcastSubscriptionRow(
            rowNumber: 1,
            title: "Private Show",
            feedURL: privateURL
        )
        let publicRow = podcastSubscriptionRow(
            rowNumber: 2,
            title: "Public Show",
            feedURL: publicURL
        )
        let opmlBatch = StagedImportBatch(
            source: .opml,
            sourceFilename: "subscriptions.opml",
            stagedAt: Date(timeIntervalSince1970: 1_720_000_000),
            rows: [privateRow, publicRow]
        )
        let service = StagedImportApplier(context: context, credentials: credentials)

        let subscriptionReport = try await service.apply(
            opmlBatch,
            selection: ImportApplicationSelection(
                acceptedRowIDs: [privateRow.id, publicRow.id]
            )
        )

        let items = try context.fetch(FetchDescriptor<LibraryItem>())
        let privateItem = try #require(items.first { $0.title == "Private Show" })
        let publicItem = try #require(items.first { $0.title == "Public Show" })
        let privateReference = try #require(privateItem.externalReferences?.first {
            $0.providerRaw == "rss" && $0.isActiveFeed
        })
        let publicReference = try #require(publicItem.externalReferences?.first {
            $0.providerRaw == "rss" && $0.isActiveFeed
        })
        let credentialKey = try #require(privateReference.credentialKeychainID)

        #expect(subscriptionReport.createdItems == 2)
        #expect(privateReference.isPrivateFeed)
        #expect(privateReference.canonicalURLString == nil)
        #expect(!privateReference.externalID.contains("top-secret"))
        #expect(await credentials.value(for: credentialKey) == privateURL)
        #expect(!publicReference.isPrivateFeed)
        #expect(publicReference.canonicalURLString == publicURL)

        let playedAt = Date(timeIntervalSince1970: 1_725_000_000)
        let episodeRow = StagedImportRow(
            sourceRowNumber: 2,
            rawFields: ["Played At": ISO8601DateFormatter().string(from: playedAt)],
            proposal: .podcastEpisode(PodcastEpisodeImportProposal(
                podcastTitle: "Private Show",
                feedURL: privateURL,
                episodeTitle: "A Notable Episode",
                episodeURL: "https://premium.example.com/episode?token=top-secret",
                enclosureURL: "https://premium.example.com/audio?token=top-secret",
                publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
                durationMinutes: 60,
                elapsedMinutes: 60,
                completionPercentage: 100,
                isCompleted: true,
                isNotable: true,
                note: "Keep this one"
            )),
            confidence: 0.99
        )
        let overcastBatch = StagedImportBatch(
            source: .overcastAllDataCSV,
            sourceFilename: "overcast.csv",
            stagedAt: Date(timeIntervalSince1970: 1_726_000_000),
            rows: [episodeRow]
        )

        let episodeReport = try await service.apply(
            overcastBatch,
            selection: ImportApplicationSelection(
                acceptedRowIDs: [episodeRow.id],
                targetItemIDsByRowID: [episodeRow.id: privateItem.id]
            )
        )

        let episode = try #require(privateItem.units?.first { $0.unitKind == .podcastEpisode })
        let session = try #require(episode.sessions?.first)
        let completion = try #require(episode.activityEvents?.first { $0.kind == .completed })

        #expect(episodeReport.createdUnits == 1)
        #expect(episodeReport.createdSessions == 1)
        #expect(episode.isNotable)
        #expect(episode.episodeGUID == nil)
        #expect(episode.canonicalURLString == nil)
        #expect(episode.externalReferences?.isEmpty != false)
        #expect(session.occurredAt == playedAt)
        #expect(session.elapsedSeconds == 3_600)
        #expect(session.source == .overcast)
        #expect(completion.effectiveAt == playedAt)
        #expect(completion.source == .overcast)
    }

    @Test("Rows the user rejects do not mutate SwiftData")
    func rejectedRowsStayStaged() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let row = podcastSubscriptionRow(
            rowNumber: 1,
            title: "Not Today",
            feedURL: "https://example.com/feed.xml?token=secret"
        )
        let batch = StagedImportBatch(source: .opml, rows: [row])
        let service = StagedImportApplier(
            context: context,
            credentials: InMemoryCredentialStore()
        )

        let report = try await service.apply(
            batch,
            selection: ImportApplicationSelection(acceptedRowIDs: [])
        )

        #expect(report.acceptedRows == 0)
        #expect(report.appliedRows == 0)
        #expect(report.skippedRows == 1)
        #expect(try context.fetchCount(FetchDescriptor<LibraryItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExternalReference>()) == 0)
    }

    @Test("A path-embedded feed token from an unknown host is stored privately")
    func pathEmbeddedTokenFeedStaysPrivate() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let credentials = InMemoryCredentialStore()
        let tokenURL = "https://example-premium.com/premium/tok_abc123def/feed.rss"
        let row = podcastSubscriptionRow(rowNumber: 1, title: "Premium Show", feedURL: tokenURL)
        let batch = StagedImportBatch(
            source: .opml,
            sourceFilename: "subscriptions.opml",
            stagedAt: Date(timeIntervalSince1970: 1_720_000_000),
            rows: [row]
        )
        let service = StagedImportApplier(context: context, credentials: credentials)

        _ = try await service.apply(
            batch,
            selection: ImportApplicationSelection(acceptedRowIDs: [row.id])
        )

        let item = try #require(try context.fetch(FetchDescriptor<LibraryItem>()).first)
        let reference = try #require(item.externalReferences?.first {
            $0.providerRaw == "rss" && $0.isActiveFeed
        })
        let key = try #require(reference.credentialKeychainID)

        #expect(reference.isPrivateFeed)
        #expect(reference.canonicalURLString == nil)
        #expect(reference.externalID.hasPrefix("private."))
        #expect(!reference.externalID.contains("tok_abc123def"))
        #expect(await credentials.value(for: key) == tokenURL)
    }

    @Test("An imported private feed URL never appears in a portable export")
    func importedPrivateFeedIsRedactedInExports() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let credentials = InMemoryCredentialStore()
        let tokenURL = "https://example-premium.com/premium/tok_abc123def/feed.rss"
        let row = podcastSubscriptionRow(rowNumber: 1, title: "Premium Show", feedURL: tokenURL)
        let batch = StagedImportBatch(source: .opml, rows: [row])
        let applier = StagedImportApplier(context: context, credentials: credentials)
        _ = try await applier.apply(
            batch,
            selection: ImportApplicationSelection(acceptedRowIDs: [row.id])
        )

        let bridge = SwiftDataArchiveBridge(context: context, credentials: credentials)
        let snapshot = try await bridge.snapshot()

        let plainPayload = try JSONEncoder().encode(snapshot.payload)
        #expect(!String(decoding: plainPayload, as: UTF8.self).contains("tok_abc123def"))

        let package = try PortableArchiveBuilder.makePackage(
            payload: snapshot.payload,
            generator: "WhatFunTests/1"
        )
        let combined = package.files.values.compactMap { String(data: $0, encoding: .utf8) }.joined()
        #expect(!combined.contains("tok_abc123def"))
        #expect(snapshot.privatePayload?.privateFeedSecrets.first?.feedURL == tokenURL)
    }

    @Test("A verifiably clean public feed stays public through import")
    func cleanPublicFeedStaysPublic() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let publicURL = "https://feeds.megaphone.fm/design-details"
        let row = podcastSubscriptionRow(rowNumber: 1, title: "Design Details", feedURL: publicURL)
        let batch = StagedImportBatch(source: .opml, rows: [row])
        let service = StagedImportApplier(
            context: context,
            credentials: InMemoryCredentialStore()
        )

        _ = try await service.apply(
            batch,
            selection: ImportApplicationSelection(acceptedRowIDs: [row.id])
        )

        let item = try #require(try context.fetch(FetchDescriptor<LibraryItem>()).first)
        let reference = try #require(item.externalReferences?.first {
            $0.providerRaw == "rss" && $0.isActiveFeed
        })
        #expect(!reference.isPrivateFeed)
        #expect(reference.canonicalURLString == publicURL)
        #expect(reference.credentialKeychainID == nil)
    }

    private func mediaRow(
        rowNumber: Int,
        consumedAt: Date,
        note: String
    ) -> StagedImportRow {
        StagedImportRow(
            sourceRowNumber: rowNumber,
            rawFields: ["Title": "Perfect Days"],
            proposal: .mediaItem(MediaItemImportProposal(
                title: "Perfect Days",
                mediaKind: .movie,
                subtitle: nil,
                creators: [],
                releaseDate: nil,
                addedAt: nil,
                status: .inProgress,
                rating: nil,
                isFavorite: false,
                startDate: nil,
                completionDate: nil,
                note: nil,
                listNames: [],
                tags: [],
                history: ImportConsumptionProposal(
                    consumedAt: consumedAt,
                    completedAt: nil,
                    isCompletion: false,
                    status: .inProgress,
                    rating: nil,
                    progress: ImportProgressProposal(
                        currentPage: nil,
                        totalPages: nil,
                        chapter: nil,
                        elapsedMinutes: 45,
                        totalRuntimeMinutes: 124,
                        seasonNumber: nil,
                        episodeNumber: nil,
                        volumeNumber: nil,
                        issueNumber: nil,
                        playtimeMinutes: nil,
                        completionPercentage: 36
                    ),
                    note: note
                ),
                externalIdentifiers: [:]
            )),
            confidence: 0.99
        )
    }

    private func podcastSubscriptionRow(
        rowNumber: Int,
        title: String,
        feedURL: String
    ) -> StagedImportRow {
        StagedImportRow(
            sourceRowNumber: rowNumber,
            rawFields: ["title": title, "xmlUrl": feedURL],
            proposal: .podcastSubscription(PodcastSubscriptionImportProposal(
                title: title,
                author: "Example Studio",
                feedURL: feedURL,
                websiteURL: nil,
                listeningStyle: .keepAround,
                status: .following,
                categoryPath: ["Favorites"]
            )),
            confidence: 0.99
        )
    }
}
