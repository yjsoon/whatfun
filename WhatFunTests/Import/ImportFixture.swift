import Foundation

enum ImportFixture {
    static func data(named name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
        return try Data(contentsOf: directory.appending(path: name))
    }
}
