import Foundation

nonisolated enum PortableArchiveTables {
    static func document(for table: PortableArchiveTable, payload: ArchivePayload) throws -> CSVDocument {
        let rows: [[String: String]] = switch table {
        case .items:
            try payload.items.map(itemRow)
        case .units:
            payload.units.map(unitRow)
        case .cycles:
            payload.cycles.map(cycleRow)
        case .sessions:
            payload.sessions.map(sessionRow)
        case .events:
            try payload.events.map(eventRow)
        case .quotes:
            payload.quotes.map(quoteRow)
        case .lists:
            payload.lists.map(listRow)
        case .smartListRules:
            payload.smartListRules.map(smartListRuleRow)
        case .smartListRuleValues:
            payload.smartListRuleValues.map(smartListRuleValueRow)
        case .listMemberships:
            payload.listMemberships.map(listMembershipRow)
        case .tags:
            payload.tags.map(tagRow)
        case .tagMemberships:
            payload.tagMemberships.map(tagMembershipRow)
        case .artworks:
            payload.artworks.map(artworkRow)
        case .credits:
            payload.credits.map(creditRow)
        case .reminders:
            payload.reminders.map(reminderRow)
        case .externalReferences:
            payload.externalReferences.map(externalReferenceRow)
        }
        return CSVDocument(headers: PortableArchiveSchema.headers[table, default: []], rows: rows)
    }

    static func decode(
        _ document: CSVDocument,
        table: PortableArchiveTable,
        into payload: inout ArchivePayload,
    ) throws {
        for header in PortableArchiveSchema.headers[table, default: []] where !document.headers.contains(header) {
            throw PortableArchiveError.missingColumn(table: table.rawValue, column: header)
        }

        switch table {
        case .items:
            payload.items = try decodeRows(document, table: table, transform: decodeItem)
        case .units:
            payload.units = try decodeRows(document, table: table, transform: decodeUnit)
        case .cycles:
            payload.cycles = try decodeRows(document, table: table, transform: decodeCycle)
        case .sessions:
            payload.sessions = try decodeRows(document, table: table, transform: decodeSession)
        case .events:
            payload.events = try decodeRows(document, table: table, transform: decodeEvent)
        case .quotes:
            payload.quotes = try decodeRows(document, table: table, transform: decodeQuote)
        case .lists:
            payload.lists = try decodeRows(document, table: table, transform: decodeList)
        case .smartListRules:
            payload.smartListRules = try decodeRows(document, table: table, transform: decodeSmartListRule)
        case .smartListRuleValues:
            payload.smartListRuleValues = try decodeRows(document, table: table, transform: decodeSmartListRuleValue)
        case .listMemberships:
            payload.listMemberships = try decodeRows(document, table: table, transform: decodeListMembership)
        case .tags:
            payload.tags = try decodeRows(document, table: table, transform: decodeTag)
        case .tagMemberships:
            payload.tagMemberships = try decodeRows(document, table: table, transform: decodeTagMembership)
        case .artworks:
            payload.artworks = try decodeRows(document, table: table, transform: decodeArtwork)
        case .credits:
            payload.credits = try decodeRows(document, table: table, transform: decodeCredit)
        case .reminders:
            payload.reminders = try decodeRows(document, table: table, transform: decodeReminder)
        case .externalReferences:
            payload.externalReferences = try decodeRows(document, table: table, transform: decodeExternalReference)
        }
    }

    private static func decodeRows<T>(
        _ document: CSVDocument,
        table: PortableArchiveTable,
        transform: (ArchiveCSVRow) throws -> T
    ) throws -> [T] {
        try document.rows.enumerated().map { offset, values in
            try transform(ArchiveCSVRow(table: table.rawValue, rowNumber: offset + 2, values: values))
        }
    }

    private static func itemRow(_ value: ArchiveItemRecord) throws -> [String: String] {
        try [
            "id": value.id.uuidString,
            "media_kind": value.mediaKind.rawValue,
            "title": value.title,
            "subtitle": ArchiveCSVValue.string(value.subtitle),
            "sort_title": ArchiveCSVValue.string(value.sortTitle),
            "original_title": ArchiveCSVValue.string(value.originalTitle),
            "summary": ArchiveCSVValue.string(value.summary),
            "creators_json": ArchiveCSVValue.json(value.creators),
            "genres_json": ArchiveCSVValue.json(value.genres),
            "platforms_json": ArchiveCSVValue.json(value.platforms),
            "language_code": ArchiveCSVValue.string(value.languageCode),
            "page_count": ArchiveCSVValue.int(value.pageCount),
            "runtime_minutes": ArchiveCSVValue.double(value.runtimeMinutes),
            "release_date": ArchiveCSVValue.date(value.releaseDate),
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
            "archived_at": ArchiveCSVValue.date(value.archivedAt),
            "deleted_at": ArchiveCSVValue.date(value.deletedAt),
            "is_favorite": ArchiveCSVValue.bool(value.isFavorite),
            "comment": ArchiveCSVValue.string(value.comment),
            "projected_status": value.projectedStatus.rawValue,
            "projected_rating": ArchiveCSVValue.double(value.projectedRating),
            "rating_override": ArchiveCSVValue.double(value.ratingOverride),
            "projected_start_date": ArchiveCSVValue.date(value.projectedStartDate),
            "projected_completion_date": ArchiveCSVValue.date(value.projectedCompletionDate),
            "projected_repeat_count": String(value.projectedRepeatCount),
            "artwork_kind": value.artworkKind?.rawValue ?? "",
            "artwork_url": ArchiveCSVValue.string(value.artworkURL),
            "artwork_archive_path": ArchiveCSVValue.string(value.artworkArchivePath),
            "podcast_listening_style": value.podcastListeningStyle?.rawValue ?? "",
            "feed_credential_identifier": "",
            "feed_url_is_private": ArchiveCSVValue.bool(value.feedURLIsPrivate),
        ]
    }

    private static func unitRow(_ value: ArchiveUnitRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "parent_unit_id": ArchiveCSVValue.uuid(value.parentUnitID),
            "unit_kind": value.kind.rawValue,
            "title": value.title,
            "summary": ArchiveCSVValue.string(value.summary),
            "guid": ArchiveCSVValue.string(value.guid),
            "canonical_url": ArchiveCSVValue.string(value.canonicalURL),
            "sort_index": String(value.sortIndex),
            "season_number": ArchiveCSVValue.int(value.seasonNumber),
            "episode_number": ArchiveCSVValue.int(value.episodeNumber),
            "volume_number": ArchiveCSVValue.int(value.volumeNumber),
            "issue_number": ArchiveCSVValue.string(value.issueNumber),
            "released_at": ArchiveCSVValue.date(value.releasedAt),
            "duration_minutes": ArchiveCSVValue.double(value.durationMinutes),
            "page_count": ArchiveCSVValue.int(value.pageCount),
            "status": value.status.rawValue,
            "rating": ArchiveCSVValue.double(value.rating),
            "completed_at": ArchiveCSVValue.date(value.completedAt),
            "is_notable": ArchiveCSVValue.bool(value.isNotable),
            "comment": ArchiveCSVValue.string(value.comment),
            "artwork_url": ArchiveCSVValue.string(value.artworkURL),
            "artwork_archive_path": ArchiveCSVValue.string(value.artworkArchivePath),
        ]
    }

    private static func cycleRow(_ value: ArchiveCycleRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "unit_id": ArchiveCSVValue.uuid(value.unitID),
            "sequence": String(value.sequence),
            "cycle_kind": value.kind.rawValue,
            "status": value.status.rawValue,
            "started_at": ArchiveCSVValue.date(value.startedAt),
            "completed_at": ArchiveCSVValue.date(value.completedAt),
            "rating": ArchiveCSVValue.double(value.rating),
            "note": ArchiveCSVValue.string(value.note),
            "current_page": ArchiveCSVValue.int(value.currentPage),
            "total_pages": ArchiveCSVValue.int(value.totalPages),
            "elapsed_minutes": ArchiveCSVValue.double(value.elapsedMinutes),
            "playtime_minutes": ArchiveCSVValue.double(value.playtimeMinutes),
            "completion_percentage": ArchiveCSVValue.double(value.completionPercentage),
        ]
    }

    private static func sessionRow(_ value: ArchiveSessionRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "cycle_id": ArchiveCSVValue.uuid(value.cycleID),
            "unit_id": ArchiveCSVValue.uuid(value.unitID),
            "started_at": ArchiveCSVValue.date(value.startedAt),
            "ended_at": ArchiveCSVValue.date(value.endedAt),
            "logged_at": ArchiveCSVValue.date(value.loggedAt),
            "time_zone_identifier": value.timeZoneIdentifier,
            "duration_minutes": ArchiveCSVValue.double(value.durationMinutes),
            "start_page": ArchiveCSVValue.int(value.startPage),
            "end_page": ArchiveCSVValue.int(value.endPage),
            "total_pages": ArchiveCSVValue.int(value.totalPages),
            "chapter": ArchiveCSVValue.string(value.chapter),
            "start_elapsed_minutes": ArchiveCSVValue.double(value.startElapsedMinutes),
            "end_elapsed_minutes": ArchiveCSVValue.double(value.endElapsedMinutes),
            "total_runtime_minutes": ArchiveCSVValue.double(value.totalRuntimeMinutes),
            "playtime_delta_minutes": ArchiveCSVValue.double(value.playtimeDeltaMinutes),
            "cumulative_playtime_minutes": ArchiveCSVValue.double(value.cumulativePlaytimeMinutes),
            "completion_percentage": ArchiveCSVValue.double(value.completionPercentage),
            "is_completion": ArchiveCSVValue.bool(value.isCompletion),
            "rating": ArchiveCSVValue.double(value.rating),
            "note": ArchiveCSVValue.string(value.note),
        ]
    }

    private static func eventRow(_ value: ArchiveEventRecord) throws -> [String: String] {
        try [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "cycle_id": ArchiveCSVValue.uuid(value.cycleID),
            "unit_id": ArchiveCSVValue.uuid(value.unitID),
            "session_id": ArchiveCSVValue.uuid(value.sessionID),
            "event_kind": value.kind.rawValue,
            "occurred_at": ArchiveCSVValue.date(value.occurredAt),
            "time_zone_identifier": value.timeZoneIdentifier,
            "previous_status": value.previousStatus?.rawValue ?? "",
            "new_status": value.newStatus?.rawValue ?? "",
            "note": ArchiveCSVValue.string(value.note),
            "details_json": ArchiveCSVValue.json(value.details),
        ]
    }

    private static func quoteRow(_ value: ArchiveQuoteRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "unit_id": ArchiveCSVValue.uuid(value.unitID),
            "session_id": ArchiveCSVValue.uuid(value.sessionID),
            "text": value.text,
            "timestamp_seconds": ArchiveCSVValue.double(value.timestampSeconds),
            "comment": ArchiveCSVValue.string(value.comment),
            "captured_at": ArchiveCSVValue.date(value.capturedAt),
        ]
    }

    private static func listRow(_ value: ArchiveListRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "name": value.name,
            "list_kind": value.kind.rawValue,
            "match_mode": value.matchMode?.rawValue ?? "",
            "comment": ArchiveCSVValue.string(value.comment),
            "icon_name": ArchiveCSVValue.string(value.iconName),
            "color_hex": ArchiveCSVValue.string(value.colorHex),
            "sort_index": String(value.sortIndex),
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
            "archived_at": ArchiveCSVValue.date(value.archivedAt),
            "deleted_at": ArchiveCSVValue.date(value.deletedAt),
            "purge_after": ArchiveCSVValue.date(value.purgeAfter),
        ]
    }

    private static func smartListRuleRow(_ value: ArchiveSmartListRuleRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "list_id": value.listID.uuidString,
            "sort_index": String(value.sortIndex),
            "field": value.field,
            "comparison": value.comparison,
            "is_negated": ArchiveCSVValue.bool(value.isNegated),
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
        ]
    }

    private static func smartListRuleValueRow(_ value: ArchiveSmartListRuleValueRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "rule_id": value.ruleID.uuidString,
            "sort_index": String(value.sortIndex),
            "value_type": value.valueType,
            "string_value": ArchiveCSVValue.string(value.stringValue),
            "number_value": ArchiveCSVValue.double(value.numberValue),
            "date_value": ArchiveCSVValue.date(value.dateValue),
            "bool_value": value.boolValue.map(ArchiveCSVValue.bool) ?? "",
            "reference_id": ArchiveCSVValue.uuid(value.referenceID),
        ]
    }

    private static func listMembershipRow(_ value: ArchiveListMembershipRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "list_id": value.listID.uuidString,
            "item_id": value.itemID.uuidString,
            "position_rank": ArchiveCSVValue.string(value.positionRank),
            "added_at": ArchiveCSVValue.date(value.addedAt),
            "note": ArchiveCSVValue.string(value.note),
        ]
    }

    private static func tagRow(_ value: ArchiveTagRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "name": value.name,
            "color_hex": ArchiveCSVValue.string(value.colorHex),
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
        ]
    }

    private static func tagMembershipRow(_ value: ArchiveTagMembershipRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "tag_id": value.tagID.uuidString,
            "item_id": value.itemID.uuidString,
            "added_at": ArchiveCSVValue.date(value.addedAt),
            "source": ArchiveCSVValue.string(value.source),
            "sort_index": ArchiveCSVValue.int(value.sortIndex),
        ]
    }

    private static func artworkRow(_ value: ArchiveArtworkRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "unit_id": ArchiveCSVValue.uuid(value.unitID),
            "artwork_kind": value.kind.rawValue,
            "remote_url": ArchiveCSVValue.string(value.remoteURL),
            "archive_path": ArchiveCSVValue.string(value.archivePath),
            "content_hash": ArchiveCSVValue.string(value.contentHash),
            "mime_type": ArchiveCSVValue.string(value.mimeType),
            "pixel_width": ArchiveCSVValue.int(value.pixelWidth),
            "pixel_height": ArchiveCSVValue.int(value.pixelHeight),
            "aspect_ratio": ArchiveCSVValue.double(value.aspectRatio),
            "provider": ArchiveCSVValue.string(value.provider),
            "attribution_text": ArchiveCSVValue.string(value.attributionText),
            "attribution_url": ArchiveCSVValue.string(value.attributionURL),
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
        ]
    }

    private static func creditRow(_ value: ArchiveCreditRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "unit_id": ArchiveCSVValue.uuid(value.unitID),
            "name": value.name,
            "role": value.role,
            "sort_index": String(value.sortIndex),
            "external_person_id": ArchiveCSVValue.string(value.externalPersonID),
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
        ]
    }

    private static func reminderRow(_ value: ArchiveReminderRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": value.itemID.uuidString,
            "fire_at": ArchiveCSVValue.date(value.fireAt),
            "time_zone_identifier": value.timeZoneIdentifier,
            "state": value.state.rawValue,
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
        ]
    }

    private static func externalReferenceRow(_ value: ArchiveExternalReferenceRecord) -> [String: String] {
        [
            "id": value.id.uuidString,
            "item_id": ArchiveCSVValue.uuid(value.itemID),
            "unit_id": ArchiveCSVValue.uuid(value.unitID),
            "provider": value.provider,
            "record_kind": value.recordKind,
            "external_id": value.externalID,
            "canonical_url": ArchiveCSVValue.string(value.canonicalURL),
            "last_fetched_at": ArchiveCSVValue.date(value.lastFetchedAt),
            "etag": ArchiveCSVValue.string(value.etag),
            "last_modified": ArchiveCSVValue.string(value.lastModified),
            "payload_hash": ArchiveCSVValue.string(value.payloadHash),
            "payload_version": ArchiveCSVValue.string(value.payloadVersion),
            "attribution_text": ArchiveCSVValue.string(value.attributionText),
            "attribution_url": ArchiveCSVValue.string(value.attributionURL),
            "is_active_feed": ArchiveCSVValue.bool(value.isActiveFeed),
            "is_private_feed": ArchiveCSVValue.bool(value.isPrivateFeed),
            "credential_keychain_id": "",
            "created_at": ArchiveCSVValue.date(value.createdAt),
            "updated_at": ArchiveCSVValue.date(value.updatedAt),
        ]
    }
}

