import Foundation

nonisolated struct ImportCatalogEntry: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var mediaKind: ArchiveMediaKind
    var externalIdentifiers: [String: String] = [:]
}

/// Adds possible canonical-library joins to staged rows without choosing or inserting anything.
nonisolated struct ImportCandidateMatcher: Sendable {
    func matching(
        _ batch: StagedImportBatch,
        against catalog: [ImportCatalogEntry]
    ) -> StagedImportBatch {
        var copy = batch
        copy.rows = batch.rows.map { matching($0, against: catalog) }
        return copy
    }

    private func matching(
        _ row: StagedImportRow,
        against catalog: [ImportCatalogEntry]
    ) -> StagedImportRow {
        guard let identity = identity(for: row.proposal) else { return row }

        let matches = catalog.compactMap { entry -> ImportMatchCandidate? in
            let confidence = confidence(identity: identity, entry: entry)
            guard confidence >= 0.55 else { return nil }
            return ImportMatchCandidate(
                id: entry.id,
                title: entry.title,
                mediaKind: entry.mediaKind,
                confidence: confidence,
                explanation: explanation(identity: identity, entry: entry, confidence: confidence),
            )
        }
        .sorted {
            if $0.confidence == $1.confidence { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.confidence > $1.confidence
        }

        var copy = row
        copy.matchCandidates = Array(matches.prefix(5))
        if matches.count >= 2,
           matches[0].confidence >= 0.8,
           matches[1].confidence >= 0.8,
           matches[0].confidence - matches[1].confidence <= 0.03
        {
            copy.ambiguities.removeAll { $0.field == "match" }
            copy.ambiguities.append(ImportAmbiguity(
                field: "match",
                message: "More than one library item is an equally strong match.",
                candidates: matches.prefix(5).map { "\($0.title) · \($0.mediaKind.rawValue) · \($0.id.uuidString)" },
            ))
            copy.disposition = .needsReview
        } else {
            copy.reassessDisposition()
        }
        return copy
    }

    private func identity(for proposal: ImportProposal) -> MatchIdentity? {
        switch proposal {
        case let .mediaItem(value):
            MatchIdentity(
                title: value.title,
                mediaKind: value.mediaKind,
                externalIdentifiers: value.externalIdentifiers,
            )
        case let .podcastSubscription(value):
            MatchIdentity(
                title: value.title,
                mediaKind: .podcast,
                externalIdentifiers: value.feedURL.map { ["feed_url": $0] } ?? [:],
            )
        case let .podcastEpisode(value):
            value.podcastTitle.map {
                MatchIdentity(
                    title: $0,
                    mediaKind: .podcast,
                    externalIdentifiers: value.feedURL.map { ["feed_url": $0] } ?? [:],
                )
            }
        case .unresolved:
            nil
        }
    }

    private func confidence(identity: MatchIdentity, entry: ImportCatalogEntry) -> Double {
        if hasSharedExternalIdentifier(identity.externalIdentifiers, entry.externalIdentifiers) { return 1 }

        let sourceTitle = normalized(identity.title)
        let candidateTitle = normalized(entry.title)
        let kindMatches = identity.mediaKind == nil || identity.mediaKind == entry.mediaKind
        if sourceTitle == candidateTitle { return kindMatches ? 0.96 : 0.7 }

        let sourceTokens = Set(sourceTitle.split(separator: " ").map(String.init))
        let candidateTokens = Set(candidateTitle.split(separator: " ").map(String.init))
        guard !sourceTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }
        let union = sourceTokens.union(candidateTokens).count
        let overlap = Double(sourceTokens.intersection(candidateTokens).count) / Double(union)
        let score = 0.5 + 0.4 * overlap - (kindMatches ? 0 : 0.2)
        return min(max(score, 0), 1)
    }

    private func hasSharedExternalIdentifier(
        _ source: [String: String],
        _ candidate: [String: String]
    ) -> Bool {
        source.contains { key, value in
            candidate[key]?.caseInsensitiveCompare(value) == .orderedSame
        }
    }

    private func explanation(
        identity: MatchIdentity,
        entry: ImportCatalogEntry,
        confidence: Double
    ) -> String {
        if hasSharedExternalIdentifier(identity.externalIdentifiers, entry.externalIdentifiers) {
            return "An external identifier matches exactly."
        }
        if normalized(identity.title) == normalized(entry.title) {
            return identity.mediaKind == entry.mediaKind ? "Title and media type match." : "Title matches; media type differs."
        }
        return confidence >= 0.8 ? "Title words and media type are a close match." : "Some title words match."
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}

private nonisolated struct MatchIdentity {
    var title: String
    var mediaKind: ArchiveMediaKind?
    var externalIdentifiers: [String: String]
}

private nonisolated extension StagedImportRow {
    mutating func reassessDisposition() {
        if case .unresolved = proposal {
            disposition = .manualEntry
        } else if confidence >= 0.85, ambiguities.isEmpty {
            disposition = .ready
        } else {
            disposition = .needsReview
        }
    }
}
