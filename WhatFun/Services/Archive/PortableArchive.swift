import CryptoKit
import Foundation

nonisolated enum PortableArchiveTable: String, Codable, CaseIterable, Sendable {
    case items
    case units
    case cycles
    case sessions
    case events
    case quotes
    case lists
    case smartListRules = "smart_list_rules"
    case smartListRuleValues = "smart_list_rule_values"
    case listMemberships = "list_memberships"
    case tags
    case tagMemberships = "tag_memberships"
    case artworks
    case credits
    case reminders
    case externalReferences = "external_references"

    var filename: String { "\(rawValue).csv" }
}

nonisolated struct PortableArchiveManifestFile: Codable, Equatable, Sendable {
    var path: String
    var sha256: String
    var byteCount: Int
    var rowCount: Int?
}

nonisolated struct PortableArchiveManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let formatIdentifier = "app.whatfun.portable-archive"

    var format: String = Self.formatIdentifier
    var schemaVersion: Int = Self.currentSchemaVersion
    var exportedAt: Date
    var generator: String
    var files: [PortableArchiveManifestFile]
    var redactions: [String] = ["private_podcast_feed_urls", "keychain_credential_identifiers"]
}

nonisolated struct PortableArchivePackage: Equatable, Sendable {
    static let manifestFilename = "manifest.json"
    static let schemaFilename = "SCHEMA.md"

    var manifest: PortableArchiveManifest
    /// Includes the manifest, schema documentation, CSV tables, and caller-supplied archive assets.
    var files: [String: Data]
}

nonisolated enum PortableArchiveError: Error, Equatable, Sendable, LocalizedError {
    case invalidManifestFormat(String)
    case unsupportedSchemaVersion(Int)
    case missingFile(String)
    case unsafePath(String)
    case manifestDoesNotMatchFile
    case duplicateManifestPath(String)
    case unlistedFile(String)
    case assetConflict(String)
    case checksumMismatch(path: String, expected: String, actual: String)
    case byteCountMismatch(path: String, expected: Int, actual: Int)
    case missingColumn(table: String, column: String)
    case invalidField(table: String, row: Int, column: String, value: String)
    case destinationNotEmpty(String)

    var errorDescription: String? {
        switch self {
        case let .invalidManifestFormat(format):
            "The package format \(format) is not a WhatFun portable archive."
        case let .unsupportedSchemaVersion(version):
            "Portable archive schema version \(version) is not supported."
        case let .missingFile(path):
            "The archive is missing \(path)."
        case let .unsafePath(path):
            "The archive contains an unsafe path: \(path)."
        case .manifestDoesNotMatchFile:
            "The in-memory manifest does not match manifest.json."
        case let .duplicateManifestPath(path):
            "The manifest lists \(path) more than once."
        case let .unlistedFile(path):
            "The package contains \(path), but the manifest does not list it."
        case let .assetConflict(path):
            "More than one different artwork payload uses archive path \(path)."
        case let .checksumMismatch(path, expected, actual):
            "Checksum mismatch for \(path): expected \(expected), found \(actual)."
        case let .byteCountMismatch(path, expected, actual):
            "Byte count mismatch for \(path): expected \(expected), found \(actual)."
        case let .missingColumn(table, column):
            "The \(table) table is missing required column \(column)."
        case let .invalidField(table, row, column, value):
            "Invalid value \(value) in \(table), row \(row), column \(column)."
        case let .destinationNotEmpty(path):
            "The export destination is not empty: \(path)."
        }
    }
}

