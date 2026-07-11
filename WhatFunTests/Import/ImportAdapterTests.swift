import Foundation
import Testing
@testable import WhatFun

@Suite("Podcast and legacy import staging")
struct ImportAdapterTests {
    @Test("OPML preserves categories, ignores duplicates, and stages invalid feeds for review")
    func opmlStaging() throws {
        let data = try ImportFixture.data(named: "subscriptions.opml")
        let batch = try OPMLPodcastImporter().stage(data, sourceFilename: "subscriptions.opml")

        #expect(batch.source == .opml)
        #expect(batch.rows.count == 2)
        #expect(batch.warnings.contains { $0.code == .duplicateSourceRow })

        let first = try #require(batch.rows.first)
        guard case let .podcastSubscription(subscription) = first.proposal else {
            Issue.record("Expected a podcast subscription")
            return
        }
        #expect(subscription.title == "Swift by Sundell")
        #expect(subscription.categoryPath == ["Technology"])
        #expect(first.disposition == .ready)

        let invalid = try #require(batch.rows.last)
        #expect(invalid.disposition == .needsReview)
        #expect(invalid.warnings.contains { $0.code == .invalidURL })
        #expect(!invalid.ambiguities.isEmpty)
    }

    @Test("Overcast keeps episode progress, completion, stars, and ambiguous dates")
    func overcastStaging() throws {
        let data = try ImportFixture.data(named: "overcast_all_data.csv")
        let batch = try OvercastAllDataImporter().stage(data, sourceFilename: "All Data.csv")

        #expect(batch.rows.count == 3)
        let first = batch.rows[0]
        guard case let .podcastEpisode(episode) = first.proposal else {
            Issue.record("Expected an episode proposal")
            return
        }
        #expect(episode.podcastTitle == "99% Invisible")
        #expect(episode.episodeTitle == "A City, Reconsidered")
        #expect(episode.durationMinutes == 60)
        #expect(episode.elapsedMinutes == 30)
        #expect(episode.completionPercentage == 50)
        #expect(episode.isNotable)
        #expect(episode.note?.contains("Worth revisiting") == true)
        #expect(first.disposition == .ready)

        let ambiguous = batch.rows[1]
        #expect(ambiguous.disposition == .needsReview)
        #expect(ambiguous.ambiguities.contains { $0.field == "Published" })
        guard case let .podcastEpisode(completedEpisode) = ambiguous.proposal else {
            Issue.record("Expected an episode proposal")
            return
        }
        #expect(completedEpisode.isCompleted)

        #expect(batch.rows[2].disposition == .manualEntry)
    }

    @Test("Sofa leaves repeated titles as separate history and normalizes known fields")
    func sofaStaging() throws {
        let data = try ImportFixture.data(named: "sofa_export.csv")
        let batch = try SofaCSVImporter().stage(data, sourceFilename: "Sofa.csv")

        #expect(batch.rows.count == 6)
        let duneRows = batch.rows.filter { row in
            guard case let .mediaItem(proposal) = row.proposal else { return false }
            return proposal.title == "Dune"
        }
        #expect(duneRows.count == 2)

        guard case let .mediaItem(firstDune) = duneRows[0].proposal else {
            Issue.record("Expected a media proposal")
            return
        }
        #expect(firstDune.mediaKind == .book)
        #expect(firstDune.history?.isCompletion == true)
        #expect(firstDune.history?.progress?.currentPage == 412)
        #expect(firstDune.rating == 4.5)

        guard case let .mediaItem(secondDune) = duneRows[1].proposal else {
            Issue.record("Expected a media proposal")
            return
        }
        #expect(secondDune.rating == 4)
        #expect(duneRows[1].warnings.contains { $0.code == .normalizedRating })
        #expect(duneRows[1].ambiguities.contains { $0.field == "Consumed At" })
        #expect(duneRows[1].disposition == .needsReview)

        guard case let .mediaItem(tv) = batch.rows[2].proposal else {
            Issue.record("Expected TV media proposal")
            return
        }
        #expect(tv.mediaKind == .television)
        #expect(tv.history?.progress?.seasonNumber == 2)
        #expect(tv.history?.progress?.episodeNumber == 10)

        #expect(batch.rows[4].ambiguities.contains { $0.field == "Media Type" })
        #expect(batch.rows[5].disposition == .manualEntry)
    }

    @Test("Candidate matching surfaces equally strong existing items instead of choosing one")
    func ambiguousCandidateMatching() throws {
        let data = try ImportFixture.data(named: "sofa_export.csv")
        let batch = try SofaCSVImporter().stage(data)
        let candidates = [
            ImportCatalogEntry(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                title: "Dune",
                mediaKind: .book,
            ),
            ImportCatalogEntry(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                title: "Dune",
                mediaKind: .book,
            ),
        ]

        let matched = ImportCandidateMatcher().matching(batch, against: candidates)
        let dune = matched.rows.filter { $0.matchCandidates.count == 2 }
        #expect(dune.count == 2)
        #expect(dune.allSatisfy { $0.disposition == .needsReview })
        #expect(dune.allSatisfy { $0.ambiguities.contains(where: { $0.field == "match" }) })
    }
}
