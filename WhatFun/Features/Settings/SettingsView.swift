import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query private var items: [LibraryItem]
    @Query private var lists: [UserList]

    @AppStorage("library.grid-style") private var gridStyleRaw = LibraryGridStyle.flow.rawValue
    @AppStorage("reminders.default-hour") private var defaultReminderHour = 9

    private var recentlyDeletedCount: Int {
        items.lazy.filter { $0.trashedAt != nil }.count +
            lists.lazy.filter { $0.trashedAt != nil }.count
    }

    private var archivedCount: Int {
        items.lazy.filter { $0.archivedAt != nil && $0.trashedAt == nil }.count
    }

    var body: some View {
        Form {
            Section("Your Data") {
                NavigationLink(value: AppRoute.importExport) {
                    SettingsRow(
                        title: "Import & Export",
                        subtitle: "Sofa and Overcast imports, CSV and JSON backups",
                        symbol: "arrow.up.arrow.down"
                    )
                }

                NavigationLink(value: AppRoute.archived) {
                    SettingsRow(
                        title: "Archived Items",
                        subtitle: "\(archivedCount) hidden from the library",
                        symbol: "archivebox"
                    )
                }

                NavigationLink(value: AppRoute.recentlyDeleted) {
                    SettingsRow(
                        title: "Recently Deleted",
                        subtitle: "\(recentlyDeletedCount) recoverable for 30 days",
                        symbol: "trash"
                    )
                }
            }

            Section("Defaults") {
                Picker("Library Grid", selection: $gridStyleRaw) {
                    ForEach(LibraryGridStyle.allCases) { style in
                        Label(style.displayName, systemImage: style.symbolName)
                            .tag(style.rawValue)
                    }
                }

                Stepper(value: $defaultReminderHour, in: 0 ... 23) {
                    LabeledContent("Start Reminder") {
                        Text(defaultReminderDate, format: .dateTime.hour().minute())
                    }
                }

                LabeledContent("Appearance", value: "Follow System")
            }

            Section {
                MetadataKeyRow(
                    credentialKey: .tmdbReadAccessToken,
                    hasConfigFallback: Config.hasTMDBCredentials,
                    guidance: "Film and TV search needs a free TMDB read-access token."
                )
                MetadataKeyRow(
                    credentialKey: .rawgAPIKey,
                    hasConfigFallback: Config.hasRAWGCredentials,
                    guidance: "Game search needs a free RAWG API key."
                )
                LabeledContent("Open Library", value: "No key required")
                LabeledContent("Apple Podcasts", value: "No key required")
            } header: {
                Text("Metadata")
            } footer: {
                Text("Keys are stored in your device's Keychain, take effect immediately, and are never included in exports or backups.")
            }

            Section("About") {
                Link("WhatFun on GitHub", destination: URL(string: "https://github.com/yjsoon/whatfun")!)
                Link("Metadata by TMDB", destination: URL(string: "https://www.themoviedb.org")!)
                Link("Data by RAWG", destination: URL(string: "https://rawg.io")!)
                Text("Local-first · no account · no backend")
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .archiveBackground()
    }

    private var defaultReminderDate: Date {
        Calendar.autoupdatingCurrent.date(
            bySettingHour: defaultReminderHour,
            minute: 0,
            second: 0,
            of: .now
        ) ?? .now
    }
}

private struct SettingsRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(WhatFunTheme.coral)
        }
    }
}

private struct MetadataKeyRow: View {
    let credentialKey: MetadataCredentialKey
    let hasConfigFallback: Bool
    let guidance: LocalizedStringKey

    @Environment(AppServices.self) private var services
    /// Never holds the plaintext key: the value is read, masked, and dropped. A
    /// failed Keychain read is its own state, not "no key saved".
    @State private var status = MetadataKeyStatus.missing
    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            LabeledContent {
                Label(statusText, systemImage: statusSymbol)
                    .foregroundStyle(status.isUsable ? WhatFunTheme.sage : WhatFunTheme.coral)
            } label: {
                Text(credentialKey.displayName)
                    .foregroundStyle(.primary)
            }
        }
        .task(id: isEditing) {
            status = await loadStatus()
        }
        .sheet(isPresented: $isEditing) {
            MetadataKeyEditorView(
                credentialKey: credentialKey,
                hasConfigFallback: hasConfigFallback,
                guidance: guidance,
                status: status
            )
        }
    }

    private func loadStatus() async -> MetadataKeyStatus {
        do {
            let stored = try await services.credentials.value(for: credentialKey.account)
            return metadataKeyStatus(stored: .success(stored), hasConfigFallback: hasConfigFallback)
        } catch {
            return metadataKeyStatus(stored: .failure(error), hasConfigFallback: hasConfigFallback)
        }
    }

    private var statusText: String {
        switch status {
        case let .saved(masked): masked
        case .developerFallback: String(localized: "Developer key")
        case .missing: String(localized: "Add Key")
        case .unreadable: String(localized: "Keychain unavailable")
        }
    }

    private var statusSymbol: String {
        switch status {
        case .saved, .developerFallback: "checkmark.circle.fill"
        case .missing: "key"
        case .unreadable: "exclamationmark.triangle.fill"
        }
    }
}

private struct MetadataKeyEditorView: View {
    let credentialKey: MetadataCredentialKey
    let hasConfigFallback: Bool
    let guidance: LocalizedStringKey
    /// Carries at most the masked key. The editor never needs the plaintext: it
    /// only writes a new key or removes the existing one.
    let status: MetadataKeyStatus

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                if status == .unreadable {
                    Section {
                        Label(
                            "WhatFun couldn’t read your saved key from the Keychain, so it can’t tell whether one is stored. Unlock your device and reopen Settings. Saving a key below will overwrite whatever is there.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(WhatFunTheme.coral)
                    }
                }

                Section {
                    SecureField(status.maskedKey == nil ? "Paste key" : "Paste replacement key", text: $draftKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isWorking)
                } header: {
                    Text("\(credentialKey.displayName) Key")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(guidance)
                        Link("Get a key from \(credentialKey.displayName)", destination: credentialKey.setupURL)
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(WhatFunTheme.coral)
                        }
                    }
                }

                if let maskedKey = status.maskedKey {
                    Section {
                        LabeledContent("Saved key", value: maskedKey)
                        Button("Remove Key", role: .destructive) {
                            Task { await removeKey() }
                        }
                        .disabled(isWorking)
                    } footer: {
                        if hasConfigFallback {
                            Text("Removing the saved key falls back to the key built into this copy of the app.")
                        } else {
                            Text("Removing the saved key disables \(credentialKey.displayName) search until you add another.")
                        }
                    }
                }
            }
            .navigationTitle(credentialKey.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveKey() }
                    }
                    .disabled(isWorking || draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveKey() async {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.credentials.set(trimmed, for: credentialKey.account)
            draftKey = ""
            purgeCredentialBearingResponseCache()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeKey() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.credentials.removeValue(for: credentialKey.account)
            purgeCredentialBearingResponseCache()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

