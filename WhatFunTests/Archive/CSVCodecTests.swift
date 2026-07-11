import Foundation
import Testing
@testable import WhatFun

@Suite("RFC 4180 CSV codec")
struct CSVCodecTests {
    @Test("Round-trips commas, quotes, Unicode, and embedded newlines")
    func specialCharactersRoundTrip() throws {
        let document = CSVDocument(
            headers: ["title", "note", "empty"],
            rows: [[
                "title": "A title, with punctuation",
                "note": "A \"quoted\" thought\r\nwith a second line and café",
                "empty": "",
            ]],
        )

        let data = try CSVCodec.encode(document)
        #expect(String(decoding: data, as: UTF8.self).contains("\r\n"))
        #expect(try CSVCodec.decode(data) == document)
    }

    @Test("Accepts a UTF-8 BOM and LF records")
    func bomAndLF() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("a,b\n1,2\n\n".utf8)
        let document = try CSVCodec.decode(data)
        #expect(document.headers == ["a", "b"])
        #expect(document.rows == [["a": "1", "b": "2"]])
    }

    @Test("Rejects an unterminated quoted field")
    func malformedQuote() {
        do {
            _ = try CSVCodec.decode("title,note\nExample,\"unfinished")
            Issue.record("Expected malformed CSV to throw")
        } catch let error as CSVCodecError {
            #expect(error == .unterminatedQuotedField(row: 2, column: 2))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
