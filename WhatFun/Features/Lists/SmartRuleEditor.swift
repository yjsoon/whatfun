import SwiftData
import SwiftUI

struct SmartRuleValueDraft: Identifiable, Hashable {
    var id = UUID()
    var valueTypeRaw: String
    var stringValue: String?
    var numberValue: Double?
    var dateValue: Date?
    var boolValue: Bool?
    var referenceID: UUID?

    init(
        id: UUID = UUID(),
        valueTypeRaw: String,
        stringValue: String? = nil,
        numberValue: Double? = nil,
        dateValue: Date? = nil,
        boolValue: Bool? = nil,
        referenceID: UUID? = nil
    ) {
        self.id = id
        self.valueTypeRaw = valueTypeRaw
        self.stringValue = stringValue
        self.numberValue = numberValue
        self.dateValue = dateValue
        self.boolValue = boolValue
        self.referenceID = referenceID
    }

    init(_ value: SmartRuleValue) {
        id = value.id
        valueTypeRaw = value.valueTypeRaw
        stringValue = value.stringValue
        numberValue = value.numberValue
        dateValue = value.dateValue
        boolValue = value.boolValue
        referenceID = value.referenceID
    }
}

struct SmartRuleDraft: Identifiable, Hashable {
    var id = UUID()
    var fieldRaw = SmartListField.mediaKind.rawValue
    var operatorRaw = SmartRuleOperator.equals.rawValue
    var isNegated = false
    var values: [SmartRuleValueDraft] = [
        SmartRuleValueDraft(valueTypeRaw: "string", stringValue: MediaKind.book.rawValue),
    ]

    init() {}

    init(_ rule: SmartRule) {
        id = rule.id
        fieldRaw = rule.fieldRaw
        operatorRaw = rule.operatorRaw
        isNegated = rule.isNegated
        values = (rule.values ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(SmartRuleValueDraft.init)
    }

    var field: SmartListField? { SmartListField(rawValue: fieldRaw) }
    var operation: SmartRuleOperator? { SmartRuleOperator(rawValue: operatorRaw) }

    mutating func chooseField(_ field: SmartListField) {
        fieldRaw = field.rawValue
        operatorRaw = field.allowedOperators.first?.rawValue ?? SmartRuleOperator.equals.rawValue
        switch field.valueKind {
        case .selection:
            let value = field == .status
                ? ConsumptionStatus.planned.rawValue
                : MediaKind.book.rawValue
            values = [SmartRuleValueDraft(valueTypeRaw: "string", stringValue: value)]
        case .referenceSelection:
            values = []
        case .number:
            let value = switch field {
            case .effectiveRating: 4.0
            case .progress: 50.0
            case .repeatCount: 1.0
            default: 0.0
            }
            values = [SmartRuleValueDraft(valueTypeRaw: "number", numberValue: value)]
        case .date:
            values = [SmartRuleValueDraft(valueTypeRaw: "date", dateValue: .now)]
        case .boolean:
            values = [SmartRuleValueDraft(valueTypeRaw: "bool", boolValue: true)]
        }
    }
}

struct SmartRuleEditor: View {
    @Binding var draft: SmartRuleDraft
    let editingListID: UUID?

    @Query(sort: [SortDescriptor(\Facet.name)]) private var facets: [Facet]
    @Query(sort: \UserList.sortOrder) private var allLists: [UserList]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Rule") {
                Picker("Field", selection: fieldBinding) {
                    if draft.field == nil {
                        Text("Unsupported: \(draft.fieldRaw)")
                            .tag(draft.fieldRaw)
                    }
                    ForEach(SmartListField.allCases) { field in
                        Text(field.displayName).tag(field.rawValue)
                    }
                }

                if let field = draft.field {
                    Picker("Condition", selection: operatorBinding) {
                        if !field.allowedOperators.contains(where: { $0.rawValue == draft.operatorRaw }) {
                            Text("Unsupported: \(draft.operatorRaw)")
                                .tag(draft.operatorRaw)
                        }
                        ForEach(field.allowedOperators) { operation in
                            Text(operation.displayName).tag(operation.rawValue)
                        }
                    }
                    if !field.allowedOperators.contains(where: { $0.rawValue == draft.operatorRaw }) {
                        Text("Choose a supported condition to reactivate this rule.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Label(
                        "This rule came from a newer or different WhatFun version. It will be ignored until you choose a supported field.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }

                Toggle("Invert Result", isOn: $draft.isNegated)
            }

            if let field = draft.field,
               draft.operation != .isSet,
               draft.operation != .isNotSet {
                valueSection(for: field)
            }
        }
        .scrollContentBackground(.hidden)
        .archiveBackground()
        .navigationTitle("Smart Rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: dismiss.callAsFunction)
            }
        }
    }

