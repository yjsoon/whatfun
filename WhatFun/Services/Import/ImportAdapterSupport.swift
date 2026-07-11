import Foundation

nonisolated struct ImportCSVRow {
    var sourceRowNumber: Int
    var raw: [String: String]
    private var canonical: [String: String]

    init(sourceRowNumber: Int, raw: [String: String]) {
        self.sourceRowNumber = sourceRowNumber
        self.raw = raw
        var canonical: [String: String] = [:]
        for (header, value) in raw {
            let key = Self.normalizedHeader(header)
            if canonical[key, default: ""].isEmpty {
                canonical[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        self.canonical = canonical
    }

    func value(_ aliases: String...) -> String? {
        for alias in aliases {
            let candidate = canonical[Self.normalizedHeader(alias)]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
            .lowercased()
    }
}

nonisolated enum ImportAdapterSupport {
    static func csvRows(from data: Data, maxRows: Int) throws -> [ImportCSVRow] {
        let document: CSVDocument
        do {
            document = try CSVCodec.decode(data)
        } catch {
            throw ImportStagingError.parserFailure(error.localizedDescription)
        }
        guard document.rows.count <= maxRows else {
            throw ImportStagingError.tooManyRows(limit: maxRows)
        }
        return document.rows.enumerated().map { offset, row in
            ImportCSVRow(sourceRowNumber: offset + 2, raw: row)
        }
    }

    static func mediaKind(from rawValue: String?) -> ArchiveMediaKind? {
        guard let value = rawValue?.foldedForImport else { return nil }
        if value.contains("comic") || value.contains("manga") || value.contains("graphic novel") { return .comic }
        if value.contains("book") || value.contains("novel") || value.contains("audiobook") { return .book }
        if value.contains("movie") || value.contains("film") { return .movie }
        if value == "tv" || value.contains("television") || value.contains("tv show") || value.contains("series") {
            return .television
        }
        if value.contains("game") { return .game }
        if value.contains("podcast") { return .podcast }
        return nil
    }

    static func status(from rawValue: String?) -> ArchiveLifecycleStatus? {
        guard let value = rawValue?.foldedForImport else { return nil }
        if value.contains("plan") || value.contains("want") || value.contains("queue") ||
            value.contains("backlog") || value.contains("pile")
        {
            return .planned
        }
        if value.contains("progress") || value.contains("current") || value.contains("watching") || value.contains("reading") {
            return .inProgress
        }
        if value.contains("pause") || value.contains("hold") { return .paused }
        if value.contains("complete") || value.contains("finish") || value == "done" || value.contains("played") {
            return .completed
        }
        if value.contains("drop") || value.contains("abandon") || value.contains("did not finish") { return .dropped }
        if value.contains("follow") || value.contains("subscribe") { return .following }
        if value.contains("archive") { return .archived }
        return nil
    }

    static func bool(from rawValue: String?) -> Bool? {
        guard let value = rawValue?.foldedForImport else { return nil }
        return switch value {
        case "true", "yes", "y", "1", "x", "starred", "played", "complete", "completed": true
        case "false", "no", "n", "0", "unstarred", "unplayed", "incomplete": false
        default: nil
        }
    }

    static func integer(from rawValue: String?) -> Int? {
        guard let rawValue else { return nil }
        return Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func double(from rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard let result = Double(normalized), result.isFinite else { return nil }
        return result
    }

    static func minutes(from rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 {
            return parts[0] * 60 + parts[1] + parts[2] / 60
        }
        if parts.count == 2 {
            return parts[0] + parts[1] / 60
        }
        return double(from: value)
    }

    static func rating(from rawValue: String?, field: String = "rating") -> (
        value: Double?,
        warnings: [ImportWarning]
    ) {
        guard var rawValue, !rawValue.isEmpty else { return (nil, []) }
        rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if rawValue.contains("★") || rawValue.contains("⭐") {
            let wholeStars = rawValue.count(where: { $0 == "★" || $0 == "⭐" })
            return wholeStars > 0 ? (Double(wholeStars), []) : (nil, [])
        }

        let numerator = rawValue.split(separator: "/").first.map(String.init) ?? rawValue
        guard var rating = double(from: numerator) else {
            return (
                nil,
                [ImportWarning(
                    code: .invalidRating,
                    severity: .warning,
                    message: "The rating could not be interpreted.",
                    field: field,
                    rawValue: rawValue,
                )],
            )
        }

        var warnings: [ImportWarning] = []
        if rating > 5, rating <= 10 {
            rating /= 2
            warnings.append(ImportWarning(
                code: .normalizedRating,
                severity: .information,
                message: "A ten-point rating was converted to the five-star scale.",
                field: field,
                rawValue: rawValue,
            ))
        }
        guard rating >= 0.5, rating <= 5 else {
            warnings.append(ImportWarning(
                code: .invalidRating,
                severity: .warning,
                message: "The rating is outside WhatFun's 0.5–5 range.",
                field: field,
                rawValue: rawValue,
            ))
            return (nil, warnings)
        }

        let rounded = (rating * 2).rounded() / 2
        if rounded != rating {
            warnings.append(ImportWarning(
                code: .normalizedRating,
                severity: .information,
                message: "The rating was rounded to the nearest half star.",
                field: field,
                rawValue: rawValue,
            ))
        }
        return (rounded, warnings)
    }

    static func date(from rawValue: String?, field: String) -> (
        value: Date?,
        warnings: [ImportWarning],
        ambiguities: [ImportAmbiguity]
    ) {
        guard let rawValue, !rawValue.isEmpty else { return (nil, [], []) }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ArchiveDateCodec.date(from: value) {
            return (date, [], [])
        }

        if let components = hyphenDateComponents(value),
           let date = calendarDate(year: components.year, month: components.month, day: components.day)
        {
            // Noon UTC preserves a calendar-only legacy date across the widest range of time zones.
            return (date, [], [])
        }

        if let date = parseDate(value, formats: ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"]) {
            return (date, [], [])
        }

        if let slash = slashDateComponents(value) {
            if slash.first <= 12, slash.second <= 12, slash.first != slash.second {
                let monthFirst = calendarDate(year: slash.year, month: slash.first, day: slash.second)
                let dayFirst = calendarDate(year: slash.year, month: slash.second, day: slash.first)
                let candidates = [monthFirst, dayFirst]
                    .compactMap(\.self)
                    .map(ArchiveDateCodec.string)
                return (
                    nil,
                    [ImportWarning(
                        code: .ambiguousDate,
                        severity: .warning,
                        message: "The numeric date could be month-first or day-first.",
                        field: field,
                        rawValue: value,
                    )],
                    [ImportAmbiguity(
                        field: field,
                        message: "Choose how to interpret \(value).",
                        candidates: candidates,
                    )],
                )
            }
            let month = slash.first > 12 ? slash.second : slash.first
            let day = slash.first > 12 ? slash.first : slash.second
            if let date = calendarDate(year: slash.year, month: month, day: day) {
                return (date, [], [])
            }
        }

        if let date = parseDate(
            value,
            formats: [
                "EEE, dd MMM yyyy HH:mm:ss Z",
                "EEE, d MMM yyyy HH:mm:ss Z",
                "MMM d, yyyy",
                "MMMM d, yyyy",
            ],
        ) {
            return (date, [], [])
        }

        return (
            nil,
            [ImportWarning(
                code: .unparseableDate,
                severity: .warning,
                message: "The date could not be interpreted and was left for review.",
                field: field,
                rawValue: value,
            )],
            [],
        )
    }

    private static func parseDate(_ value: String, formats: [String]) -> Date? {
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func slashDateComponents(_ value: String) -> (first: Int, second: Int, year: Int)? {
        let components = value.split(separator: "/")
        guard components.count == 3,
              let first = Int(components[0]),
              let second = Int(components[1]),
              var year = Int(components[2]) else { return nil }
        if year < 100 { year += year >= 70 ? 1900 : 2000 }
        return (first, second, year)
    }

    private static func hyphenDateComponents(_ value: String) -> (year: Int, month: Int, day: Int)? {
        let components = value.split(separator: "-")
        guard components.count == 3,
              components[0].count == 4,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else { return nil }
        return (year, month, day)
    }

    private static func calendarDate(year: Int, month: Int, day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let date = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12,
        )) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return date
    }
}

private nonisolated extension String {
    var foldedForImport: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
