import Foundation

nonisolated protocol MetadataProvider: Sendable {
    var id: MetadataProviderID { get }
    var supportedMediaTypes: Set<MetadataMediaType> { get }
    var attribution: MetadataAttribution? { get }
    var availability: MetadataProviderAvailability { get }

    func search(_ request: MetadataSearchRequest) async throws -> MetadataSearchPage
    func details(for result: MetadataSearchResult) async throws -> MetadataItemDetails
}

nonisolated extension MetadataProvider {
    func validate(_ request: MetadataSearchRequest) throws {
        guard !request.trimmedQuery.isEmpty else {
            throw MetadataProviderError.emptyQuery
        }
        guard supportedMediaTypes.contains(request.mediaType) else {
            throw MetadataProviderError.unsupportedMediaType(
                provider: id,
                mediaType: request.mediaType
            )
        }
        if case let .credentialRequired(instructions, _) = availability {
            throw MetadataProviderError.missingCredential(
                provider: id,
                instructions: instructions
            )
        }
    }

    func validateOwnership(of result: MetadataSearchResult) throws {
        guard result.id.provider == id, supportedMediaTypes.contains(result.mediaType) else {
            throw MetadataProviderError.unsupportedMediaType(
                provider: id,
                mediaType: result.mediaType
            )
        }
        if case let .credentialRequired(instructions, _) = availability {
            throw MetadataProviderError.missingCredential(
                provider: id,
                instructions: instructions
            )
        }
    }

    func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MetadataProviderError.invalidResponse(
                provider: id,
                reason: String(describing: error)
            )
        }
    }
}

/// A provider registry lets Search choose a source by media type without knowing
/// about credentials or provider-specific endpoints.
nonisolated struct MetadataProviderCatalog: Sendable {
    let providers: [any MetadataProvider]

    init(providers: [any MetadataProvider]) {
        self.providers = providers
    }

    func providers(for mediaType: MetadataMediaType) -> [any MetadataProvider] {
        providers.filter { $0.supportedMediaTypes.contains(mediaType) }
    }

    func primaryProvider(for mediaType: MetadataMediaType) -> (any MetadataProvider)? {
        providers(for: mediaType).first
    }
}

nonisolated struct MetadataServiceBundle: Sendable {
    let catalog: MetadataProviderCatalog
    let podcastFeeds: any PodcastFeedRefreshing
}

/// The only bridge from Config into the Sendable networking layer. Because the
/// project uses MainActor default isolation, construction happens on MainActor;
/// requests themselves run through nonisolated Sendable clients.
enum MetadataServiceFactory {
    static func live(httpClient: any HTTPClient = URLSessionHTTPClient()) -> MetadataServiceBundle {
        let providers: [any MetadataProvider] = [
            TMDBMetadataProvider(
                httpClient: httpClient,
                readAccessToken: Config.tmdbReadAccessToken
            ),
            OpenLibraryMetadataProvider(
                httpClient: httpClient,
                applicationName: Config.applicationName,
                contactEmail: Config.openLibraryContactEmail
            ),
            RAWGMetadataProvider(
                httpClient: httpClient,
                apiKey: Config.rawgAPIKey
            ),
            ApplePodcastMetadataProvider(httpClient: httpClient),
        ]

        return MetadataServiceBundle(
            catalog: MetadataProviderCatalog(providers: providers),
            podcastFeeds: RSSPodcastFeedClient(httpClient: httpClient)
        )
    }
}

nonisolated func metadataYear(from value: String?) -> Int? {
    guard let value, value.count >= 4 else { return nil }
    return Int(value.prefix(4))
}

nonisolated func metadataURL(_ value: String?) -> URL? {
    guard let value = value?.metadataNilIfBlank else { return nil }
    return URL(string: value)
}