    @ViewBuilder
    private func valueSection(for field: SmartListField) -> some View {
        switch field {
        case .mediaKind:
            Section("Media Types") {
                ForEach(MediaKind.filterCases, id: \.rawValue) { kind in
                    Toggle(isOn: stringSelection(kind.rawValue)) {
                        Label(kind.displayName, systemImage: kind.symbolName)
                    }
                }
            }
        case .status:
            Section("Statuses") {
                ForEach([
                    ConsumptionStatus.planned,
                    .inProgress,
                    .paused,
                    .completed,
                    .dropped,
                ], id: \.rawValue) { status in
                    Toggle(isOn: stringSelection(status.rawValue)) {
                        Label(status.displayName, systemImage: status.symbolName)
                    }
                }
            }
        case .genre, .platform, .tag:
            facetSection(for: field)
        case .listMembership:
            Section("Lists") {
                if selectableLists.isEmpty {
                    Text("Create another list first.")
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                } else {
                    ForEach(selectableLists) { list in
                        Toggle(list.name, isOn: referenceSelection(list.id))
                    }
                }
            }
        case .effectiveRating, .progress, .repeatCount:
            Section("Value") {
                TextField(numberPrompt(for: field), value: numberBinding, format: .number)
                    .keyboardType(.decimalPad)
                Text(numberHelp(for: field))
                    .font(.footnote)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        case .startDate, .completionDate, .lastSessionDate:
            Section("Date") {
                DatePicker(
                    "Date",
                    selection: dateBinding,
                    displayedComponents: [.date]
                )
            }
        case .favorite:
            Section("Value") {
                Toggle("Favorite", isOn: boolBinding)
            }
        }
    }

    @ViewBuilder
    private func facetSection(for field: SmartListField) -> some View {
        let kind: FacetKind = switch field {
        case .genre: .genre
        case .platform: .platform
        default: .tag
        }
        let choices = facets.filter { $0.kind == kind }
        Section(field.displayName) {
            if choices.isEmpty {
                Text("No \(String(localized: field.displayName).lowercased()) values exist in your library yet.")
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            } else {
                ForEach(choices) { facet in
                    Toggle(facet.name, isOn: referenceSelection(facet.id))
                }
            }
        }
    }

    private var selectableLists: [UserList] {
        allLists.filter {
            $0.trashedAt == nil && $0.id != editingListID &&
                $0.archivedAt == nil && $0.kind == .manual
        }
    }

    private var fieldBinding: Binding<String> {
        Binding(
            get: { draft.fieldRaw },
            set: { rawValue in
                guard let field = SmartListField(rawValue: rawValue) else {
                    draft.fieldRaw = rawValue
                    return
                }
                draft.chooseField(field)
            }
        )
    }

    private var operatorBinding: Binding<String> {
        Binding(
            get: { draft.operatorRaw },
            set: { draft.operatorRaw = $0 }
        )
    }

    private func stringSelection(_ value: String) -> Binding<Bool> {
        Binding(
            get: { draft.values.contains { $0.stringValue == value } },
            set: { isSelected in
                draft.values.removeAll { $0.stringValue == value }
                if isSelected {
                    draft.values.append(
                        SmartRuleValueDraft(valueTypeRaw: "string", stringValue: value)
                    )
                }
            }
        )
    }

    private func referenceSelection(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { draft.values.contains { $0.referenceID == id } },
            set: { isSelected in
                draft.values.removeAll { $0.referenceID == id }
                if isSelected {
                    draft.values.append(
                        SmartRuleValueDraft(valueTypeRaw: "reference", referenceID: id)
                    )
                }
            }
        )
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { draft.values.first?.numberValue ?? 0 },
            set: { value in
                let adjusted = switch draft.field {
                case .effectiveRating: min(max(value, 0.5), 5)
                case .progress: min(max(value, 0), 100)
                case .repeatCount: max(value.rounded(), 0)
                default: value
                }
                draft.values = [
                    SmartRuleValueDraft(valueTypeRaw: "number", numberValue: adjusted),
                ]
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { draft.values.first?.dateValue ?? .now },
            set: { value in
                draft.values = [SmartRuleValueDraft(valueTypeRaw: "date", dateValue: value)]
            }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { draft.values.first?.boolValue ?? true },
            set: { value in
                draft.values = [SmartRuleValueDraft(valueTypeRaw: "bool", boolValue: value)]
            }
        )
    }

    private func numberPrompt(for field: SmartListField) -> String {
        switch field {
        case .effectiveRating: "Stars"
        case .progress: "Percent"
        case .repeatCount: "Count"
        default: "Value"
        }
    }

    private func numberHelp(for field: SmartListField) -> String {
        switch field {
        case .effectiveRating: "Use a value from 0.5 to 5."
        case .progress: "Use a percentage from 0 to 100."
        case .repeatCount: "The number of rereads, rewatches, or replays."
        default: ""
        }
    }
}