nonisolated enum PortableArchiveBuilder {
    static func makePackage(
        payload: ArchivePayload,
        generator: String,
        exportedAt: Date = .now,
        assets: [String: Data] = [:]
    ) throws -> PortableArchivePackage {
        let prepared = try payload.preparedForPortableExport(callerAssets: assets)
        let portablePayload = prepared.payload.stablySorted()
        var packageFiles: [String: Data] = [:]
        var rowCounts: [String: Int] = [:]

        for table in PortableArchiveTable.allCases {
            let document = try PortableArchiveTables.document(for: table, payload: portablePayload)
            packageFiles[table.filename] = try CSVCodec.encode(document)
            rowCounts[table.filename] = document.rows.count
        }

        let schema = PortableArchiveSchema.documentation
        packageFiles[PortableArchivePackage.schemaFilename] = Data(schema.utf8)

        for (path, data) in prepared.assets {
            try validateRelativePath(path)
            guard path.hasPrefix("assets/") else {
                throw PortableArchiveError.unsafePath(path)
            }
            packageFiles[path] = data
        }

        let manifestFiles = packageFiles.keys.sorted().map { path in
            let data = packageFiles[path, default: Data()]
            return PortableArchiveManifestFile(
                path: path,
                sha256: checksum(of: data),
                byteCount: data.count,
                rowCount: rowCounts[path],
            )
        }
        let manifest = PortableArchiveManifest(
            exportedAt: exportedAt,
            generator: generator,
            files: manifestFiles,
        )
        packageFiles[PortableArchivePackage.manifestFilename] = try PortableManifestCodec.encode(manifest)
        return PortableArchivePackage(manifest: manifest, files: packageFiles)
    }

    static func decodePayload(from package: PortableArchivePackage) throws -> ArchivePayload {
        try validate(package)
        var payload = ArchivePayload()
        for table in PortableArchiveTable.allCases {
            guard let data = package.files[table.filename] else {
                throw PortableArchiveError.missingFile(table.filename)
            }
            let document = try CSVCodec.decode(data)
            try PortableArchiveTables.decode(document, table: table, into: &payload)
        }
        for index in payload.artworks.indices {
            guard let path = payload.artworks[index].archivePath else { continue }
            guard let data = package.files[path] else {
                throw PortableArchiveError.missingFile(path)
            }
            payload.artworks[index].imageData = data
        }
        return payload.stablySorted()
    }

    static func validate(_ package: PortableArchivePackage) throws {
        try validateManifestHeader(package.manifest)
        guard let manifestData = package.files[PortableArchivePackage.manifestFilename] else {
            throw PortableArchiveError.missingFile(PortableArchivePackage.manifestFilename)
        }
        let diskManifest = try PortableManifestCodec.decode(manifestData)
        guard manifestsMatch(diskManifest, package.manifest) else {
            throw PortableArchiveError.manifestDoesNotMatchFile
        }

        let requiredPaths = Set(PortableArchiveTable.allCases.map(\.filename) + [PortableArchivePackage.schemaFilename])
        let listedPaths = Set(package.manifest.files.map(\.path))
        for path in requiredPaths where !listedPaths.contains(path) {
            throw PortableArchiveError.missingFile(path)
        }
        let allowedPaths = listedPaths.union([PortableArchivePackage.manifestFilename])
        for path in package.files.keys where !allowedPaths.contains(path) {
            throw PortableArchiveError.unlistedFile(path)
        }

        var seenPaths: Set<String> = []
        for file in package.manifest.files {
            guard seenPaths.insert(file.path).inserted else {
                throw PortableArchiveError.duplicateManifestPath(file.path)
            }
            try validateRelativePath(file.path)
            guard file.path != PortableArchivePackage.manifestFilename else {
                throw PortableArchiveError.unsafePath(file.path)
            }
            guard let data = package.files[file.path] else {
                throw PortableArchiveError.missingFile(file.path)
            }
            guard data.count == file.byteCount else {
                throw PortableArchiveError.byteCountMismatch(
                    path: file.path,
                    expected: file.byteCount,
                    actual: data.count,
                )
            }
            let actual = checksum(of: data)
            guard actual == file.sha256 else {
                throw PortableArchiveError.checksumMismatch(
                    path: file.path,
                    expected: file.sha256,
                    actual: actual,
                )
            }
        }
    }

    static func validateManifestHeader(_ manifest: PortableArchiveManifest) throws {
        guard manifest.format == PortableArchiveManifest.formatIdentifier else {
            throw PortableArchiveError.invalidManifestFormat(manifest.format)
        }
        guard manifest.schemaVersion > 0,
              manifest.schemaVersion <= PortableArchiveManifest.currentSchemaVersion
        else {
            throw PortableArchiveError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
    }

    static func checksum(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func manifestsMatch(
        _ lhs: PortableArchiveManifest,
        _ rhs: PortableArchiveManifest
    ) -> Bool {
        lhs.format == rhs.format &&
            lhs.schemaVersion == rhs.schemaVersion &&
            abs(lhs.exportedAt.timeIntervalSince1970 - rhs.exportedAt.timeIntervalSince1970) < 0.000_001 &&
            lhs.generator == rhs.generator &&
            lhs.files == rhs.files &&
            lhs.redactions == rhs.redactions
    }

    static func validateRelativePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !components.contains(".."),
              !components.contains("")
        else {
            throw PortableArchiveError.unsafePath(path)
        }
    }
}

actor PortableArchiveStore {
    func write(_ package: PortableArchivePackage, to directory: URL) throws {
        try PortableArchiveBuilder.validate(package)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
            guard contents.isEmpty else {
                throw PortableArchiveError.destinationNotEmpty(directory.path)
            }
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        for path in package.files.keys.sorted() {
            guard let data = package.files[path] else { continue }
            let destination = directory.appending(path: path, directoryHint: .notDirectory)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: destination, options: .atomic)
        }
    }

    func read(from directory: URL) throws -> PortableArchivePackage {
        let manifestURL = directory.appending(path: PortableArchivePackage.manifestFilename)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PortableArchiveError.missingFile(PortableArchivePackage.manifestFilename)
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try PortableManifestCodec.decode(manifestData)
        try PortableArchiveBuilder.validateManifestHeader(manifest)

        var files: [String: Data] = [PortableArchivePackage.manifestFilename: manifestData]
        var seenPaths: Set<String> = []
        for file in manifest.files {
            try PortableArchiveBuilder.validateRelativePath(file.path)
            guard seenPaths.insert(file.path).inserted else {
                throw PortableArchiveError.duplicateManifestPath(file.path)
            }
            let url = directory.appending(path: file.path, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PortableArchiveError.missingFile(file.path)
            }
            files[file.path] = try Data(contentsOf: url)
        }

        let package = PortableArchivePackage(manifest: manifest, files: files)
        try PortableArchiveBuilder.validate(package)
        return package
    }
}

