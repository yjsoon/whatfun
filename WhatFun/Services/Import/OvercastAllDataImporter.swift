import Foundation

/// Best-effort adapter for Overcast's user-facing "All Data" CSV export.
///
/// Overcast has changed column labels over time, so aliases are intentionally accepted and every
/// source row remains visible for confirmation.
nonisolated struct OvercastAllDataImporter: Sendable {
    var maximumRows = 100_000
    var maximumBytes = 250 * 1024 * 1024

    func stage(_ data: Data, sourceFilename: String? = nil) throws -> StagedImportBatch {
        guard data.count <= maximumBytes else {
            throw ImportStagingError.fileTooLarge(limitBytes: maximumBytes)
        }
        let sourceRows = try ImportAdapterSupport.csvRows(from: data, maxRows: maximumRows)
        guard !sourceRows.isEmpty else {
            throw ImportStagingError.unsupportedFormat("The Overcast CSV contains no episode rows.")
        }
        let hasOvercastShape = sourceRows.contains { row in
            let hasTitle = row.value("Episode", "Episode Title", "Title") != nil
            let hasSpecificField = row.value(
                "Podcast", "Podcast Title", "Enclosure URL", "Overcast URL", "Played", "Progress", "Duration",
            ) != nil
            return hasTitle && hasSpecificField
        }
        guard hasOvercastShape else {
            throw ImportStagingError.unsupportedFormat(
                "The CSV does not contain the episode and playback columns expected in an Overcast All Data export.",
            )
        }

        var rows: [StagedImportRow] = []
        var batchWarnings: [ImportWarning] = []
        var seen: Set<String> = []

        for source in sourceRows {
            let podcastTitle = source.value("Podcast", "Podcast Title", "Feed", "Feed Title")
            let episodeTitle = source.value("Episode", "Episode Title", "Title")
            let feedURL = source.value("Feed URL", "Podcast URL", "XML URL", "Feed XML URL")
            let episodeURL = source.value("Episode URL", "Overcast URL", "Web URL", "Link")
            let enclosureURL = source.value("Enclosure URL", "Audio URL", "Media URL")

            let deduplicationKey = [
                enclosureURL,
                episodeURL,
                podcastTitle,
                episodeTitle,
                source.value("Published", "Publication Date", "Pub Date"),
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: "|")
            guard seen.insert(deduplicationKey).inserted || deduplicationKey.isEmpty else {
                batchWarnings.append(ImportWarning(
                    code: .duplicateSourceRow,
                    severity: .information,
                    message: "A duplicate Overcast episode row was ignored.",
                    field: nil,
                    rawValue: nil,
                ))
                continue
            }

            rows.append(stageRow(
                source,
                podcastTitle: podcastTitle,
                episodeTitle: episodeTitle,
                feedURL: feedURL,
                episodeURL: episodeURL,
                enclosureURL: enclosureURL,
            ))
        }

        guard rows.contains(where: { $0.proposal.kind == .podcastEpisode }) else {
            throw ImportStagingError.unsupportedFormat(
                "The CSV does not look like an Overcast All Data export; no episode title column was found.",
            )
        }
        return StagedImportBatch(
            source: .overcastAllDataCSV,
            sourceFilename: sourceFilename,
            rows: rows,
            warnings: batchWarnings,
        )
    }

    private func stageRow(
        _ source: ImportCSVRow,
        podcastTitle: String?,
        episodeTitle: String?,
        feedURL: String?,
        episodeURL: String?,
        enclosureURL: String?
    ) -> StagedImportRow {
        guard let episodeTitle, !episodeTitle.isEmpty else {
            return StagedImportRow(
                sourceRowNumber: source.sourceRowNumber,
                rawFields: source.raw,
                proposal: .unresolved(UnresolvedImportProposal(
                    bestTitle: podcastTitle,
                    reason: "This row has no episode title.",
                )),
                confidence: 0.2,
                warnings: [ImportWarning(
                    code: .missingTitle,
                    severity: .warning,
                    message: "No episode title was found.",
                    field: "Episode",
                    rawValue: nil,
                )],
            )
        }

        var warnings: [ImportWarning] = []
        var ambiguities: [ImportAmbiguity] = []
        if podcastTitle == nil {
            warnings.append(ImportWarning(
                code: .partialMetadata,
                severity: .warning,
                message: "The podcast title is missing, so this episode must be matched manually.",
                field: "Podcast",
                rawValue: nil,
            ))
        }

        for (field, value) in [("Feed URL", feedURL), ("Episode URL", episodeURL), ("Enclosure URL", enclosureURL)] {
            if let value, !isHTTPURL(value) {
                warnings.append(ImportWarning(
                    code: .invalidURL,
                    severity: .warning,
                    message: "The URL needs review.",
                    field: field,
                    rawValue: value,
                ))
            }
        }

        let published = ImportAdapterSupport.date(
            from: source.value("Published", "Publication Date", "Pub Date", "Release Date"),
            field: "Published",
        )
        warnings.append(contentsOf: published.warnings)
        ambiguities.append(contentsOf: published.ambiguities)

        let duration = overcastMinutes(from: source.value("Duration", "Duration Seconds", "Episode Duration"))
        let rawProgress = source.value("Progress", "Progress Seconds", "Playback Position", "Played Seconds")
        let progress = overcastProgress(rawProgress, durationMinutes: duration)
        var isCompleted = ImportAdapterSupport.bool(from: source.value("Played", "Completed", "Is Played")) ?? false
        if let percentage = progress.percentage, percentage >= 99.5 { isCompleted = true }
        let elapsed = isCompleted ? (duration ?? progress.minutes) : progress.minutes

        let proposal = PodcastEpisodeImportProposal(
            podcastTitle: podcastTitle,
            feedURL: feedURL,
            episodeTitle: episodeTitle,
            episodeURL: episodeURL,
            enclosureURL: enclosureURL,
            publishedAt: published.value,
            durationMinutes: duration,
            elapsedMinutes: elapsed,
            completionPercentage: isCompleted ? 100 : progress.percentage,
            isCompleted: isCompleted,
            isNotable: ImportAdapterSupport.bool(from: source.value("Starred", "Favorite", "Favourited")) ?? false,
            note: source.value("Notes", "Note", "Comment"),
        )

        var confidence = podcastTitle == nil ? 0.62 : 0.88
        if feedURL != nil || episodeURL != nil || enclosureURL != nil { confidence += 0.06 }
        if published.value != nil { confidence += 0.03 }
        if !ambiguities.isEmpty { confidence -= 0.2 }
        return StagedImportRow(
            sourceRowNumber: source.sourceRowNumber,
            rawFields: source.raw,
            proposal: .podcastEpisode(proposal),
            confidence: confidence,
            warnings: warnings,
            ambiguities: ambiguities,
        )
    }

    private func isHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host()?.isEmpty == false
    }

    private func overcastMinutes(from rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        if rawValue.contains(":") { return ImportAdapterSupport.minutes(from: rawValue) }
        guard let seconds = ImportAdapterSupport.double(from: rawValue) else { return nil }
        return seconds / 60
    }

    private func overcastProgress(
        _ rawValue: String?,
        durationMinutes: Double?
    ) -> (minutes: Double?, percentage: Double?) {
        guard let rawValue else { return (nil, nil) }
        if rawValue.contains("%"), let percentage = ImportAdapterSupport.double(from: rawValue) {
            let minutes = durationMinutes.map { $0 * percentage / 100 }
            return (minutes, percentage)
        }
        if rawValue.contains(":"), let minutes = ImportAdapterSupport.minutes(from: rawValue) {
            let percentage = durationMinutes.flatMap { $0 > 0 ? minutes / $0 * 100 : nil }
            return (minutes, percentage)
        }
        guard let numeric = ImportAdapterSupport.double(from: rawValue) else { return (nil, nil) }
        if numeric >= 0, numeric <= 1 {
            return (durationMinutes.map { $0 * numeric }, numeric * 100)
        }
        let minutes = numeric / 60
        let percentage = durationMinutes.flatMap { $0 > 0 ? minutes / $0 * 100 : nil }
        return (minutes, percentage)
    }
}
