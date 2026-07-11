import Foundation

nonisolated struct CSVDocument: Equatable, Sendable {
    var headers: [String]
    var rows: [[String: String]]

    init(headers: [String], rows: [[String: String]]) {
        self.headers = headers
        self.rows = rows
    }
}

nonisolated enum CSVCodecError: Error, Equatable, Sendable, LocalizedError {
    case invalidUTF8
    case emptyDocument
    case emptyHeader(column: Int)
    case duplicateHeader(String)
    case unexpectedQuote(row: Int, column: Int)
    case charactersAfterClosingQuote(row: Int, column: Int)
    case unterminatedQuotedField(row: Int, column: Int)
    case inconsistentColumnCount(row: Int, expected: Int, actual: Int)
    case missingValue(header: String, row: Int)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "The CSV file is not valid UTF-8."
        case .emptyDocument:
            "The CSV file does not contain a header row."
        case let .emptyHeader(column):
            "CSV header column \(column) is empty."
        case let .duplicateHeader(header):
            "CSV header \(header) appears more than once."
        case let .unexpectedQuote(row, column):
            "Unexpected quote at CSV row \(row), column \(column)."
        case let .charactersAfterClosingQuote(row, column):
            "Unexpected characters after a closing quote at CSV row \(row), column \(column)."
        case let .unterminatedQuotedField(row, column):
            "Unterminated quoted field at CSV row \(row), column \(column)."
        case let .inconsistentColumnCount(row, expected, actual):
            "CSV row \(row) has \(actual) columns; expected \(expected)."
        case let .missingValue(header, row):
            "CSV row \(row) has no value for \(header)."
        }
    }
}

/// A small RFC 4180 codec that supports commas, CRLF/LF newlines, embedded newlines, and doubled quotes.
nonisolated enum CSVCodec {
    static func encode(_ document: CSVDocument) throws -> Data {
        guard !document.headers.isEmpty else {
            throw CSVCodecError.emptyDocument
        }
        try validate(headers: document.headers)

        var lines: [String] = []
        lines.reserveCapacity(document.rows.count + 1)
        lines.append(document.headers.map(escaped).joined(separator: ","))

        for (offset, row) in document.rows.enumerated() {
            let values = try document.headers.map { header in
                guard let value = row[header] else {
                    throw CSVCodecError.missingValue(header: header, row: offset + 2)
                }
                return escaped(value)
            }
            lines.append(values.joined(separator: ","))
        }

        // RFC 4180 records use CRLF and the final record is terminated as well.
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func decode(_ data: Data) throws -> CSVDocument {
        var bytes = Array(data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
        }
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw CSVCodecError.invalidUTF8
        }
        return try decode(string)
    }

    static func decode(_ source: String) throws -> CSVDocument {
        let rawRows = try parseRows(source)
        guard let headers = rawRows.first else {
            throw CSVCodecError.emptyDocument
        }
        try validate(headers: headers)

        var rows: [[String: String]] = []
        rows.reserveCapacity(max(0, rawRows.count - 1))
        for (offset, values) in rawRows.dropFirst().enumerated() {
            // Spreadsheet exports commonly append blank physical lines. They are not records in
            // a multi-column table and should not make an otherwise valid import unusable.
            if headers.count > 1, values == [""] { continue }
            guard values.count == headers.count else {
                throw CSVCodecError.inconsistentColumnCount(
                    row: offset + 2,
                    expected: headers.count,
                    actual: values.count,
                )
            }
            rows.append(Dictionary(uniqueKeysWithValues: zip(headers, values)))
        }
        return CSVDocument(headers: headers, rows: rows)
    }

    private static func validate(headers: [String]) throws {
        var seen: Set<String> = []
        for (offset, header) in headers.enumerated() {
            guard !header.isEmpty else {
                throw CSVCodecError.emptyHeader(column: offset + 1)
            }
            guard seen.insert(header).inserted else {
                throw CSVCodecError.duplicateHeader(header)
            }
        }
    }

    private static func escaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\r") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseRows(_ source: String) throws -> [[String]] {
        guard !source.isEmpty else { return [] }

        let scalars = Array(source.unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var justClosedQuote = false
        var fieldHasContent = false
        var rowHasContent = false
        var index = 0

        func fieldString() -> String {
            String(field)
        }

        while index < scalars.count {
            let scalar = scalars[index]

            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        fieldHasContent = true
                        rowHasContent = true
                        index += 2
                        continue
                    }
                    inQuotes = false
                    justClosedQuote = true
                    index += 1
                    continue
                }

                field.append(scalar)
                fieldHasContent = true
                rowHasContent = true
                index += 1
                continue
            }

            if scalar == "\"" {
                guard !fieldHasContent, !justClosedQuote else {
                    throw CSVCodecError.unexpectedQuote(row: rows.count + 1, column: row.count + 1)
                }
                inQuotes = true
                rowHasContent = true
                index += 1
                continue
            }

            if scalar == "," {
                row.append(fieldString())
                field.removeAll(keepingCapacity: true)
                fieldHasContent = false
                justClosedQuote = false
                rowHasContent = true
                index += 1
                continue
            }

            if scalar == "\r" || scalar == "\n" {
                row.append(fieldString())
                rows.append(row)
                row.removeAll(keepingCapacity: true)
                field.removeAll(keepingCapacity: true)
                fieldHasContent = false
                justClosedQuote = false
                rowHasContent = false
                if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            guard !justClosedQuote else {
                throw CSVCodecError.charactersAfterClosingQuote(row: rows.count + 1, column: row.count + 1)
            }
            field.append(scalar)
            fieldHasContent = true
            rowHasContent = true
            index += 1
        }

        if inQuotes {
            throw CSVCodecError.unterminatedQuotedField(row: rows.count + 1, column: row.count + 1)
        }

        if rowHasContent || fieldHasContent || !row.isEmpty || justClosedQuote {
            row.append(fieldString())
            rows.append(row)
        }

        return rows
    }
}
