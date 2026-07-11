import Foundation

nonisolated struct PodcastFeed: Hashable, Codable, Sendable {
    let title: String
    let author: String?
    let summary: String?
    let websiteURL: URL?
    let imageURL: URL?
    let languageCode: String?
    let isExplicit: Bool?
    let lastUpdatedAt: Date?
    let episodes: [PodcastFeedEpisode]
}

nonisolated struct PodcastFeedEpisode: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let publishedAt: Date?
    let durationSeconds: Int?
    let webpageURL: URL?
    let enclosureURL: URL?
    let imageURL: URL?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeType: String?
    let isExplicit: Bool?
}

nonisolated struct PodcastFeedRefreshRequest: Hashable, Sendable {
    let feedURL: URL
    let eTag: String?
    let lastModified: String?

    init(feedURL: URL, eTag: String? = nil, lastModified: String? = nil) {
        self.feedURL = feedURL
        self.eTag = eTag
        self.lastModified = lastModified
    }
}

nonisolated enum PodcastFeedRefreshResult: Hashable, Sendable {
    case updated(feed: PodcastFeed, eTag: String?, lastModified: String?)
    case notModified(eTag: String?, lastModified: String?)
}

nonisolated enum PodcastFeedError: Error, Sendable, Equatable {
    case invalidDocument(reason: String)
    case missingFeedTitle
}

extension PodcastFeedError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "The podcast feed is not valid RSS or Atom XML."
        case .missingFeedTitle:
            "The podcast feed does not include a title."
        }
    }

    var recoverySuggestion: String? {
        "Check the feed address and try again. You can also add the podcast manually."
    }
}

nonisolated protocol PodcastFeedRefreshing: Sendable {
    func refresh(_ request: PodcastFeedRefreshRequest) async throws -> PodcastFeedRefreshResult
}

