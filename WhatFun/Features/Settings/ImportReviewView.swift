import SwiftUI

struct ImportReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var batch: StagedImportBatch
    @State private var selectedRowIDs: Set<UUID>
    @State private var targetItemIDs: [UUID: UUID] = [:]
    @State private var isApplying = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    let apply: (StagedImportBatch, ImportApplicationSelection) async throws -> ImportApplicationReport

    init(
        batch: StagedImportBatch,
        apply: @escaping (StagedImportBatch, ImportApplicationSelection) async throws -> ImportApplicationReport
    ) {
        _batch = State(initialValue: batch)
        _selectedRowIDs = State(
            initialValue: Set(batch.rows.filter { $0.disposition == .ready }.map(\.id))
        )
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection

                ForEach($batch.rows) { $row in
                    ImportReviewRow(
                        row: $row,
                        isSelected: selectionBinding(for: row.id),
                        targetItemID: targetBinding(for: row.id),
                        isSelectable: row.proposal.isActionable
                    )
                    .listRowBackground(WhatFunTheme.raisedBackground)
                }
            }
            .listStyle(.insetGrouped)
            .disabled(isApplying)
            .scrollContentBackground(.hidden)
            .background(WhatFunTheme.background)
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isApplying)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedRowIDs.count)") {
                        Task { await applySelectedRows() }
                    }
                    .disabled(selectedRowIDs.isEmpty || isApplying)
                }
            }
            .overlay {
                if isApplying {
                    ProgressView("Preserving history…")
                        .padding()
                        .glassEffect(in: .rect(cornerRadius: 18))
                        .accessibilityAddTraits(.isModal)
                        .accessibilityHint("Import controls are unavailable until history is saved.")
                }
            }
            .alert("Import Complete", isPresented: resultBinding) {
                Button("Done") { dismiss() }
            } message: {
                Text(resultMessage ?? "Import finished.")
            }
            .alert("Couldn’t Import", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please review the file and try again.")
            }
        }
        .interactiveDismissDisabled(isApplying)
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Ready", value: batch.rows.filter { $0.disposition == .ready }.count, format: .number)
            LabeledContent("Needs Review", value: batch.rows.filter { $0.disposition == .needsReview }.count, format: .number)
            LabeledContent("Manual or Unresolved", value: batch.rows.filter { $0.disposition == .manualEntry }.count, format: .number)

            if !batch.warnings.isEmpty {
                ForEach(batch.warnings) { warning in
                    Label(warning.message, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
            }
        } header: {
            Text(batch.sourceFilename ?? sourceName)
        } footer: {
            Text("High-confidence rows are selected automatically. Ambiguous rows stay off until you choose them; nothing is silently matched.")
        }
    }

    private var sourceName: String {
        switch batch.source {
        case .opml: "OPML Podcasts"
        case .overcastAllDataCSV: "Overcast All Data"
        case .sofaCSV: "Sofa Export"
        }
    }

    private var resultBinding: Binding<Bool> {
        Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedRowIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedRowIDs.insert(id)
                } else {
                    selectedRowIDs.remove(id)
                }
            }
        )
    }

    private func targetBinding(for id: UUID) -> Binding<UUID?> {
        Binding(
            get: { targetItemIDs[id] },
            set: { targetItemIDs[id] = $0 }
        )
    }

    private func applySelectedRows() async {
        isApplying = true
        defer { isApplying = false }
        do {
            let report = try await apply(
                batch,
                ImportApplicationSelection(
                    acceptedRowIDs: selectedRowIDs,
                    targetItemIDsByRowID: targetItemIDs
                )
            )
            resultMessage = "Imported \(report.appliedRows) rows, creating \(report.createdItems) items and \(report.createdSessions) historical sessions. \(report.skippedRows) rows were skipped and \(report.warnings.count) warnings were recorded."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ImportReviewRow: View {
    @Binding var row: StagedImportRow
    @Binding var isSelected: Bool
    @Binding var targetItemID: UUID?
    let isSelectable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.proposal.reviewTitle)
                        .font(.headline)
                    Text(row.proposal.reviewKind)
                        .font(.caption)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
                Spacer()
                Toggle("Include", isOn: $isSelected)
                    .labelsHidden()
                    .accessibilityLabel("Include \(row.proposal.reviewTitle)")
                    .disabled(!isSelectable)
            }

            HStack {
                ProgressView(value: row.confidence)
                    .tint(confidenceColor)
                    .accessibilityHidden(true)
                Text(row.confidence, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WhatFunTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Match confidence")
            .accessibilityValue(Text(row.confidence, format: .percent.precision(.fractionLength(0))))

            if !isSelectable {
                Label("This unresolved row will be skipped.", systemImage: "pencil.and.list.clipboard")
                    .font(.footnote)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }

            if row.proposal.needsMediaKind {
                Picker("Media Type", selection: mediaKindBinding) {
                    Text("Choose…").tag(ArchiveMediaKind?.none)
                    ForEach(ArchiveMediaKind.allCases, id: \.self) { kind in
                        Text(kind.reviewName).tag(ArchiveMediaKind?.some(kind))
                    }
                }
            }

            if !row.matchCandidates.isEmpty {
                Picker("Match Existing Item", selection: $targetItemID) {
                    Text("Create New Item").tag(UUID?.none)
                    ForEach(row.matchCandidates) { candidate in
                        Text("\(candidate.title) · \(candidate.confidence, format: .percent.precision(.fractionLength(0)))")
                            .tag(UUID?.some(candidate.id))
                    }
                }
            }

            ForEach(row.ambiguities) { ambiguity in
                Label(ambiguity.message, systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ForEach(row.warnings) { warning in
                Label(warning.message, systemImage: warning.severity == .warning ? "exclamationmark.triangle" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(
                        warning.severity == .warning ? Color.orange : WhatFunTheme.secondaryInk
                    )
            }
        }
        .padding(.vertical, 5)
    }

    private var confidenceColor: Color {
        if row.confidence >= 0.85 { return WhatFunTheme.sage }
        if row.confidence >= 0.6 { return .orange }
        return WhatFunTheme.coral
    }

    private var mediaKindBinding: Binding<ArchiveMediaKind?> {
        Binding(
            get: {
                guard case let .mediaItem(proposal) = row.proposal else { return nil }
                return proposal.mediaKind
            },
            set: { newKind in
                guard case var .mediaItem(proposal) = row.proposal else { return }
                proposal.mediaKind = newKind
                row.proposal = .mediaItem(proposal)
                if newKind != nil {
                    row.ambiguities.removeAll { $0.field == "Media Type" }
                }
                if newKind != nil, row.ambiguities.isEmpty {
                    row.disposition = .ready
                }
            }
        )
    }
}

private extension ImportProposal {
    var reviewTitle: String {
        switch self {
        case let .mediaItem(value): value.title
        case let .podcastSubscription(value): value.title
        case let .podcastEpisode(value): value.episodeTitle
        case let .unresolved(value): value.bestTitle ?? "Unresolved Row"
        }
    }

    var reviewKind: String {
        switch self {
        case let .mediaItem(value): value.mediaKind?.reviewName ?? "Media type needed"
        case .podcastSubscription: "Podcast subscription"
        case .podcastEpisode: "Podcast episode"
        case .unresolved: "Manual entry required"
        }
    }

    var needsMediaKind: Bool {
        guard case let .mediaItem(value) = self else { return false }
        return value.mediaKind == nil
    }

    var isActionable: Bool {
        if case .unresolved = self { return false }
        return true
    }
}

private extension ArchiveMediaKind {
    var reviewName: String {
        switch self {
        case .book: "Book"
        case .comic: "Comic"
        case .movie: "Movie"
        case .television: "TV Show"
        case .game: "Game"
        case .podcast: "Podcast"
        }
    }
}
