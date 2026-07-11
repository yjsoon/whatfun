import CryptoKit
import Foundation
import ImageIO
import UIKit

enum ArtworkRepositoryError: Error, Equatable, LocalizedError {
    case invalidHTTPResponse
    case unsuccessfulStatus(Int)
    case emptyResponse
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            "The artwork server returned an invalid response."
        case let .unsuccessfulStatus(status):
            "The artwork server returned status \(status)."
        case .emptyResponse:
            "The artwork response was empty."
        case .invalidImage:
            "The downloaded file is not a supported image."
        }
    }
}

struct ArtworkCacheLocation: Sendable {
    let remoteDirectory: URL
    let userDirectory: URL

    static func applicationSupport(fileManager: FileManager = .default) throws -> ArtworkCacheLocation {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appending(path: "WhatFun", directoryHint: .isDirectory)
        .appending(path: "Artwork", directoryHint: .isDirectory)

        return ArtworkCacheLocation(
            remoteDirectory: root.appending(path: "Remote", directoryHint: .isDirectory),
            userDirectory: root.appending(path: "User", directoryHint: .isDirectory)
        )
    }
}

actor ArtworkRepository {
    private let session: URLSession
    private let fileManager: FileManager
    private let location: ArtworkCacheLocation
    private var inFlightDownloads: [String: Task<Data, Error>] = [:]

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        location: ArtworkCacheLocation
    ) throws {
        self.session = session
        self.fileManager = fileManager
        self.location = location

        try fileManager.createDirectory(at: location.remoteDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: location.userDirectory, withIntermediateDirectories: true)

        var remoteDirectory = location.remoteDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? remoteDirectory.setResourceValues(resourceValues)
    }

    func data(for remoteURL: URL, cacheKey explicitCacheKey: String? = nil) async throws -> Data {
        let key = explicitCacheKey ?? Self.hash(remoteURL.absoluteString)
        let destination = cachedRemoteFileURL(forKey: key)

        if let cached = try? Data(contentsOf: destination), !cached.isEmpty {
            return cached
        }

        if let existing = inFlightDownloads[key] {
            return try await existing.value
        }

        let session = session
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: remoteURL)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ArtworkRepositoryError.invalidHTTPResponse
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw ArtworkRepositoryError.unsuccessfulStatus(httpResponse.statusCode)
            }
            guard !data.isEmpty else {
                throw ArtworkRepositoryError.emptyResponse
            }
            guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                throw ArtworkRepositoryError.invalidImage
            }
            return data
        }

        inFlightDownloads[key] = task
        defer { inFlightDownloads[key] = nil }

        let data = try await task.value
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return data
    }

    func cachedData(for remoteURL: URL, cacheKey explicitCacheKey: String? = nil) -> Data? {
        let key = explicitCacheKey ?? Self.hash(remoteURL.absoluteString)
        return try? Data(contentsOf: cachedRemoteFileURL(forKey: key))
    }

    func storeUserArtwork(_ data: Data, id: UUID) throws -> URL {
        guard !data.isEmpty, CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            throw ArtworkRepositoryError.invalidImage
        }

        let destination = location.userDirectory.appending(path: "\(id.uuidString.lowercased()).image")
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return destination
    }

    func userArtworkData(id: UUID) -> Data? {
        let file = location.userDirectory.appending(path: "\(id.uuidString.lowercased()).image")
        return try? Data(contentsOf: file)
    }

    func removeRemoteArtwork(cacheKey: String) throws {
        let file = cachedRemoteFileURL(forKey: cacheKey)
        guard fileManager.fileExists(atPath: file.path) else { return }
        try fileManager.removeItem(at: file)
    }

    func removeUserArtwork(id: UUID) throws {
        let file = location.userDirectory.appending(path: "\(id.uuidString.lowercased()).image")
        guard fileManager.fileExists(atPath: file.path) else { return }
        try fileManager.removeItem(at: file)
    }

    nonisolated static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cachedRemoteFileURL(forKey key: String) -> URL {
        location.remoteDirectory.appending(path: Self.hash(key))
    }
}

enum ArtworkDownsampler {
    nonisolated static func image(
        from data: Data,
        targetSize: CGSize,
        displayScale: CGFloat
    ) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }

            let maxDimension = max(targetSize.width, targetSize.height) * displayScale
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxDimension)),
            ] as CFDictionary

            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                return nil
            }
            return UIImage(cgImage: image, scale: displayScale, orientation: .up)
        }.value
    }
}

