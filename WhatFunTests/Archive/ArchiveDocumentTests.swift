import Foundation
import Testing
@testable import WhatFun

@Suite("Archive document safety", .serialized)
struct ArchiveDocumentTests {
    @Test("Portable packages ignore Finder metadata but reject unlisted files")
    func packageMetadataAndUnlistedFiles() async throws {
        let package = try PortableArchiveBuilder.makePackage(
            payload: ArchiveFixture.payload,
            generator: "WhatFunTests",
            exportedAt: ArchiveFixture.timestamp
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WhatFunDocumentTests-\(UUID().uuidString).whatfunarchive", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try await PortableArchiveStore().write(package, to: directory)
        try Data("Finder metadata".utf8).write(
            to: directory.appending(path: ".DS_Store"),
            options: .atomic
        )

        let restored = try PortableArchiveDocument.readPackage(from: directory)
        #expect(restored.manifest == package.manifest)

        try Data("not listed".utf8).write(
            to: directory.appending(path: "unexpected.txt"),
            options: .atomic
        )
        do {
            _ = try PortableArchiveDocument.readPackage(from: directory)
            Issue.record("Expected an unlisted file to be rejected")
        } catch let error as PortableArchiveError {
            #expect(error == .unlistedFile("unexpected.txt"))
        }
    }
}
