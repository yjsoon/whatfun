import Foundation
import SwiftData

@Model
final class ArtworkAsset {
    #Index<ArtworkAsset>([\.rootItemID], [\.contentHash])

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var unitID: UUID?
    var kindRaw: String = ArtworkKind.providerRemote.rawValue
    var remoteURLString: String?
    var cacheKey: String?

    @Attribute(.externalStorage)
    var imageData: Data?

    var contentHash: String?
    var mimeType: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var aspectRatio: Double?
    var providerRaw: String?
    var attributionText: String?
    var attributionURLString: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var ownerItem: LibraryItem?
    var unit: ContentUnit?

    init(
        id: UUID = UUID(),
        ownerItem: LibraryItem,
        unit: ContentUnit? = nil,
        kind: ArtworkKind,
        remoteURLString: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rootItemID = ownerItem.id
        self.unitID = unit?.id
        self.kindRaw = kind.rawValue
        self.remoteURLString = remoteURLString
        self.imageData = imageData
        self.ownerItem = ownerItem
        self.unit = unit
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var kind: ArtworkKind {
        get { ArtworkKind.value(for: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class ExternalReference {
    #Index<ExternalReference>(
        [\.providerRaw, \.externalID],
        [\.rootItemID],
        [\.unitID]
    )

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var unitID: UUID?
    var providerRaw: String = "manual"
    var recordKindRaw: String = "item"
    var externalID: String = ""
    var canonicalURLString: String?
    var lastFetchedAt: Date?
    var etag: String?
    var lastModified: String?
    var payloadHash: String?
    var payloadVersion: String?
    var attributionText: String?
    var attributionURLString: String?

    // Podcast feeds may be public or represented by an opaque Keychain identifier.
    var isActiveFeed: Bool = false
    var isPrivateFeed: Bool = false
    var credentialKeychainID: String?

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var ownerItem: LibraryItem?
    var unit: ContentUnit?

    init(
        id: UUID = UUID(),
        ownerItem: LibraryItem,
        unit: ContentUnit? = nil,
        providerRaw: String,
        recordKindRaw: String,
        externalID: String,
        canonicalURLString: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rootItemID = ownerItem.id
        self.unitID = unit?.id
        self.providerRaw = providerRaw
        self.recordKindRaw = recordKindRaw
        self.externalID = externalID
        self.canonicalURLString = canonicalURLString
        self.ownerItem = ownerItem
        self.unit = unit
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

@Model
final class Credit {
    #Index<Credit>([\.rootItemID, \.sortOrder], [\.normalizedName])

    var id: UUID = UUID()
    var rootItemID: UUID = UUID()
    var unitID: UUID?
    var name: String = ""
    var normalizedName: String = ""
    var roleRaw: String = "creator"
    var sortOrder: Int = 0
    var externalPersonID: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var ownerItem: LibraryItem?
    var unit: ContentUnit?

    init(
        id: UUID = UUID(),
        ownerItem: LibraryItem,
        unit: ContentUnit? = nil,
        name: String,
        roleRaw: String,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rootItemID = ownerItem.id
        self.unitID = unit?.id
        self.name = name
        self.normalizedName = LibraryItem.normalize(name)
        self.roleRaw = roleRaw
        self.sortOrder = sortOrder
        self.ownerItem = ownerItem
        self.unit = unit
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