private nonisolated enum PortableManifestCodec {
    static func encode(_ manifest: PortableArchiveManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ArchiveDateCodec.string(from: date))
        }
        return try encoder.encode(manifest)
    }

    static func decode(_ data: Data) throws -> PortableArchiveManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ArchiveDateCodec.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO 8601 timestamp.",
                )
            }
            return date
        }
        return try decoder.decode(PortableArchiveManifest.self, from: data)
    }
}

private nonisolated extension ArchivePayload {
    func preparedForPortableExport(
        callerAssets: [String: Data]
    ) throws -> (payload: ArchivePayload, assets: [String: Data]) {
        var copy = self
        var assets = callerAssets
        copy.items = copy.items.map { item in
            var redacted = item
            redacted.feedCredentialIdentifier = nil
            return redacted
        }
        copy.externalReferences = copy.externalReferences.map { reference in
            var redacted = reference
            if redacted.isPrivateFeed {
                if Self.looksLikeNetworkURL(redacted.externalID) {
                    redacted.externalID = "private.\(redacted.id.uuidString.lowercased())"
                }
                redacted.canonicalURL = nil
                redacted.credentialKeychainID = nil
            }
            return redacted
        }
        copy.artworks = try copy.artworks.map { artwork in
            var prepared = artwork
            switch artwork.kind {
            case .remote:
                prepared.archivePath = nil
                prepared.imageData = nil
            case .userSelected, .generated:
                let path = artwork.archivePath ?? Self.artworkPath(for: artwork)
                try PortableArchiveBuilder.validateRelativePath(path)
                guard path.hasPrefix("assets/artwork/") else {
                    throw PortableArchiveError.unsafePath(path)
                }
                if let imageData = artwork.imageData {
                    if let existing = assets[path], existing != imageData {
                        throw PortableArchiveError.assetConflict(path)
                    }
                    assets[path] = imageData
                } else if assets[path] == nil {
                    throw PortableArchiveError.missingFile(path)
                }
                prepared.archivePath = path
                prepared.imageData = nil
            }
            return prepared
        }
        return (copy, assets)
    }

    static func artworkPath(for artwork: ArchiveArtworkRecord) -> String {
        let fileExtension = switch artwork.mimeType?.lowercased() {
        case "image/jpeg", "image/jpg": "jpg"
        case "image/png": "png"
        case "image/heic", "image/heif": "heic"
        case "image/webp": "webp"
        case "image/gif": "gif"
        default: "bin"
        }
        return "assets/artwork/\(artwork.id.uuidString.lowercased()).\(fileExtension)"
    }

    static func looksLikeNetworkURL(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "feed"
    }
}
