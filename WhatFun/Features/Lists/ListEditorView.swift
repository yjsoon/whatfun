import SwiftData
import SwiftUI

struct ListEditorView: View {
    let existingList: UserList?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var notes: String
    @State private var kindRaw: String
    @State private var matchModeRaw: String
    @State private var ruleDrafts: [SmartRuleDraft]
    @State private var errorMessage: String?
    @State private var confirmsDeletion = false

    init(list: UserList? = nil) {
        existingList = list
        _name = State(initialValue: list?.name ?? "")
        _notes = State(initialValue: list?.notes ?? "")
        _kindRaw = State(initialValue: list?.kindRaw ?? ListKind.manual.rawValue)
        _matchModeRaw = State(
            initialValue: list?.matchModeRaw ?? SmartListMatchMode.all.rawValue
        )
        _ruleDrafts = State(
            initialValue: (list?.smartRules ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(SmartRuleDraft.init)
        )
    }

    private var listKind: ListKind {
        ListKind.value(for: kindRaw)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 5)
                }

                Section("List Type") {
                    Picker("Type", selection: $kindRaw) {
                        Text("Manual").tag(ListKind.manual.rawValue)
                        Text("Smart").tag(ListKind.smart.rawValue)
                    }
                    .pickerStyle(.segmented)

                    Text(listKind == .smart
                         ? "Smart lists update automatically as your archive changes."
                         : "Manual lists keep exactly the items and order you choose.")
                        .font(.footnote)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }

                if listKind == .smart {
                    smartRulesSection
                }

                if let existingList {
                    Section("List Actions") {
                        Button {
                            existingList.archivedAt = existingList.archivedAt == nil ? .now : nil
                            existingList.updatedAt = .now
                            saveAndDismiss()
                        } label: {
                            Label(
                                existingList.archivedAt == nil ? "Archive List" : "Restore List",
                                systemImage: existingList.archivedAt == nil
                                    ? "archivebox"
                                    : "arrow.uturn.backward"
                            )
                        }

                        Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) {
                            confirmsDeletion = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .archiveBackground()
            .navigationTitle(existingList == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Move this list to Recently Deleted?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("Move to Recently Deleted", role: .destructive, action: moveToTrash)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The list can be restored for 30 days. Items and their history are not deleted.")
            }
            .alert("Couldn’t Save List", isPresented: errorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var smartRulesSection: some View {
        Section {
            Picker("Match", selection: $matchModeRaw) {
                Text("All Rules").tag(SmartListMatchMode.all.rawValue)
                Text("Any Rule").tag(SmartListMatchMode.any.rawValue)
            }

            ForEach($ruleDrafts) { $draft in
                NavigationLink {
                    SmartRuleEditor(
                        draft: $draft,
                        editingListID: existingList?.id
                    )
                } label: {
                    RuleDraftSummary(draft: draft)
                }
            }
            .onDelete { offsets in
                ruleDrafts.remove(atOffsets: offsets)
            }

            Button("Add Rule", systemImage: "plus") {
                ruleDrafts.append(SmartRuleDraft())
            }
        } header: {
            Text("Rules")
        } footer: {
            if ruleDrafts.isEmpty {
                Text("A smart list with no supported rules stays empty.")
            } else {
                Text("Multiple selected values inside one rule match any of those values.")
            }
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let list: UserList
        if let existingList {
            list = existingList
        } else {
            let existing = (try? modelContext.fetch(FetchDescriptor<UserList>())) ?? []
            let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
            list = UserList(
                name: cleanName,
                kind: listKind,
                matchMode: SmartListMatchMode.value(for: matchModeRaw),
                sortOrder: nextOrder
            )
            modelContext.insert(list)
        }

        list.name = cleanName
        list.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        list.kindRaw = kindRaw
        list.matchModeRaw = matchModeRaw
        list.updatedAt = .now

        for rule in list.smartRules ?? [] {
            modelContext.delete(rule)
        }
        list.smartRules = []

        if listKind == .smart {
            var rules: [SmartRule] = []
            for (ruleIndex, draft) in ruleDrafts.enumerated() {
                let rule = SmartRule(
                    id: draft.id,
                    list: list,
                    fieldRaw: draft.fieldRaw,
                    operatorRaw: draft.operatorRaw,
                    isNegated: draft.isNegated,
                    sortOrder: ruleIndex
                )
                modelContext.insert(rule)

                var values: [SmartRuleValue] = []
                for (valueIndex, draftValue) in draft.values.enumerated() {
                    let value = SmartRuleValue(
                        id: draftValue.id,
                        rule: rule,
                        valueTypeRaw: draftValue.valueTypeRaw,
                        stringValue: draftValue.stringValue,
                        numberValue: draftValue.numberValue,
                        dateValue: draftValue.dateValue,
                        boolValue: draftValue.boolValue,
                        referenceID: draftValue.referenceID,
                        sortOrder: valueIndex
                    )
                    modelContext.insert(value)
                    values.append(value)
                }
                rule.values = values
                rules.append(rule)
            }
            list.smartRules = rules
        }

        saveAndDismiss()
    }

    private func moveToTrash() {
        guard let existingList else { return }
        existingList.trashedAt = .now
        existingList.purgeAfter = Calendar.current.date(byAdding: .day, value: 30, to: .now)
        existingList.updatedAt = .now
        saveAndDismiss()
    }

    private func saveAndDismiss() {
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RuleDraftSummary: View {
    let draft: SmartRuleDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let field = draft.field {
                Text(field.displayName)
                    .font(.headline)
                Text(summary(field: field))
                    .font(.caption)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
                    .lineLimit(2)
            } else {
                Label("Unsupported Rule", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(draft.fieldRaw)
                    .font(.caption.monospaced())
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func summary(field: SmartListField) -> String {
        let condition = draft.operation.map { String(localized: $0.displayName) }
            ?? draft.operatorRaw
        if draft.operation == .isSet || draft.operation == .isNotSet {
            return condition
        }

        let value: String = switch field.valueKind {
        case .selection:
            draft.values.compactMap(\.stringValue).joined(separator: ", ")
        case .referenceSelection:
            "\(draft.values.compactMap(\.referenceID).count) selected"
        case .number:
            draft.values.first?.numberValue.map { $0.formatted() } ?? "No value"
        case .date:
            draft.values.first?.dateValue?.formatted(date: .abbreviated, time: .omitted)
                ?? "No date"
        case .boolean:
            (draft.values.first?.boolValue ?? false) ? "Yes" : "No"
        }
        return "\(condition) · \(value)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
