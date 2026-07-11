import Foundation
import Testing
@testable import WhatFun

@Suite("Artwork repository")
struct ArtworkRepositoryTests {
    @Test("Cache hashes are stable and filename-safe")
    func cacheHashIsStable() {
        let first = ArtworkRepository.hash("https://example.com/a cover.jpg")
        let second = ArtworkRepository.hash("https://example.com/a cover.jpg")

        #expect(first == second)
        #expect(first.count == 64)
        #expect(first.allSatisfy { $0.isHexDigit })
    }

    @Test("Invalid user artwork is rejected")
    func invalidUserArtworkIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ArtworkRepository(
            location: ArtworkCacheLocation(
                remoteDirectory: root.appending(path: "remote"),
                userDirectory: root.appending(path: "user")
            )
        )

        await #expect(throws: ArtworkRepositoryError.invalidImage) {
            try await repository.storeUserArtwork(Data("not an image".utf8), id: UUID())
        }
    }
}

