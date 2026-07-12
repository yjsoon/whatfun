import Foundation
import Testing
@testable import WhatFun

@Suite("Import review grouping, bulk selection, and confidence phrasing")
struct ImportReviewLogicTests {
    // MARK: - Fixtures

    private func mediaRow(
        title: String = "Untitled",
        confidence: Double,
        candidates: [ImportMatchCandidate] = []
    ) -> StagedImportRow {
        StagedImportRow(
            sourceRowNumber: 2,
            rawFields: [:],
            proposal: .mediaItem(MediaItemImportProposal(title: title, mediaKind: .book)),
            confidence: confidence,
            matchCandidates: candidates
        )
    }

    private func unresolvedRow(title: String = "Mystery") -> StagedImportRow {
        StagedImportRow(
            sourceRowNumber: 2,
            rawFields: [:],
            proposal: .unresolved(UnresolvedImportProposal(bestTitle: title, reason: "No usable columns")),
            confidence: 0.1
        )
    }

    private func candidate(title: String, confidence: Double) -> ImportMatchCandidate {
        ImportMatchCandidate(
            id: UUID(),
            title: title,
            mediaKind: .book,
            confidence: confidence,
            explanation: "Title words match."
        )
    }

    // MARK: - Grouping

    @Test("Groups follow the needs-review, manual, ready order and drop empty dispositions")
    func groupOrdering() {
        let ready = mediaRow(confidence: 0.95) // -> ready
        let needsReview = mediaRow(confidence: 0.7) // -> needsReview
        let manual = unresolvedRow() // -> manualEntry

        let groups = ImportReviewLogic.groups(for: [ready, manual, needsReview])

        #expect(groups.map(\.disposition) == [.needsReview, .manualEntry, .ready])
        #expect(groups.map { $0.rowIDs.count } == [1, 1, 1])
        #expect(groups[0].rowIDs == [needsReview.id])
        #expect(groups[2].rowIDs == [ready.id])
    }

    @Test("Grouping preserves the incoming row order within a disposition")
    func groupPreservesOrder() {
        let first = mediaRow(title: "Alpha", confidence: 0.95)
        let second = mediaRow(title: "Bravo", confidence: 0.95)

        let groups = ImportReviewLogic.groups(for: [first, second])

        #expect(groups.count == 1)
        #expect(groups[0].rowIDs == [first.id, second.id])
    }

    // MARK: - Selection

    @Test("Only importable rows are selectable; unresolved rows never are")
    func selectableExcludesUnresolved() {
        let ready = mediaRow(confidence: 0.95)
        let manual = unresolvedRow()

        let selectable = ImportReviewLogic.selectableRowIDs(in: [ready, manual])

        #expect(selectable == [ready.id])
    }

    @Test("Select all adds importable rows and leaves unrelated selections and unresolved rows alone")
    func selectingAllSemantics() {
        let ready = mediaRow(confidence: 0.95)
        let review = mediaRow(confidence: 0.7)
        let manual = unresolvedRow()
        let unrelated = UUID()

        let result = ImportReviewLogic.selectingAll(in: [ready, review, manual], from: [unrelated])

        #expect(result == [ready.id, review.id, unrelated])
    }

    @Test("Deselect all removes every row in the group, importable or not")
    func deselectingAllSemantics() {
        let ready = mediaRow(confidence: 0.95)
        let review = mediaRow(confidence: 0.7)
        let unrelated = UUID()

        let result = ImportReviewLogic.deselectingAll(
            in: [ready, review],
            from: [ready.id, review.id, unrelated]
        )

        #expect(result == [unrelated])
    }

    @Test("allImportableSelected is true only when every importable row is chosen")
    func allImportableSelectedSemantics() {
        let ready = mediaRow(confidence: 0.95)
        let review = mediaRow(confidence: 0.7)
        let rows = [ready, review]

        #expect(!ImportReviewLogic.allImportableSelected(in: rows, selection: [ready.id]))
        #expect(ImportReviewLogic.allImportableSelected(in: rows, selection: [ready.id, review.id]))
    }

    @Test("allImportableSelected is false when a group has nothing importable")
    func allImportableSelectedWithNoImportables() {
        let manual = unresolvedRow()

        #expect(!ImportReviewLogic.allImportableSelected(in: [manual], selection: []))
    }

    // MARK: - Confidence bands

    @Test("Read bands mirror the 0.85 / 0.6 staging thresholds")
    func readBands() {
        #expect(ImportReviewLogic.readBand(for: 0.85) == .likely)
        #expect(ImportReviewLogic.readBand(for: 0.84) == .possible)
        #expect(ImportReviewLogic.readBand(for: 0.6) == .possible)
        #expect(ImportReviewLogic.readBand(for: 0.59) == .unclear)
    }

    @Test("Match bands mirror the matcher's 0.8 / 0.55 thresholds")
    func matchBands() {
        #expect(ImportReviewLogic.matchBand(for: 0.8) == .likely)
        #expect(ImportReviewLogic.matchBand(for: 0.79) == .possible)
        #expect(ImportReviewLogic.matchBand(for: 0.55) == .possible)
        #expect(ImportReviewLogic.matchBand(for: 0.54) == .unclear)
    }

    // MARK: - Confidence phrasing

    @Test("A strong candidate names the matched library item")
    func phraseNamesStrongCandidate() {
        let row = mediaRow(confidence: 0.7, candidates: [candidate(title: "Dune", confidence: 0.9)])

        #expect(ImportReviewLogic.confidencePhrase(for: row) == "Likely match: Dune")
    }

    @Test("A weaker candidate asks the reader to check the details")
    func phraseFlagsWeakCandidate() {
        let row = mediaRow(confidence: 0.9, candidates: [candidate(title: "Dune", confidence: 0.6)])

        #expect(ImportReviewLogic.confidencePhrase(for: row) == "Possible match: Dune — check the details")
    }

    @Test("With no candidate the phrase describes how confidently the row was read")
    func phraseWithoutCandidate() {
        #expect(ImportReviewLogic.confidencePhrase(for: mediaRow(confidence: 0.95)) == "Ready to import")
        #expect(ImportReviewLogic.confidencePhrase(for: mediaRow(confidence: 0.7)) == "Possible match — check the details")
        #expect(ImportReviewLogic.confidencePhrase(for: mediaRow(confidence: 0.3)) == "Needs a closer look")
    }

    // MARK: - Disposition presentation

    @Test("Section titles and bulk affordances match each disposition")
    func dispositionPresentation() {
        #expect(ImportDisposition.needsReview.reviewSectionTitle == "Needs review")
        #expect(ImportDisposition.manualEntry.reviewSectionTitle == "Manual entry")
        #expect(ImportDisposition.ready.reviewSectionTitle == "Ready")

        #expect(ImportDisposition.ready.allowsBulkSelection)
        #expect(ImportDisposition.needsReview.allowsBulkSelection)
        #expect(!ImportDisposition.manualEntry.allowsBulkSelection)
        #expect(!ImportDisposition.skipped.allowsBulkSelection)
    }
}
