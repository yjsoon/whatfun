import Foundation
import Testing
@testable import WhatFun

@Suite("HTTP client")
struct HTTPClientTests {
    @Test("Status validation preserves retry guidance and a bounded body preview")
    func rejectsErrorStatus() throws {
        let response = HTTPResponse(
            data: Data("{\"message\":\"slow down\"}".utf8),
            statusCode: 429,
            headers: ["Retry-After": "30"]
        )

        do {
            _ = try response.validated()
            Issue.record("Expected HTTP status validation to fail")
        } catch let error as HTTPClientError {
            #expect(
                error == .unacceptableStatus(
                    code: 429,
                    retryAfter: "30",
                    responsePreview: "{\"message\":\"slow down\"}"
                )
            )
            #expect(error.recoverySuggestion?.contains("30") == true)
        }
    }

    @Test("Podcast refresh policy accepts 304 while ordinary requests do not")
    func acceptsNotModifiedOnlyWhenRequested() throws {
        let response = HTTPResponse(data: Data(), statusCode: 304)
        #expect(throws: HTTPClientError.self) {
            try response.validated(using: .successful)
        }
        #expect(try response.validated(using: .successfulOrNotModified).statusCode == 304)
    }
}
