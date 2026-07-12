import Foundation

/// Pure, presentation-layer helpers for the import review screen. Kept free of SwiftUI and IO so the
/// grouping, bulk-selection, and confidence-phrasing rules can be exercised directly in tests.
nonisolated enum ImportReviewLogic {
    // MARK: - Grouping

    /// Dispositions listed in the order they demand a person's attention, most urgent first.
    static let sectionOrder: [ImportDisposition] = [.needsReview, .manualEntry, .ready, .skipped]

    /// A single disposition's worth of staged rows, ready to render as one list section.
    struct Group: Identifiable, Equatable {
        var disposition: ImportDisposition
        var rowIDs: [UUID]

        var id: ImportDisposition { disposition }
    }

    /// Groups rows by disposition in ``sectionOrder``, preserving each row's original order and
    /// dropping any disposition that has no rows.
    static func groups(for rows: [StagedImportRow]) -> [Group] {
        sectionOrder.compactMap { disposition in
            let ids = rows.filter { $0.disposition == disposition }.map(\.id)
            guard !ids.isEmpty else { return nil }
            return Group(disposition: disposition, rowIDs: ids)
        }
    }

    // MARK: - Selection

    /// Row IDs within `rows` that can actually be imported. Unresolved rows can never be selected
    /// because there is nothing concrete to apply.
    static func selectableRowIDs(in rows: [StagedImportRow]) -> Set<UUID> {
        Set(rows.filter { $0.isImportable }.map(\.id))
    }

    /// Whether every importable row in `rows` is already present in `selection`. Returns `false`
    /// when there is nothing importable, so a "Select all" affordance never claims to be complete.
    static func allImportableSelected(in rows: [StagedImportRow], selection: Set<UUID>) -> Bool {
        let selectable = selectableRowIDs(in: rows)
        guard !selectable.isEmpty else { return false }
        return selectable.isSubset(of: selection)
    }

    /// Adds every importable row in `rows` to `selection`, leaving unrelated selections untouched.
    static func selectingAll(in rows: [StagedImportRow], from selection: Set<UUID>) -> Set<UUID> {
        selection.union(selectableRowIDs(in: rows))
    }

    /// Removes every row in `rows` from `selection`, leaving unrelated selections untouched.
    static func deselectingAll(in rows: [StagedImportRow], from selection: Set<UUID>) -> Set<UUID> {
        selection.subtracting(rows.map(\.id))
    }

    // MARK: - Confidence phrasing

    /// Coarse confidence bands. Boundaries mirror the thresholds already baked into staging and the
    /// candidate matcher so the copy never contradicts how a row was actually classified.
    enum ConfidenceBand: Equatable {
        case likely
        case possible
        case unclear
    }

    /// Band for a row's own parse confidence. 0.85 is the staging cut-off for an auto-selected
    /// "ready" row; 0.6 is where the review UI already switches its progress tint to amber.
    static func readBand(for confidence: Double) -> ConfidenceBand {
        if confidence >= 0.85 { return .likely }
        if confidence >= 0.6 { return .possible }
        return .unclear
    }

    /// Band for a candidate library match. 0.8 is `ImportCandidateMatcher`'s "close match" line and
    /// 0.55 is its floor for surfacing a candidate at all.
    static func matchBand(for confidence: Double) -> ConfidenceBand {
        if confidence >= 0.8 { return .likely }
        if confidence >= 0.55 { return .possible }
        return .unclear
    }

    /// A short, human-actionable phrase describing how sure WhatFun is about a row. When the row
    /// points at an existing library item the phrase names that item; otherwise it describes how
    /// confidently the row itself was interpreted.
    static func confidencePhrase(for row: StagedImportRow) -> String {
        if let best = row.matchCandidates.first {
            switch matchBand(for: best.confidence) {
            case .likely: return "Likely match: \(best.title)"
            case .possible: return "Possible match: \(best.title) — check the details"
            case .unclear: return "Weak match: \(best.title) — check the details"
            }
        }
        switch readBand(for: row.confidence) {
        case .likely: return "Ready to import"
        case .possible: return "Possible match — check the details"
        case .unclear: return "Needs a closer look"
        }
    }
}

nonisolated extension ImportDisposition {
    /// User-facing section title. British spelling; sentence case to match the list's other headers.
    var reviewSectionTitle: String {
        switch self {
        case .needsReview: "Needs review"
        case .manualEntry: "Manual entry"
        case .ready: "Ready"
        case .skipped: "Skipped"
        }
    }

    /// Whether a section of this disposition can offer bulk "Select all"/"Deselect all". Only
    /// dispositions whose rows can be imported qualify; manual-entry and skipped rows never can.
    var allowsBulkSelection: Bool {
        switch self {
        case .ready, .needsReview: true
        case .manualEntry, .skipped: false
        }
    }
}

nonisolated extension StagedImportRow {
    /// Whether this row has something concrete to apply. Unresolved proposals are review-only.
    var isImportable: Bool {
        if case .unresolved = proposal { return false }
        return true
    }
}
