import Foundation

nonisolated enum PortableArchiveSchema {
    static let headers: [PortableArchiveTable: [String]] = [
        .items: [
            "id", "media_kind", "title", "subtitle", "sort_title", "original_title", "summary",
            "creators_json", "genres_json", "platforms_json", "release_date", "created_at", "updated_at",
            "language_code", "page_count", "runtime_minutes",
            "archived_at", "deleted_at", "is_favorite", "comment", "projected_status",
            "projected_rating", "rating_override", "projected_start_date",
            "projected_completion_date", "projected_repeat_count", "artwork_kind",
            "artwork_url", "artwork_archive_path", "podcast_listening_style",
            "feed_credential_identifier", "feed_url_is_private",
        ],
        .units: [
            "id", "item_id", "parent_unit_id", "unit_kind", "title", "summary", "guid", "canonical_url", "sort_index",
            "season_number", "episode_number", "volume_number", "issue_number", "released_at",
            "duration_minutes", "page_count", "status", "rating", "completed_at", "is_notable",
            "comment", "artwork_url", "artwork_archive_path",
        ],
        .cycles: [
            "id", "item_id", "unit_id", "sequence", "cycle_kind", "status", "started_at",
            "completed_at", "rating", "note", "current_page", "total_pages", "elapsed_minutes",
            "playtime_minutes", "completion_percentage",
        ],
        .sessions: [
            "id", "item_id", "cycle_id", "unit_id", "started_at", "ended_at", "logged_at",
            "time_zone_identifier", "duration_minutes", "start_page", "end_page", "total_pages",
            "chapter", "start_elapsed_minutes", "end_elapsed_minutes", "total_runtime_minutes",
            "playtime_delta_minutes", "cumulative_playtime_minutes", "completion_percentage",
            "is_completion", "rating", "note",
        ],
        .events: [
            "id", "item_id", "cycle_id", "unit_id", "session_id", "event_kind", "occurred_at",
            "time_zone_identifier", "previous_status", "new_status", "note", "details_json",
        ],
        .quotes: [
            "id", "item_id", "unit_id", "session_id", "text", "timestamp_seconds", "comment",
            "captured_at",
        ],
        .lists: [
            "id", "name", "list_kind", "match_mode", "comment", "icon_name", "color_hex", "sort_index",
            "created_at", "updated_at", "archived_at", "deleted_at", "purge_after",
        ],
        .smartListRules: [
            "id", "list_id", "sort_index", "field", "comparison", "is_negated", "created_at", "updated_at",
        ],
        .smartListRuleValues: [
            "id", "rule_id", "sort_index", "value_type", "string_value", "number_value", "date_value",
            "bool_value", "reference_id",
        ],
        .listMemberships: [
            "id", "list_id", "item_id", "position_rank", "added_at", "note",
        ],
        .tags: [
            "id", "name", "color_hex", "created_at", "updated_at",
        ],
        .tagMemberships: [
            "id", "tag_id", "item_id", "added_at", "source", "sort_index",
        ],
        .artworks: [
            "id", "item_id", "unit_id", "artwork_kind", "remote_url", "archive_path", "content_hash",
            "mime_type", "pixel_width", "pixel_height", "aspect_ratio", "provider", "attribution_text",
            "attribution_url", "created_at", "updated_at",
        ],
        .credits: [
            "id", "item_id", "unit_id", "name", "role", "sort_index", "external_person_id", "created_at",
            "updated_at",
        ],
        .reminders: [
            "id", "item_id", "fire_at", "time_zone_identifier", "state", "created_at", "updated_at",
        ],
        .externalReferences: [
            "id", "item_id", "unit_id", "provider", "record_kind", "external_id", "canonical_url",
            "last_fetched_at", "etag", "last_modified", "payload_hash", "payload_version", "attribution_text",
            "attribution_url", "is_active_feed", "is_private_feed", "credential_keychain_id", "created_at",
            "updated_at",
        ],
    ]

    static var documentation: String {
        var sections = [
            "# WhatFun portable archive schema v\(PortableArchiveManifest.currentSchemaVersion)",
            "",
            "This directory is the long-term, app-neutral archive of record for WhatFun. " +
                "Every table is UTF-8 RFC 4180 CSV with a header row and CRLF record endings.",
            "",
            "## Conventions",
            "",
            "- IDs are lowercase-insensitive UUID strings and remain stable across exports.",
            "- Foreign-key columns end in `_id`; empty means no relationship.",
            "- Timestamps are ISO 8601 UTC instants with fractional seconds. A session's original " +
                "IANA time zone is stored in `time_zone_identifier`.",
            "- Ratings use 0.5 steps on a 0.5–5.0 scale. Empty means unrated.",
            "- Progress values are explicit pages, elapsed minutes, playtime minutes, or percentages.",
            "- Columns ending in `_json` contain a JSON array or object inside one CSV field.",
            "- Private podcast feed URLs and Keychain identifiers are intentionally redacted.",
            "- `manifest.json` lists SHA-256 checksums and row counts for integrity checking.",
            "",
            "## Stable value vocabulary",
            "",
            "- `media_kind`: `book`, `comic`, `movie`, `television`, `game`, `podcast`.",
            "- status fields: `planned`, `in_progress`, `paused`, `completed`, `dropped`, " +
                "`rereading`, `rewatching`, `replaying`, `following`, `archived`.",
            "- `unit_kind`: `season`, `episode`, `volume`, `issue` (the owning item's media kind " +
                "disambiguates TV and podcast episodes).",
            "- `cycle_kind`: `initial`, `installment_continuation`, `reread`, `rewatch`, `replay`, `repeat_consumption`.",
            "- `event_kind`: `created`, `started`, `status_changed`, `progress_updated`, " +
                "`marked_completed`, `completion_reversed`, `archived`, `restored`, `moved_to_trash`.",
            "- `list_kind`: `manual`, `smart`; `match_mode`: `all`, `any`.",
            "- Smart-rule `field` and `comparison` are stable snake_case identifiers. " +
                "`value_type` is `string`, `number`, `date`, `bool`, or `reference`; the matching " +
                "typed column stores its value.",
            "",
            "## Join map",
            "",
            "`items` is the root. `units` joins by `item_id` and nests with `parent_unit_id`. " +
                "Cycles, sessions, events, quotes, list memberships, tag memberships, and " +
                "artwork, credit, reminder, and external-reference records join using their named UUID columns.",
            "",
        ]

        let purposes: [PortableArchiveTable: String] = [
            .items: "Canonical library titles and rebuildable current projections.",
            .units: "TV seasons/episodes, comic volumes/issues, and podcast episodes.",
            .cycles: "Intentional reads, watches, plays, and repeat passes.",
            .sessions: "Timestamped consumption facts with optional progress.",
            .events: "Immutable lifecycle and status facts.",
            .quotes: "Notable podcast or media quotes with optional timestamps.",
            .lists: "User-created manual and smart lists, including smart-list match mode.",
            .smartListRules: "Ordered predicates for user-created smart lists.",
            .smartListRuleValues: "Ordered typed values and UUID references belonging to smart-list predicates.",
            .listMemberships: "Many-to-many list membership without duplicated item data.",
            .tags: "User-created tags.",
            .tagMemberships: "Many-to-many tag membership.",
            .artworks: "All artwork identities; user-owned image bytes live at the checksummed archive path.",
            .credits: "Ordered creator, cast, author, developer, and other credited names.",
            .reminders: "Semantic start reminders; device notification identifiers are regenerated on restore.",
            .externalReferences: "Provider identities, public URLs, refresh validators, and attribution.",
        ]

        for table in PortableArchiveTable.allCases {
            sections.append("## `\(table.filename)`")
            sections.append("")
            sections.append(purposes[table, default: "Archive records."])
            sections.append("")
            sections.append(headers[table, default: []].map { "`\($0)`" }.joined(separator: ", "))
            sections.append("")
        }
        return sections.joined(separator: "\n") + "\n"
    }
}
