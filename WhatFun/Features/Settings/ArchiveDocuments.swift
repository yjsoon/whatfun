import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let whatFunBackup = UTType(
        exportedAs: "com.yjsoon.whatfun.backup",
        conformingTo: .json
    )

    nonisolated static let whatFunArchive = UTType(
        exportedAs: "com.yjsoon.whatfun.portable-archive",
        conformingTo: .package
    )
}

nonisolated enum ArchiveDocumentError: Error, LocalizedError {
    case fileTooLarge(Int)
    case packageTooLarge(Int)
    case tooManyFiles(Int)
    case hierarchyTooDeep(Int)

    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(limit):
            "An archive file exceeds the \(limit / 1_048_576) MB safety limit."
        case let .packageTooLarge(limit):
            "The archive exceeds the \(limit / 1_048_576) MB safety limit."
        case let .tooManyFiles(limit):
            "The archive contains more than \(limit) files."
        case let .hierarchyTooDeep(limit):
            "The archive contains more than \(limit) nested folder levels."
        }
    }
}

struct FullBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.whatFunBackup, .json] }
    nonisolated static let maximumByteCount = 512 * 1_048_576

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard data.count <= Self.maximumByteCount else {
            throw ArchiveDocumentError.fileTooLarge(Self.maximumByteCount)
        }
        _ = try FullFidelityArchiveCodec.decode(data)
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PortableArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.whatFunArchive, .package, .folder] }
    nonisolated static let maximumFileCount = 512
    nonisolated static let maximumDepth = 12
    nonisolated static let maximumFileByteCount = 128 * 1_048_576
    nonisolated static let maximumPackageByteCount = 512 * 1_048_576

    var package: PortableArchivePackage

    init(package: PortableArchivePackage) {
        self.package = package
    }

    init(configuration: ReadConfiguration) throws {
        package = try Self.decodePackage(in: configuration.file)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try PortableArchiveBuilder.validate(package)
        let root = FileWrapper(directoryWithFileWrappers: [:])
        for (path, data) in package.files.sorted(by: { $0.key < $1.key }) {
            try Self.add(data: data, at: path, to: root)
        }
        return root
    }

    static func readPackage(from url: URL) throws -> PortableArchivePackage {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let wrapper = try FileWrapper(url: url, options: [])
        return try decodePackage(in: wrapper)
    }

    private static func add(data: Data, at path: String, to root: FileWrapper) throws {
        try PortableArchiveBuilder.validateRelativePath(path)
        var current = root
        let components = path.split(separator: "/").map(String.init)
        for component in components.dropLast() {
            if let existing = current.fileWrappers?[component], existing.isDirectory {
                current = existing
            } else {
                let directory = FileWrapper(directoryWithFileWrappers: [:])
                directory.preferredFilename = component
                current.addFileWrapper(directory)
                current = directory
            }
        }
        guard let filename = components.last else {
            throw PortableArchiveError.unsafePath(path)
        }
        let file = FileWrapper(regularFileWithContents: data)
        file.preferredFilename = filename
        current.addFileWrapper(file)
    }

    private static func decodePackage(in root: FileWrapper) throws -> PortableArchivePackage {
        guard root.isDirectory,
              let manifestWrapper = root.fileWrappers?[PortableArchivePackage.manifestFilename],
              manifestWrapper.isRegularFile,
              let manifestData = manifestWrapper.regularFileContents else {
            throw PortableArchiveError.missingFile(PortableArchivePackage.manifestFilename)
        }
        guard manifestData.count <= maximumFileByteCount else {
            throw ArchiveDocumentError.fileTooLarge(maximumFileByteCount)
        }
        let manifest = try decodeManifest(manifestData)
        try PortableArchiveBuilder.validateManifestHeader(manifest)
        let expectedPaths = Set(
            manifest.files.map(\.path) + [PortableArchivePackage.manifestFilename]
        )
        guard expectedPaths.count <= maximumFileCount else {
            throw ArchiveDocumentError.tooManyFiles(maximumFileCount)
        }
        let files = try collectFiles(in: root, expectedPaths: expectedPaths)
        let package = PortableArchivePackage(manifest: manifest, files: files)
        try PortableArchiveBuilder.validate(package)
        return package
    }

    private static func collectFiles(
        in root: FileWrapper,
        expectedPaths: Set<String>
    ) throws -> [String: Data] {
        var result: [String: Data] = [:]
        var totalByteCount = 0

        func walk(_ wrapper: FileWrapper, prefix: String, depth: Int) throws {
            guard depth <= maximumDepth else {
                throw ArchiveDocumentError.hierarchyTooDeep(maximumDepth)
            }
            if wrapper.isRegularFile {
                guard expectedPaths.contains(prefix) else {
                    throw PortableArchiveError.unlistedFile(prefix)
                }
                if let size = wrapper.fileAttributes[FileAttributeKey.size.rawValue] as? NSNumber,
                   size.intValue > maximumFileByteCount {
                    throw ArchiveDocumentError.fileTooLarge(maximumFileByteCount)
                }
                guard let data = wrapper.regularFileContents else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard data.count <= maximumFileByteCount else {
                    throw ArchiveDocumentError.fileTooLarge(maximumFileByteCount)
                }
                totalByteCount += data.count
                guard totalByteCount <= maximumPackageByteCount else {
                    throw ArchiveDocumentError.packageTooLarge(maximumPackageByteCount)
                }
                result[prefix] = data
                return
            }
            guard wrapper.isDirectory else {
                throw PortableArchiveError.unsafePath(prefix)
            }
            for (name, child) in wrapper.fileWrappers ?? [:] {
                if name == ".DS_Store" || name.hasPrefix("._") || name == "__MACOSX" {
                    continue
                }
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                try PortableArchiveBuilder.validateRelativePath(path)
                if child.isDirectory,
                   !expectedPaths.contains(where: { $0.hasPrefix("\(path)/") }) {
                    throw PortableArchiveError.unlistedFile(path)
                }
                try walk(child, prefix: path, depth: depth + 1)
            }
        }

        try walk(root, prefix: "", depth: 0)
        return result
    }

    private static func decodeManifest(_ data: Data) throws -> PortableArchiveManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ArchiveDateCodec.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid archive date."
                )
            }
            return date
        }
        return try decoder.decode(PortableArchiveManifest.self, from: data)
    }
}
