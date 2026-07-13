import Foundation

/// The status codes an HTTP request considers successful.
///
/// Most metadata APIs use ordinary 2xx responses. Podcast refreshes additionally
/// accept `304 Not Modified` so callers can use ETag and Last-Modified validators.
nonisolated enum HTTPStatusPolicy: Sendable, Equatable {
    case successful
    case successfulOrNotModified
    case codes(Set<Int>)

    func accepts(_ statusCode: Int) -> Bool {
        switch self {
        case .successful:
            (200 ... 299).contains(statusCode)
        case .successfulOrNotModified:
            (200 ... 299).contains(statusCode) || statusCode == 304
        case let .codes(codes):
            codes.contains(statusCode)
        }
    }
}

/// A small Sendable response value, keeping URLSession response objects out of
/// provider code and making networking deterministic to test.
nonisolated struct HTTPResponse: Sendable, Equatable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]

    init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [String: String]()) { normalized, header in
            normalized[header.key.lowercased()] = header.value
        }
    }

    func header(named name: String) -> String? {
        headers[name.lowercased()]
    }

    @discardableResult
    func validated(using policy: HTTPStatusPolicy = .successful) throws -> HTTPResponse {
        guard policy.accepts(statusCode) else {
            let preview = String(decoding: data.prefix(512), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HTTPClientError.unacceptableStatus(
                code: statusCode,
                retryAfter: header(named: "Retry-After"),
                responsePreview: preview.isEmpty ? nil : preview
            )
        }
        return self
    }
}

nonisolated enum HTTPClientError: Error, Sendable, Equatable {
    case invalidResponse
    case unacceptableStatus(code: Int, retryAfter: String?, responsePreview: String?)
    case transport(code: Int, message: String)
}

extension HTTPClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned a response WhatFun could not understand."
        case let .unacceptableStatus(code, _, _):
            "The metadata service returned HTTP status \(code)."
        case let .transport(_, message):
            "The network request failed: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .unacceptableStatus(code, retryAfter, _):
            if code == 429, let retryAfter {
                "Try again after \(retryAfter), or add the item manually."
            } else {
                "Try again later, or add the item manually."
            }
        case .invalidResponse, .transport:
            "Check your connection and try again, or add the item manually."
        }
    }
}

/// Injectable transport shared by every metadata provider.
nonisolated protocol HTTPClient: Sendable {
    func send(
        _ request: URLRequest,
        accepting statusPolicy: HTTPStatusPolicy
    ) async throws -> HTTPResponse
}

extension HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await send(request, accepting: .successful)
    }
}

nonisolated struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A client for requests that carry secrets: metadata API keys (RAWG puts its
    /// key in the query string, TMDB sends a bearer token) and private podcast feed
    /// URLs. The default shared session writes responses — including the request URL
    /// and its headers — into an on-disk URLCache, which would leave a plaintext copy
    /// of the secret outside the Keychain that removing the key would not erase.
    /// An ephemeral configuration with no URLCache keeps nothing on disk.
    static func secretless() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSessionHTTPClient(session: URLSession(configuration: configuration))
    }

    /// Whether this client can persist a response to disk. Used by tests to assert
    /// that credential-bearing requests never touch a durable cache.
    var persistsResponsesToDisk: Bool {
        guard let cache = session.configuration.urlCache else { return false }
        return cache.diskCapacity > 0
    }

    func send(
        _ request: URLRequest,
        accepting statusPolicy: HTTPStatusPolicy
    ) async throws -> HTTPResponse {
        try Task.checkCancellation()

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()

            guard let response = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse
            }

            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                guard let key = pair.key as? String else { return }
                result[key] = String(describing: pair.value)
            }

            return try HTTPResponse(
                data: data,
                statusCode: response.statusCode,
                headers: headers
            ).validated(using: statusPolicy)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as HTTPClientError {
            throw error
        } catch let error as URLError {
            // Deliberately omit the request URL: private podcast feeds can put a
            // secret token in the URL and errors may be surfaced or logged.
            throw HTTPClientError.transport(
                code: error.code.rawValue,
                message: URLError(error.code).localizedDescription
            )
        }
    }
}
