import SwiftData
import SwiftUI

struct MarkDoneView: View {
    private let itemID: UUID

    @Query private var matchingItems: [LibraryItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedUnitID: UUID?
    @State private var completionDate = Date.now
    @State private var ratingHalfSteps: Int?
    @State private var note = ""
    @State private var didChooseDefault = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(itemID: UUID) {
        self.itemID = itemID
        _matchingItems = Query(
            filter: #Predicate<LibraryItem> { $0.id == itemID }
        )
    }

    private var item: LibraryItem? { matchingItems.first }

    private var units: [ContentUnit] {
        guard let item else { return [] }
        return (item.units ?? [])
            .filter { unit in
                guard unit.deletedAt == nil else { return false }
                return switch item.mediaKind {
                case .tvShow:
                    unit.unitKind == .tvSeason || unit.unitKind == .tvEpisode
                case .comic:
                    unit.unitKind == .comicVolume || unit.unitKind == .comicIssue
                case .podcast:
                    unit.unitKind == .podcastEpisode
                default:
                    false
                }
            }
            .sorted { lhs, rhs in
                let lhsParent = lhs.parent?.sortOrder ?? lhs.sortOrder
                let rhsParent = rhs.parent?.sortOrder ?? rhs.sortOrder
                if lhsParent != rhsParent { return lhsParent < rhsParent }
                if lhs.parent == nil, rhs.parent != nil { return true }
                if lhs.parent != nil, rhs.parent == nil { return false }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var selectedUnit: ContentUnit? {
        guard let selectedUnitID else { return nil }
        return units.first { $0.id == selectedUnitID }
    }

    private var selectedIsAlreadyComplete: Bool {
        if let selectedUnit { return selectedUnit.status == .completed }
        return item?.status == .completed
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        Label("Completion is separate from sessions", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("This records when you finished without inventing another watch, read, play, or listen session.")
                            .font(.footnote)
                            .foregroundStyle(WhatFunTheme.secondaryInk)
                    }

                    if !units.isEmpty {
                        Section("What did you finish?") {
                            Picker("Item or installment", selection: $selectedUnitID) {
                                Text("Whole \(item.mediaKind.singularName)").tag(UUID?.none)
                                ForEach(units) { unit in
                                    Text(label(for: unit)).tag(UUID?.some(unit.id))
                                }
                            }

                            if selectedIsAlreadyComplete {
                                Label("Already completed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(WhatFunTheme.sage)
                            }
                        }
                    }

                    Section("Completion") {
                        DatePicker(
                            "Finished",
                            selection: $completionDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )

                        if selectedUnit?.unitKind != .tvEpisode {
                            Picker("Rating", selection: $ratingHalfSteps) {
                                Text("Not Rated").tag(Int?.none)
                                ForEach(1 ... 10, id: \.self) { halfSteps in
                                    Text("\(Double(halfSteps) / 2, format: .number.precision(.fractionLength(1))) stars")
                                        .tag(Int?.some(halfSteps))
                                }
                            }
                        }

                        TextField("Completion note (optional)", text: $note, axis: .vertical)
                            .lineLimit(2 ... 6)
                    }
                } else {
                    ContentUnavailableView(
                        "Item unavailable",
                        systemImage: "questionmark.folder"
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(WhatFunTheme.background)
            .navigationTitle("Mark Done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(item == nil || selectedIsAlreadyComplete || isSaving)
                }
            }
            .task { chooseDefaultIfNeeded() }
            .onChange(of: selectedUnitID) { _, _ in
                ratingHalfSteps = selectedUnit?.ratingHalfSteps
            }
            .alert("Couldn’t Mark Done", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func chooseDefaultIfNeeded() {
        guard !didChooseDefault, let item else { return }
        didChooseDefault = true
        let activeCycle = (item.cycles ?? [])
            .filter { $0.deletedAt == nil && ($0.status == .inProgress || $0.status == .paused) }
            .max { ($0.lastSessionAt ?? .distantPast) < ($1.lastSessionAt ?? .distantPast) }
        selectedUnitID = activeCycle?.targetUnitID
            ?? units.first(where: { $0.status != .completed })?.id
        ratingHalfSteps = selectedUnit?.ratingHalfSteps ?? item.ratingOverrideHalfSteps
    }

    private func save() {
        guard let item, !selectedIsAlreadyComplete else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let service = ActivityService(context: modelContext)
            let matching = (item.cycles ?? []).filter {
                $0.deletedAt == nil && $0.targetUnitID == selectedUnitID
            }
            let cycle: ConsumptionCycle
            if let active = matching.first(where: {
                $0.status == .inProgress || $0.status == .paused
            }) {
                cycle = active
            } else if selectedUnit != nil,
                      (item.mediaKind == .tvShow || item.mediaKind == .comic),
                      !(item.cycles ?? []).isEmpty {
                cycle = try service.startNextInstallment(
                    for: item,
                    targetUnit: selectedUnit!,
                    at: completionDate
                )
            } else {
                cycle = try service.startCycle(
                    for: item,
                    targetUnit: selectedUnit,
                    at: completionDate
                )
            }

            _ = try service.markDone(
                item: item,
                cycle: cycle,
                targetUnit: selectedUnit,
                at: completionDate,
                ratingHalfSteps: ratingHalfSteps,
                note: note.doneNilIfBlank
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func label(for unit: ContentUnit) -> String {
        if let parent = unit.parent {
            return "\(parent.title) · \(unit.title)"
        }
        return unit.title
    }
}

private extension String {
    var doneNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