nonisolated struct RSSPodcastFeedClient: PodcastFeedRefreshing {
    private let httpClient: any HTTPClient
    private let applicationName: String

    init(httpClient: any HTTPClient, applicationName: String = "WhatFun") {
        self.httpClient = httpClient
        self.applicationName = applicationName
    }

    func refresh(_ refreshRequest: PodcastFeedRefreshRequest) async throws -> PodcastFeedRefreshResult {
        var request = URLRequest(url: refreshRequest.feedURL)
        request.timeoutInterval = 30
        request.setValue(
            "application/rss+xml, application/atom+xml, application/xml, text/xml",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("\(applicationName)/1.0", forHTTPHeaderField: "User-Agent")
        if let eTag = refreshRequest.eTag?.metadataNilIfBlank {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = refreshRequest.lastModified?.metadataNilIfBlank {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let response = try await httpClient.send(request, accepting: .successfulOrNotModified)
        let eTag = response.header(named: "ETag") ?? refreshRequest.eTag
        let lastModified = response.header(named: "Last-Modified") ?? refreshRequest.lastModified

        guard response.statusCode != 304 else {
            return .notModified(eTag: eTag, lastModified: lastModified)
        }

        try Task.checkCancellation()
        let data = response.data
        let baseURL = refreshRequest.feedURL
        let feed = try await Task.detached {
            try PodcastFeedParser().parse(data, relativeTo: baseURL)
        }.value
        try Task.checkCancellation()
        return .updated(feed: feed, eTag: eTag, lastModified: lastModified)
    }
}

nonisolated struct PodcastFeedParser: Sendable {
    func parse(_ data: Data, relativeTo baseURL: URL? = nil) throws -> PodcastFeed {
        let delegate = PodcastXMLDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw PodcastFeedError.invalidDocument(
                reason: parser.parserError?.localizedDescription ?? "Unknown XML error"
            )
        }
        return try delegate.makeFeed()
    }
}

private final nonisolated class PodcastXMLDelegate: NSObject, XMLParserDelegate {
    private struct EpisodeBuilder {
        var identifier: String?
        var title: String?
        var summary: String?
        var publishedAt: Date?
        var durationSeconds: Int?
        var webpageURL: URL?
        var enclosureURL: URL?
        var imageURL: URL?
        var seasonNumber: Int?
        var episodeNumber: Int?
        var episodeType: String?
        var isExplicit: Bool?
    }

    private let baseURL: URL?
    private var elementStack = [String]()
    private var textStack = [String]()
    private var inEpisode = false
    private var currentEpisode = EpisodeBuilder()

    private var title: String?
    private var author: String?
    private var summary: String?
    private var websiteURL: URL?
    private var imageURL: URL?
    private var languageCode: String?
    private var isExplicit: Bool?
    private var lastUpdatedAt: Date?
    private var episodes = [PodcastFeedEpisode]()

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = normalized(qName ?? elementName)
        elementStack.append(element)
        textStack.append("")

        if element == "item" || element == "entry" {
            inEpisode = true
            currentEpisode = EpisodeBuilder()
            return
        }

        let local = localName(of: element)
        if local == "enclosure" || (local == "content" && element.hasPrefix("media:")) {
            if let value = attributeDict["url"], inEpisode {
                currentEpisode.enclosureURL = resolveURL(value)
            }
        } else if local == "link", let href = attributeDict["href"] {
            let relationship = attributeDict["rel"]?.lowercased()
            if inEpisode {
                if relationship == "enclosure" {
                    currentEpisode.enclosureURL = resolveURL(href)
                } else if relationship == nil || relationship == "alternate" {
                    currentEpisode.webpageURL = resolveURL(href)
                }
            } else if relationship == nil || relationship == "alternate" {
                websiteURL = resolveURL(href)
            }
        } else if element == "itunes:image", let href = attributeDict["href"] {
            if inEpisode {
                currentEpisode.imageURL = resolveURL(href)
            } else {
                imageURL = resolveURL(href)
            }
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += string
    }

    func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
        guard !textStack.isEmpty else { return }
        textStack[textStack.count - 1] += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?
    ) {
        let element = normalized(qName ?? elementName)
        let text = (textStack.popLast() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let local = localName(of: element)

        if inEpisode {
            consumeEpisodeValue(element: element, local: local, text: text)
        } else {
            consumeFeedValue(element: element, local: local, text: text)
        }

        if element == "item" || element == "entry" {
            finishEpisode()
            inEpisode = false
        }
        _ = elementStack.popLast()
    }

    func makeFeed() throws -> PodcastFeed {
        guard let title = title?.metadataNilIfBlank else {
            throw PodcastFeedError.missingFeedTitle
        }
        return PodcastFeed(
            title: title,
            author: author?.metadataNilIfBlank,
            summary: summary.map(cleanHTML)?.metadataNilIfBlank,
            websiteURL: websiteURL,
            imageURL: imageURL,
            languageCode: languageCode?.metadataNilIfBlank,
            isExplicit: isExplicit,
            lastUpdatedAt: lastUpdatedAt,
            episodes: episodes
        )
    }

    private func consumeEpisodeValue(element: String, local: String, text: String) {
        guard !text.isEmpty else { return }
        switch element {
        case "title":
            currentEpisode.title = text
        case "guid", "id":
            currentEpisode.identifier = text
        case "description", "summary", "content:encoded":
            if text.count > (currentEpisode.summary?.count ?? 0) {
                currentEpisode.summary = text
            }
        case "pubdate", "published", "updated", "dc:date":
            currentEpisode.publishedAt = parseFeedDate(text)
        case "itunes:duration":
            currentEpisode.durationSeconds = parseDuration(text)
        case "itunes:season":
            currentEpisode.seasonNumber = Int(text)
        case "itunes:episode":
            currentEpisode.episodeNumber = Int(text)
        case "itunes:episodetype":
            currentEpisode.episodeType = text
        case "itunes:explicit":
            currentEpisode.isExplicit = parseBoolean(text)
        case "link":
            currentEpisode.webpageURL = currentEpisode.webpageURL ?? resolveURL(text)
        default:
            if local == "image", currentEpisode.imageURL == nil {
                currentEpisode.imageURL = resolveURL(text)
            }
        }
    }

    private func consumeFeedValue(element: String, local: String, text: String) {
        guard !text.isEmpty else { return }
        switch element {
        case "title":
            // Ignore nested RSS image titles.
            if !elementStack.contains("image") {
                title = text
            }
        case "description", "subtitle":
            summary = text
        case "itunes:author", "managingeditor":
            author = text
        case "language":
            languageCode = text
        case "lastbuilddate", "pubdate", "updated":
            lastUpdatedAt = parseFeedDate(text)
        case "itunes:explicit":
            isExplicit = parseBoolean(text)
        case "link":
            websiteURL = websiteURL ?? resolveURL(text)
        default:
            if local == "name", elementStack.contains("author") {
                author = text
            } else if local == "url", elementStack.contains("image") {
                imageURL = resolveURL(text)
            }
        }
    }

    private func finishEpisode() {
        guard let title = currentEpisode.title?.metadataNilIfBlank else { return }
        let identifier = currentEpisode.identifier?.metadataNilIfBlank
            ?? currentEpisode.enclosureURL?.absoluteString
            ?? currentEpisode.webpageURL?.absoluteString
            ?? [title, currentEpisode.publishedAt?.ISO8601Format()].compactMap(\.self).joined(separator: "|")
        episodes.append(
            PodcastFeedEpisode(
                id: identifier,
                title: title,
                summary: currentEpisode.summary.map(cleanHTML)?.metadataNilIfBlank,
                publishedAt: currentEpisode.publishedAt,
                durationSeconds: currentEpisode.durationSeconds,
                webpageURL: currentEpisode.webpageURL,
                enclosureURL: currentEpisode.enclosureURL,
                imageURL: currentEpisode.imageURL,
                seasonNumber: currentEpisode.seasonNumber,
                episodeNumber: currentEpisode.episodeNumber,
                episodeType: currentEpisode.episodeType?.metadataNilIfBlank,
                isExplicit: currentEpisode.isExplicit
            )
        )
    }

    private func resolveURL(_ value: String) -> URL? {
        guard let value = value.metadataNilIfBlank else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func localName(of value: String) -> String {
        value.split(separator: ":").last.map(String.init) ?? value
    }

    private func parseBoolean(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes", "true", "explicit", "1": true
        case "no", "false", "clean", "0": false
        default: nil
        }
    }

    private func parseDuration(_ value: String) -> Int? {
        let components = value.split(separator: ":").compactMap { Int($0) }
        guard !components.isEmpty, components.count <= 3 else { return nil }
        return components.reversed().enumerated().reduce(0) { total, pair in
            total + pair.element * Int(pow(60.0, Double(pair.offset)))
        }
    }

    private func parseFeedDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let formats = [
            "E, d MMM yyyy HH:mm:ss Z",
            "E, dd MMM yyyy HH:mm:ss Z",
            "E, d MMM yyyy HH:mm Z",
            "dd MMM yyyy HH:mm:ss Z",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func cleanHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
