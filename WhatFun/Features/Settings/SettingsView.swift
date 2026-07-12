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

            Section("Metadata") {
                CredentialStatusRow(
                    title: "TMDB",
                    isConfigured: Config.hasTMDBCredentials,
                    setupURL: URL(string: "https://www.themoviedb.org/settings/api")!
                )
                CredentialStatusRow(
                    title: "RAWG",
                    isConfigured: Config.hasRAWGCredentials,
                    setupURL: URL(string: "https://rawg.io/apidocs")!
                )
                LabeledContent("Open Library", value: "No key required")
                LabeledContent("Apple Podcasts", value: "No key required")
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

private struct CredentialStatusRow: View {
    let title: String
    let isConfigured: Bool
    let setupURL: URL

    var body: some View {
        LabeledContent {
            Link(destination: setupURL) {
                Label(
                    isConfigured ? "Configured" : "Add Key in Config.swift",
                    systemImage: isConfigured ? "checkmark.circle.fill" : "key"
                )
                .foregroundStyle(isConfigured ? WhatFunTheme.sage : WhatFunTheme.coral)
            }
        } label: {
            Text(title)
        }
    }
}

