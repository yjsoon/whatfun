import Foundation

/// Flexible staging adapter for Sofa CSV exports from multiple app versions.
/// Rows are never merged here: repeated titles remain repeated history candidates.
nonisolated struct SofaCSVImporter: Sendable {
    var maximumRows = 100_000
    var maximumBytes = 250 * 1024 * 1024

    func stage(_ data: Data, sourceFilename: String? = nil) throws -> StagedImportBatch {
        guard data.count <= maximumBytes else {
            throw ImportStagingError.fileTooLarge(limitBytes: maximumBytes)
        }
        let sourceRows = try ImportAdapterSupport.csvRows(from: data, maxRows: maximumRows)
        guard !sourceRows.isEmpty else {
            throw ImportStagingError.unsupportedFormat("The Sofa CSV contains no rows.")
        }

        let rows = sourceRows.map(stageRow)
        guard rows.contains(where: { $0.proposal.kind == .mediaItem }) else {
            throw ImportStagingError.unsupportedFormat(
                "No titled media rows were found. Confirm that this is a Sofa CSV export.",
            )
        }
        return StagedImportBatch(
            source: .sofaCSV,
            sourceFilename: sourceFilename,
            rows: rows,
            warnings: [ImportWarning(
                code: .partialMetadata,
                severity: .information,
                message: "Sofa exports vary by version. Review staged matches before importing.",
                field: nil,
                rawValue: nil,
            )],
        )
    }

    private func stageRow(_ source: ImportCSVRow) -> StagedImportRow {
        let title = source.value("Title", "Name", "Item", "Media Title")
        guard let title else {
            return StagedImportRow(
                sourceRowNumber: source.sourceRowNumber,
                rawFields: source.raw,
                proposal: .unresolved(UnresolvedImportProposal(
                    bestTitle: nil,
                    reason: "This Sofa row has no title.",
                )),
                confidence: 0.1,
                warnings: [ImportWarning(
                    code: .missingTitle,
                    severity: .warning,
                    message: "No title was found in this row.",
                    field: "Title",
                    rawValue: nil,
                )],
            )
        }

        var warnings: [ImportWarning] = []
        var ambiguities: [ImportAmbiguity] = []

        let rawType = source.value("Media Type", "Type", "Category", "Kind", "Item Type")
        var mediaKind = ImportAdapterSupport.mediaKind(from: rawType)
        if mediaKind == nil {
            mediaKind = inferredMediaKind(from: source)
            if let mediaKind {
                warnings.append(ImportWarning(
                    code: .inferredValue,
                    severity: .information,
                    message: "The media type was inferred as \(mediaKind.rawValue) from progress columns.",
                    field: "Media Type",
                    rawValue: rawType,
                ))
            } else {
                warnings.append(ImportWarning(
                    code: .unknownMediaType,
                    severity: .warning,
                    message: "The media type needs to be selected.",
                    field: "Media Type",
                    rawValue: rawType,
                ))
                ambiguities.append(ImportAmbiguity(
                    field: "Media Type",
                    message: "Choose a WhatFun media type for this Sofa row.",
                    candidates: ArchiveMediaKind.allCases.map(\.rawValue),
                ))
            }
        }

        let rawStatus = source.value("Status", "State", "Shelf", "Sofa List")
        var status = ImportAdapterSupport.status(from: rawStatus)
        let consumed = ImportAdapterSupport.date(
            from: source.value(
                "Consumed At", "Activity Date", "Logged At", "Date", "Watched At", "Read At", "Played At",
            ),
            field: "Consumed At",
        )
        let started = ImportAdapterSupport.date(
            from: source.value("Start Date", "Started At", "Started", "Date Started"),
            field: "Start Date",
        )
        let completed = ImportAdapterSupport.date(
            from: source.value("Completion Date", "Completed At", "Finished At", "Date Finished", "Date Completed"),
            field: "Completion Date",
        )
        let released = ImportAdapterSupport.date(
            from: source.value("Release Date", "Published", "Publication Date"),
            field: "Release Date",
        )
        let added = ImportAdapterSupport.date(
            from: source.value("Date Added", "Added At", "Created At"),
            field: "Date Added",
        )
        warnings += consumed.warnings + started.warnings + completed.warnings + released.warnings + added.warnings
        ambiguities += consumed.ambiguities + started.ambiguities + completed.ambiguities +
            released.ambiguities + added.ambiguities

        if completed.value != nil { status = .completed }
        let rating = ImportAdapterSupport.rating(
            from: source.value("Rating", "Stars", "Score", "Your Rating"),
        )
        warnings += rating.warnings

        let progress = progressProposal(from: source)
        let note = source.value("Notes", "Note", "Comment", "Review", "Description")
        let isCompletion = status == .completed || completed.value != nil
        let hasHistory = consumed.value != nil || completed.value != nil || progress != nil || isCompletion
        let history = hasHistory ? ImportConsumptionProposal(
            consumedAt: consumed.value ?? completed.value,
            completedAt: completed.value,
            isCompletion: isCompletion,
            status: status,
            rating: rating.value,
            progress: progress,
            note: note,
        ) : nil

        if isCompletion, completed.value == nil, consumed.value == nil {
            warnings.append(ImportWarning(
                code: .partialMetadata,
                severity: .warning,
                message: "The item is complete but the export has no completion date.",
                field: "Completion Date",
                rawValue: nil,
            ))
        }

        var externalIdentifiers: [String: String] = [:]
        for (key, aliases) in [
            ("source_url", ["URL", "Link", "Source URL"]),
            ("isbn", ["ISBN", "ISBN13"]),
            ("tmdb", ["TMDB ID", "TMDb ID"]),
            ("rawg", ["RAWG ID"]),
        ] {
            for alias in aliases {
                if let value = source.value(alias) {
                    externalIdentifiers[key] = value
                    break
                }
            }
        }

        let proposal = MediaItemImportProposal(
            title: title,
            mediaKind: mediaKind,
            subtitle: source.value("Subtitle"),
            creators: separatedValues(from: source.value("Creator", "Creators", "Author", "Director", "Developer")),
            releaseDate: released.value,
            addedAt: added.value,
            status: status,
            rating: rating.value,
            isFavorite: ImportAdapterSupport.bool(from: source.value("Favorite", "Favourite", "Starred")) ?? false,
            startDate: started.value,
            completionDate: completed.value,
            note: note,
            listNames: separatedValues(from: source.value("List", "Sofa List", "Collection", "Custom List")),
            tags: separatedValues(from: source.value("Tags", "Tag")),
            history: history,
            externalIdentifiers: externalIdentifiers,
        )

        var confidence = 0.66
        if mediaKind != nil { confidence += 0.2 }
        if rawType != nil { confidence += 0.05 }
        if consumed.value != nil || completed.value != nil { confidence += 0.05 }
        if !ambiguities.isEmpty { confidence -= 0.2 }
        return StagedImportRow(
            sourceRowNumber: source.sourceRowNumber,
            rawFields: source.raw,
            proposal: .mediaItem(proposal),
            confidence: confidence,
            warnings: warnings,
            ambiguities: ambiguities,
        )
    }

    private func inferredMediaKind(from row: ImportCSVRow) -> ArchiveMediaKind? {
        if row.value("Season", "Season Number", "Episode", "Episode Number") != nil { return .television }
        if row.value("Issue", "Issue Number", "Volume", "Volume Number") != nil { return .comic }
        if row.value("Platform", "Playtime", "Hours Played") != nil { return .game }
        if row.value("Page", "Current Page", "Total Pages", "Chapter") != nil { return .book }
        return nil
    }

    private func progressProposal(from row: ImportCSVRow) -> ImportProgressProposal? {
        var percentage = ImportAdapterSupport.double(
            from: row.value("Completion Percentage", "Percent Complete", "Progress Percent", "Progress %"),
        )
        if let value = percentage, value >= 0, value <= 1 { percentage = value * 100 }

        let currentPage = ImportAdapterSupport.integer(from: row.value("Current Page", "Page", "Page Progress"))
        let totalPages = ImportAdapterSupport.integer(from: row.value("Total Pages", "Page Count", "Pages"))
        let chapter = row.value("Chapter", "Current Chapter")
        let elapsedMinutes = ImportAdapterSupport.minutes(
            from: row.value("Elapsed Minutes", "Watch Progress", "Episode Progress", "Elapsed"),
        )
        let totalRuntimeMinutes = ImportAdapterSupport.minutes(
            from: row.value("Runtime Minutes", "Duration Minutes", "Runtime"),
        )
        let seasonNumber = ImportAdapterSupport.integer(from: row.value("Season", "Season Number"))
        let episodeNumber = ImportAdapterSupport.integer(from: row.value("Episode", "Episode Number"))
        let volumeNumber = ImportAdapterSupport.integer(from: row.value("Volume", "Volume Number"))
        let issueNumber = row.value("Issue", "Issue Number")
        let playtimeMinutes = ImportAdapterSupport.minutes(
            from: row.value("Playtime Minutes", "Playtime", "Minutes Played"),
        )
        let hasValue = currentPage != nil || totalPages != nil || chapter != nil || elapsedMinutes != nil ||
            totalRuntimeMinutes != nil || seasonNumber != nil || episodeNumber != nil || volumeNumber != nil ||
            issueNumber != nil || playtimeMinutes != nil || percentage != nil
        guard hasValue else { return nil }

        let progress = ImportProgressProposal(
            currentPage: currentPage,
            totalPages: totalPages,
            chapter: chapter,
            elapsedMinutes: elapsedMinutes,
            totalRuntimeMinutes: totalRuntimeMinutes,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            volumeNumber: volumeNumber,
            issueNumber: issueNumber,
            playtimeMinutes: playtimeMinutes,
            completionPercentage: percentage,
        )
        return progress
    }

    private func separatedValues(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        let separator: Character? = rawValue.contains(";") ? ";" : (rawValue.contains("|") ? "|" : nil)
        guard let separator else { return [rawValue] }
        return rawValue.split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
