import Foundation

nonisolated struct OPMLPodcastImporter: Sendable {
    var maximumSubscriptions = 20000
    var maximumBytes = 25 * 1024 * 1024

    func stage(_ data: Data, sourceFilename: String? = nil) throws -> StagedImportBatch {
        guard data.count <= maximumBytes else {
            throw ImportStagingError.fileTooLarge(limitBytes: maximumBytes)
        }
        let delegate = OPMLDelegate(maximumSubscriptions: maximumSubscriptions)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        let succeeded = parser.parse()
        if delegate.exceededLimit {
            throw ImportStagingError.tooManyRows(limit: maximumSubscriptions)
        }
        guard succeeded else {
            throw ImportStagingError.parserFailure(
                parser.parserError?.localizedDescription ?? "The OPML document could not be parsed.",
            )
        }
        guard !delegate.rows.isEmpty else {
            throw ImportStagingError.unsupportedFormat("No podcast feed outlines were found in the OPML document.")
        }

        return StagedImportBatch(
            source: .opml,
            sourceFilename: sourceFilename,
            rows: delegate.rows,
            warnings: delegate.batchWarnings,
        )
    }
}

private final nonisolated class OPMLDelegate: NSObject, XMLParserDelegate {
    let maximumSubscriptions: Int
    var rows: [StagedImportRow] = []
    var batchWarnings: [ImportWarning] = []
    var exceededLimit = false

    private var categoryPath: [String] = []
    private var outlineCategoryStack: [Bool] = []
    private var seenFeedURLs: Set<String> = []

    init(maximumSubscriptions: Int) {
        self.maximumSubscriptions = maximumSubscriptions
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:],
    ) {
        guard elementName.caseInsensitiveCompare("outline") == .orderedSame else { return }
        let attributes = Dictionary(uniqueKeysWithValues: attributeDict.map { ($0.key.lowercased(), $0.value) })
        let rawTitle = attributes["title"] ?? attributes["text"]
        let feedURL = attributes["xmlurl"]

        if let feedURL {
            outlineCategoryStack.append(false)
            if rows.count >= maximumSubscriptions {
                exceededLimit = true
                parser.abortParsing()
                return
            }
            stageFeed(
                rawTitle: rawTitle,
                feedURL: feedURL,
                websiteURL: attributes["htmlurl"],
                author: attributes["author"],
            )
        } else {
            let isCategory = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            outlineCategoryStack.append(isCategory)
            if isCategory, let rawTitle {
                categoryPath.append(rawTitle.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
    ) {
        guard elementName.caseInsensitiveCompare("outline") == .orderedSame,
              let wasCategory = outlineCategoryStack.popLast() else { return }
        if wasCategory { _ = categoryPath.popLast() }
    }

    private func stageFeed(rawTitle: String?, feedURL: String, websiteURL: String?, author: String?) {
        let normalizedFeedURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let deduplicationKey = normalizedFeedURL.lowercased()
        guard seenFeedURLs.insert(deduplicationKey).inserted else {
            batchWarnings.append(ImportWarning(
                code: .duplicateSourceRow,
                severity: .information,
                message: "A duplicate podcast feed was ignored.",
                field: "xmlUrl",
                rawValue: nil,
            ))
            return
        }

        let parsedURL = URL(string: normalizedFeedURL)
        let scheme = parsedURL?.scheme?.lowercased()
        let isHTTPURL = (scheme == "https" || scheme == "http") && parsedURL?.host()?.isEmpty == false
        let cleanTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? parsedURL?.host()
            ?? "Untitled Podcast"

        var warnings: [ImportWarning] = []
        var ambiguities: [ImportAmbiguity] = []
        if !isHTTPURL {
            warnings.append(ImportWarning(
                code: .invalidURL,
                severity: .warning,
                message: "The feed URL is not a valid HTTP or HTTPS URL.",
                field: "xmlUrl",
                rawValue: normalizedFeedURL,
            ))
            ambiguities.append(ImportAmbiguity(
                field: "xmlUrl",
                message: "Confirm or replace this feed URL.",
                candidates: [normalizedFeedURL],
            ))
        }
        if cleanTitle == nil || cleanTitle?.isEmpty == true {
            warnings.append(ImportWarning(
                code: .missingTitle,
                severity: .information,
                message: "The title was inferred from the feed host.",
                field: "title",
                rawValue: nil,
            ))
        }

        let proposal = PodcastSubscriptionImportProposal(
            title: title,
            author: author,
            feedURL: normalizedFeedURL,
            websiteURL: websiteURL,
            listeningStyle: .keepAround,
            status: .following,
            categoryPath: categoryPath,
        )
        rows.append(StagedImportRow(
            sourceRowNumber: rows.count + 1,
            rawFields: [
                "title": rawTitle ?? "",
                "xmlUrl": normalizedFeedURL,
                "htmlUrl": websiteURL ?? "",
                "author": author ?? "",
            ],
            proposal: .podcastSubscription(proposal),
            confidence: isHTTPURL ? 0.98 : 0.65,
            warnings: warnings,
            ambiguities: ambiguities,
        ))
    }
}