private nonisolated enum ArchiveCSVValue {
    static func string(_ value: String?) -> String { value ?? "" }
    static func uuid(_ value: UUID?) -> String { value?.uuidString ?? "" }
    static func date(_ value: Date?) -> String { value.map(ArchiveDateCodec.string) ?? "" }
    static func int(_ value: Int?) -> String { value.map(String.init) ?? "" }
    static func double(_ value: Double?) -> String { value.map { String($0) } ?? "" }
    static func bool(_ value: Bool) -> String { value ? "true" : "false" }

    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private nonisolated extension PortableArchiveTables {
    static func decodeItem(_ row: ArchiveCSVRow) throws -> ArchiveItemRecord {
        try ArchiveItemRecord(
            id: row.uuid("id"),
            mediaKind: row.enumValue("media_kind"),
            title: row.string("title"),
            subtitle: row.optionalString("subtitle"),
            sortTitle: row.optionalString("sort_title"),
            originalTitle: row.optionalString("original_title"),
            summary: row.optionalString("summary"),
            creators: row.json("creators_json", as: [String].self),
            genres: row.json("genres_json", as: [String].self),
            platforms: row.json("platforms_json", as: [String].self),
            languageCode: row.optionalString("language_code"),
            pageCount: row.optionalInt("page_count"),
            runtimeMinutes: row.optionalDouble("runtime_minutes"),
            releaseDate: row.optionalDate("release_date"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
            archivedAt: row.optionalDate("archived_at"),
            deletedAt: row.optionalDate("deleted_at"),
            isFavorite: row.bool("is_favorite"),
            comment: row.optionalString("comment"),
            projectedStatus: row.enumValue("projected_status"),
            projectedRating: row.optionalDouble("projected_rating"),
            ratingOverride: row.optionalDouble("rating_override"),
            projectedStartDate: row.optionalDate("projected_start_date"),
            projectedCompletionDate: row.optionalDate("projected_completion_date"),
            projectedRepeatCount: row.int("projected_repeat_count"),
            artworkKind: row.optionalEnumValue("artwork_kind"),
            artworkURL: row.optionalString("artwork_url"),
            artworkArchivePath: row.optionalString("artwork_archive_path"),
            podcastListeningStyle: row.optionalEnumValue("podcast_listening_style"),
            feedCredentialIdentifier: row.optionalString("feed_credential_identifier"),
            feedURLIsPrivate: row.bool("feed_url_is_private"),
        )
    }

    static func decodeUnit(_ row: ArchiveCSVRow) throws -> ArchiveUnitRecord {
        try ArchiveUnitRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            parentUnitID: row.optionalUUID("parent_unit_id"),
            kind: row.enumValue("unit_kind"),
            title: row.string("title"),
            summary: row.optionalString("summary"),
            guid: row.optionalString("guid"),
            canonicalURL: row.optionalString("canonical_url"),
            sortIndex: row.int("sort_index"),
            seasonNumber: row.optionalInt("season_number"),
            episodeNumber: row.optionalInt("episode_number"),
            volumeNumber: row.optionalInt("volume_number"),
            issueNumber: row.optionalString("issue_number"),
            releasedAt: row.optionalDate("released_at"),
            durationMinutes: row.optionalDouble("duration_minutes"),
            pageCount: row.optionalInt("page_count"),
            status: row.enumValue("status"),
            rating: row.optionalDouble("rating"),
            completedAt: row.optionalDate("completed_at"),
            isNotable: row.bool("is_notable"),
            comment: row.optionalString("comment"),
            artworkURL: row.optionalString("artwork_url"),
            artworkArchivePath: row.optionalString("artwork_archive_path"),
        )
    }

    static func decodeCycle(_ row: ArchiveCSVRow) throws -> ArchiveCycleRecord {
        try ArchiveCycleRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            unitID: row.optionalUUID("unit_id"),
            sequence: row.int("sequence"),
            kind: row.enumValue("cycle_kind"),
            status: row.enumValue("status"),
            startedAt: row.optionalDate("started_at"),
            completedAt: row.optionalDate("completed_at"),
            rating: row.optionalDouble("rating"),
            note: row.optionalString("note"),
            currentPage: row.optionalInt("current_page"),
            totalPages: row.optionalInt("total_pages"),
            elapsedMinutes: row.optionalDouble("elapsed_minutes"),
            playtimeMinutes: row.optionalDouble("playtime_minutes"),
            completionPercentage: row.optionalDouble("completion_percentage"),
        )
    }

    static func decodeSession(_ row: ArchiveCSVRow) throws -> ArchiveSessionRecord {
        try ArchiveSessionRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            cycleID: row.optionalUUID("cycle_id"),
            unitID: row.optionalUUID("unit_id"),
            startedAt: row.date("started_at"),
            endedAt: row.optionalDate("ended_at"),
            loggedAt: row.date("logged_at"),
            timeZoneIdentifier: row.string("time_zone_identifier"),
            durationMinutes: row.optionalDouble("duration_minutes"),
            startPage: row.optionalInt("start_page"),
            endPage: row.optionalInt("end_page"),
            totalPages: row.optionalInt("total_pages"),
            chapter: row.optionalString("chapter"),
            startElapsedMinutes: row.optionalDouble("start_elapsed_minutes"),
            endElapsedMinutes: row.optionalDouble("end_elapsed_minutes"),
            totalRuntimeMinutes: row.optionalDouble("total_runtime_minutes"),
            playtimeDeltaMinutes: row.optionalDouble("playtime_delta_minutes"),
            cumulativePlaytimeMinutes: row.optionalDouble("cumulative_playtime_minutes"),
            completionPercentage: row.optionalDouble("completion_percentage"),
            isCompletion: row.bool("is_completion"),
            rating: row.optionalDouble("rating"),
            note: row.optionalString("note"),
        )
    }

    static func decodeEvent(_ row: ArchiveCSVRow) throws -> ArchiveEventRecord {
        try ArchiveEventRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            cycleID: row.optionalUUID("cycle_id"),
            unitID: row.optionalUUID("unit_id"),
            sessionID: row.optionalUUID("session_id"),
            kind: row.enumValue("event_kind"),
            occurredAt: row.date("occurred_at"),
            timeZoneIdentifier: row.string("time_zone_identifier"),
            previousStatus: row.optionalEnumValue("previous_status"),
            newStatus: row.optionalEnumValue("new_status"),
            note: row.optionalString("note"),
            details: row.json("details_json", as: [String: String].self),
        )
    }

    static func decodeQuote(_ row: ArchiveCSVRow) throws -> ArchiveQuoteRecord {
        try ArchiveQuoteRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            unitID: row.optionalUUID("unit_id"),
            sessionID: row.optionalUUID("session_id"),
            text: row.string("text"),
            timestampSeconds: row.optionalDouble("timestamp_seconds"),
            comment: row.optionalString("comment"),
            capturedAt: row.date("captured_at"),
        )
    }

    static func decodeList(_ row: ArchiveCSVRow) throws -> ArchiveListRecord {
        try ArchiveListRecord(
            id: row.uuid("id"),
            name: row.string("name"),
            kind: row.enumValue("list_kind"),
            matchMode: row.optionalEnumValue("match_mode"),
            comment: row.optionalString("comment"),
            iconName: row.optionalString("icon_name"),
            colorHex: row.optionalString("color_hex"),
            sortIndex: row.int("sort_index"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
            archivedAt: row.optionalDate("archived_at"),
            deletedAt: row.optionalDate("deleted_at"),
            purgeAfter: row.optionalDate("purge_after"),
        )
    }

    static func decodeSmartListRule(_ row: ArchiveCSVRow) throws -> ArchiveSmartListRuleRecord {
        try ArchiveSmartListRuleRecord(
            id: row.uuid("id"),
            listID: row.uuid("list_id"),
            sortIndex: row.int("sort_index"),
            field: row.string("field"),
            comparison: row.string("comparison"),
            isNegated: row.bool("is_negated"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
        )
    }

    static func decodeSmartListRuleValue(_ row: ArchiveCSVRow) throws -> ArchiveSmartListRuleValueRecord {
        try ArchiveSmartListRuleValueRecord(
            id: row.uuid("id"),
            ruleID: row.uuid("rule_id"),
            sortIndex: row.int("sort_index"),
            valueType: row.string("value_type"),
            stringValue: row.optionalString("string_value"),
            numberValue: row.optionalDouble("number_value"),
            dateValue: row.optionalDate("date_value"),
            boolValue: row.optionalBool("bool_value"),
            referenceID: row.optionalUUID("reference_id"),
        )
    }

    static func decodeListMembership(_ row: ArchiveCSVRow) throws -> ArchiveListMembershipRecord {
        try ArchiveListMembershipRecord(
            id: row.uuid("id"),
            listID: row.uuid("list_id"),
            itemID: row.uuid("item_id"),
            positionRank: row.optionalString("position_rank"),
            addedAt: row.date("added_at"),
            note: row.optionalString("note"),
        )
    }

    static func decodeTag(_ row: ArchiveCSVRow) throws -> ArchiveTagRecord {
        try ArchiveTagRecord(
            id: row.uuid("id"),
            name: row.string("name"),
            colorHex: row.optionalString("color_hex"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
        )
    }

    static func decodeTagMembership(_ row: ArchiveCSVRow) throws -> ArchiveTagMembershipRecord {
        try ArchiveTagMembershipRecord(
            id: row.uuid("id"),
            tagID: row.uuid("tag_id"),
            itemID: row.uuid("item_id"),
            addedAt: row.date("added_at"),
            source: row.optionalString("source"),
            sortIndex: row.optionalInt("sort_index"),
        )
    }

    static func decodeArtwork(_ row: ArchiveCSVRow) throws -> ArchiveArtworkRecord {
        try ArchiveArtworkRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            unitID: row.optionalUUID("unit_id"),
            kind: row.enumValue("artwork_kind"),
            remoteURL: row.optionalString("remote_url"),
            archivePath: row.optionalString("archive_path"),
            imageData: nil,
            contentHash: row.optionalString("content_hash"),
            mimeType: row.optionalString("mime_type"),
            pixelWidth: row.optionalInt("pixel_width"),
            pixelHeight: row.optionalInt("pixel_height"),
            aspectRatio: row.optionalDouble("aspect_ratio"),
            provider: row.optionalString("provider"),
            attributionText: row.optionalString("attribution_text"),
            attributionURL: row.optionalString("attribution_url"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
        )
    }

    static func decodeCredit(_ row: ArchiveCSVRow) throws -> ArchiveCreditRecord {
        try ArchiveCreditRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            unitID: row.optionalUUID("unit_id"),
            name: row.string("name"),
            role: row.string("role"),
            sortIndex: row.int("sort_index"),
            externalPersonID: row.optionalString("external_person_id"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
        )
    }

    static func decodeReminder(_ row: ArchiveCSVRow) throws -> ArchiveReminderRecord {
        try ArchiveReminderRecord(
            id: row.uuid("id"),
            itemID: row.uuid("item_id"),
            fireAt: row.date("fire_at"),
            timeZoneIdentifier: row.string("time_zone_identifier"),
            state: row.enumValue("state"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
        )
    }

    static func decodeExternalReference(_ row: ArchiveCSVRow) throws -> ArchiveExternalReferenceRecord {
        try ArchiveExternalReferenceRecord(
            id: row.uuid("id"),
            itemID: row.optionalUUID("item_id"),
            unitID: row.optionalUUID("unit_id"),
            provider: row.string("provider"),
            recordKind: row.string("record_kind"),
            externalID: row.string("external_id"),
            canonicalURL: row.optionalString("canonical_url"),
            lastFetchedAt: row.optionalDate("last_fetched_at"),
            etag: row.optionalString("etag"),
            lastModified: row.optionalString("last_modified"),
            payloadHash: row.optionalString("payload_hash"),
            payloadVersion: row.optionalString("payload_version"),
            attributionText: row.optionalString("attribution_text"),
            attributionURL: row.optionalString("attribution_url"),
            isActiveFeed: row.bool("is_active_feed"),
            isPrivateFeed: row.bool("is_private_feed"),
            credentialKeychainID: row.optionalString("credential_keychain_id"),
            createdAt: row.date("created_at"),
            updatedAt: row.date("updated_at"),
        )
    }
}

private nonisolated struct ArchiveCSVRow {
    var table: String
    var rowNumber: Int
    var values: [String: String]

    func string(_ column: String) -> String {
        values[column, default: ""]
    }

    func optionalString(_ column: String) -> String? {
        let value = string(column)
        return value.isEmpty ? nil : value
    }

    func uuid(_ column: String) throws -> UUID {
        let value = string(column)
        guard let uuid = UUID(uuidString: value) else { throw invalid(column, value) }
        return uuid
    }

    func optionalUUID(_ column: String) throws -> UUID? {
        guard let value = optionalString(column) else { return nil }
        guard let uuid = UUID(uuidString: value) else { throw invalid(column, value) }
        return uuid
    }

    func date(_ column: String) throws -> Date {
        let value = string(column)
        guard let date = ArchiveDateCodec.date(from: value) else { throw invalid(column, value) }
        return date
    }

    func optionalDate(_ column: String) throws -> Date? {
        guard let value = optionalString(column) else { return nil }
        guard let date = ArchiveDateCodec.date(from: value) else { throw invalid(column, value) }
        return date
    }

    func int(_ column: String) throws -> Int {
        let value = string(column)
        guard let result = Int(value) else { throw invalid(column, value) }
        return result
    }

    func optionalInt(_ column: String) throws -> Int? {
        guard let value = optionalString(column) else { return nil }
        guard let result = Int(value) else { throw invalid(column, value) }
        return result
    }

    func optionalDouble(_ column: String) throws -> Double? {
        guard let value = optionalString(column) else { return nil }
        guard let result = Double(value), result.isFinite else { throw invalid(column, value) }
        return result
    }

    func bool(_ column: String) throws -> Bool {
        let value = string(column)
        switch value.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: throw invalid(column, value)
        }
    }

    func optionalBool(_ column: String) throws -> Bool? {
        guard optionalString(column) != nil else { return nil }
        return try bool(column)
    }

    func enumValue<T>(_ column: String) throws -> T where T: RawRepresentable, T.RawValue == String {
        let value = string(column)
        guard let result = T(rawValue: value) else { throw invalid(column, value) }
        return result
    }

    func optionalEnumValue<T>(_ column: String) throws -> T? where T: RawRepresentable, T.RawValue == String {
        guard let value = optionalString(column) else { return nil }
        guard let result = T(rawValue: value) else { throw invalid(column, value) }
        return result
    }

    func json<T: Decodable>(_ column: String, as type: T.Type) throws -> T {
        let value = string(column)
        do {
            return try JSONDecoder().decode(type, from: Data(value.utf8))
        } catch {
            throw invalid(column, value)
        }
    }

    private func invalid(_ column: String, _ value: String) -> PortableArchiveError {
        PortableArchiveError.invalidField(table: table, row: rowNumber, column: column, value: value)
    }
}
