import CryptoKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportExportView: View {
    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.sortTitle)]
    ) private var items: [LibraryItem]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @AppStorage("library.grid-style") private var gridStyleRaw = LibraryGridStyle.flow.rawValue
    @AppStorage("reminders.default-hour") private var defaultReminderHour = 9
    @AppStorage("backup.last-success") private var lastBackupTimestamp = 0.0
    @AppStorage("backup.last-error") private var lastBackupError = ""

    @State private var restorePolicy = RestorePolicy.mergeNew
    @State private var portableDocument: PortableArchiveDocument?
    @State private var fullDocument: FullBackupDocument?
    @State private var presentsPortableExporter = false
    @State private var presentsFullExporter = false
    @State private var presentsPortableImporter = false
    @State private var presentsFullImporter = false
    @State private var presentsLegacyImporter = false
    @State private var selectedLegacySource = LegacyImportSource.sofa
    @State private var stagedImport: StagedImportBatch?
    @State private var pendingRestore: PendingRestore?
    @State private var confirmsRestore = false
    @State private var encryptedBackup: EncryptedBackupRequest?
    @State private var presentsFullExportOptions = false
    @State private var queuesFullExporterAfterDismiss = false
    @State private var queuedRestoreAfterUnlock: PendingRestore.Source?
    @State private var includesPrivateFeeds = false
    @State private var exportPassphrase = ""
    @State private var exportPassphraseConfirmation = ""
    @State private var backupURLs: [URL] = []
    @State private var isWorking = false
    @State private var notice: ImportExportNotice?

    var body: some View {
        Form {
            portableArchiveSection
            fullBackupSection
            restoreSection
            legacyImportSection
            localRecoverySection
            privacySection
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Import & Export")
        .archiveBackground()
        .overlay {
            if isWorking {
                ProgressView("Preserving your archive…")
                    .padding(20)
                    .glassEffect(in: .rect(cornerRadius: 20))
            }
        }
        .disabled(isWorking)
        .fileExporter(
            isPresented: $presentsPortableExporter,
            document: portableDocument,
            contentType: .whatFunArchive,
            defaultFilename: "WhatFun-\(dateStamp)-portable.whatfunarchive"
        ) { result in
            handleExportResult(result, label: "Portable archive")
            portableDocument = nil
        }
        .fileExporter(
            isPresented: $presentsFullExporter,
            document: fullDocument,
            contentType: .whatFunBackup,
            defaultFilename: "WhatFun-\(dateStamp)-full.whatfunbackup"
        ) { result in
            handleExportResult(result, label: "Full backup")
            fullDocument = nil
        }
        .fileImporter(
            isPresented: $presentsPortableImporter,
            allowedContentTypes: [.whatFunArchive, .package, .folder],
            allowsMultipleSelection: false,
            onCompletion: receivePortableArchive
        )
        .fileImporter(
            isPresented: $presentsFullImporter,
            allowedContentTypes: [.whatFunBackup, .json],
            allowsMultipleSelection: false,
            onCompletion: receiveFullBackup
        )
        .fileImporter(
            isPresented: $presentsLegacyImporter,
            allowedContentTypes: selectedLegacySource.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: receiveLegacyImport
        )
        .sheet(isPresented: $presentsFullExportOptions, onDismiss: finishFullExportOptions) {
            fullExportOptions
        }
        .sheet(item: $encryptedBackup, onDismiss: finishEncryptedUnlock) { request in
            BackupUnlockView(request: request) { key in
                queuedRestoreAfterUnlock = .full(data: request.data, key: key)
                encryptedBackup = nil
            }
        }
        .sheet(item: $stagedImport, onDismiss: { stagedImport = nil }) { batch in
            ImportReviewView(batch: batch) { batch, selection in
                try await StagedImportApplier(
                    context: modelContext,
                    credentials: services.credentials
                ).apply(batch, selection: selection)
            }
        }
        .confirmationDialog(
            pendingRestore?.mode == .replaceAll ? "Replace your current archive?" : "Merge this archive?",
            isPresented: $confirmsRestore,
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { request in
            Button(
                request.mode == .replaceAll ? "Replace Everything" : "Merge New Records",
                role: request.mode == .replaceAll ? .destructive : nil
            ) {
                Task { await performRestore(request) }
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { request in
            if request.mode == .replaceAll {
                Text("The file is validated first. WhatFun then replaces local semantic records while retaining a rotating recovery snapshot.")
            } else {
                Text("Stable IDs already in your library are kept; new records and their history are inserted.")
            }
        }
        .onChange(of: confirmsRestore) { _, isPresented in
            if !isPresented { pendingRestore = nil }
        }
        .onChange(of: includesPrivateFeeds) { _, includesSecrets in
            if !includesSecrets { scrubExportPassphrase() }
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task { await refreshBackupList() }
    }

    private var portableArchiveSection: some View {
        Section {
            Button("Export Portable Archive", systemImage: "shippingbox") {
                Task { await makePortableArchive() }
            }
        } header: {
            Text("Archive of Record")
        } footer: {
            Text("A checksummed multi-file CSV package with stable IDs, history, progress, ratings, notes, lists, tags, quotes, and user artwork. Private feed URLs are always redacted.")
        }
    }

    private var fullBackupSection: some View {
        Section {
            Button("Export Full JSON Backup", systemImage: "doc.text") {
                presentsFullExportOptions = true
            }
        } header: {
            Text("WhatFun Backup")
        } footer: {
            Text("For restoring WhatFun’s native relationships. Replace restores supported settings; merge leaves current preferences untouched. Private podcast feeds are optional and encrypted separately.")
        }
    }

    private var restoreSection: some View {
        Section("Restore") {
            Picker("Restore Behavior", selection: $restorePolicy) {
                ForEach(RestorePolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Button("Import Portable Archive", systemImage: "shippingbox.and.arrow.backward") {
                presentsPortableImporter = true
            }

            Button("Import Full JSON Backup", systemImage: "arrow.down.doc") {
                presentsFullImporter = true
            }
        }
    }

    private var legacyImportSection: some View {
        Section {
            ForEach(LegacyImportSource.allCases) { source in
                Button(source.buttonTitle, systemImage: source.symbolName) {
                    selectedLegacySource = source
                    presentsLegacyImporter = true
                }
            }
        } header: {
            Text("Bring Data In")
        } footer: {
            Text("Sofa, Overcast, and OPML files are staged first. High-confidence rows are selected; ambiguous matches wait for your review.")
        }
    }

    private var localRecoverySection: some View {
        Section {
            Button("Create Recovery Snapshot Now", systemImage: "clock.arrow.circlepath") {
                Task { await createDailyBackup(showSuccess: true) }
            }

            Button("Restore Latest Snapshot", systemImage: "arrow.counterclockwise") {
                Task { await queueLatestBackup() }
            }
            .disabled(backupURLs.isEmpty)

            if backupURLs.isEmpty {
                LabeledContent("Snapshots", value: "None yet")
            } else {
                ForEach(backupURLs, id: \.self) { url in
                    Label(url.deletingPathExtension().deletingPathExtension().lastPathComponent, systemImage: "checkmark.shield")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
            }

            if lastBackupTimestamp > 0 {
                LabeledContent("Last Automatic Snapshot") {
                    Text(Date(timeIntervalSince1970: lastBackupTimestamp), format: .dateTime.day().month().year().hour().minute())
                }
            }

            if !lastBackupError.isEmpty {
                Label(lastBackupError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Local Recovery")
        } footer: {
            Text("WhatFun keeps one validated, private-feed-redacted JSON snapshot per day and retains the seven newest days on this device.")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("No account or backend", systemImage: "iphone")
            Label("Private feed URLs live in Keychain", systemImage: "key")
            Label("Downloaded cover caches are rebuildable", systemImage: "photo.badge.arrow.down")
        }
    }

    private var fullExportOptions: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include Private Podcast Feeds", isOn: $includesPrivateFeeds)

                    if includesPrivateFeeds {
                        SecureField("Passphrase", text: $exportPassphrase)
                            .textContentType(.newPassword)
                        SecureField("Confirm Passphrase", text: $exportPassphraseConfirmation)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    Text("The passphrase is never stored. Without it, an encrypted private-feed block cannot be restored; the rest of the backup remains readable.")
                }
            }
            .navigationTitle("Full Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentsFullExportOptions = false }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Prepare Export") {
                        Task { await makeFullBackup() }
                    }
                    .disabled(!fullExportOptionsAreValid || isWorking)
                }
            }
            .overlay { if isWorking { ProgressView("Encrypting backup…") } }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isWorking)
    }

    private var fullExportOptionsAreValid: Bool {
        !includesPrivateFeeds ||
            (!exportPassphrase.isEmpty && exportPassphrase == exportPassphraseConfirmation)
    }

    private var dateStamp: String {
        Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private var archivePreferences: [String: String] {
        DurabilityCoordinator.backupPreferences(
            gridStyle: gridStyleRaw,
            defaultReminderHour: defaultReminderHour
        )
    }

    private func makeCoordinator(
        generator: String = "WhatFun 0.1"
    ) throws -> DurabilityCoordinator {
        let store = try DailyBackupStore.applicationSupport()
        return DurabilityCoordinator(
            bridge: SwiftDataArchiveBridge(
                context: modelContext,
                credentials: services.credentials
            ),
            dailyStore: store,
            generator: generator
        )
    }

    private func makePortableArchive() async {
        await performWork {
            let package = try await makeCoordinator().makePortablePackage()
            portableDocument = PortableArchiveDocument(package: package)
            presentsPortableExporter = true
        }
    }

    private func makeFullBackup() async {
        await performWork {
            let snapshot = try await makeCoordinator().snapshot(
                includePrivateFeedSecrets: includesPrivateFeeds
            )
            let encryptedPrivateData: ArchiveEncryptedPrivateData?
            if let privatePayload = snapshot.privatePayload {
                let passphrase = exportPassphrase
                encryptedPrivateData = try await Task.detached(priority: .userInitiated) {
                    let salt = try BackupKeyDerivation.randomSalt()
                    let key = try BackupKeyDerivation.deriveKey(
                        passphrase: passphrase,
                        salt: salt
                    )
                    return try ArchivePrivateDataCipher.encrypt(
                        privatePayload,
                        using: key,
                        salt: salt,
                        keyDerivationIterations: Int(BackupKeyDerivation.recommendedIterations)
                    )
                }.value
            } else {
                encryptedPrivateData = nil
            }

            let envelope = FullFidelityArchiveEnvelope(
                exportedAt: .now,
                generator: "WhatFun 0.1",
                payload: snapshot.payload,
                preferences: archivePreferences,
                encryptedPrivateData: encryptedPrivateData
            )
            fullDocument = FullBackupDocument(data: try FullFidelityArchiveCodec.encode(envelope))
            queuesFullExporterAfterDismiss = true
            presentsFullExportOptions = false
        }
    }

    private func receivePortableArchive(_ result: Result<[URL], Error>) {
        Task {
            await performWork {
                let url = try singleURL(from: result)
                let package = try PortableArchiveDocument.readPackage(from: url)
                queueRestore(.portable(package))
            }
        }
    }

    private func receiveFullBackup(_ result: Result<[URL], Error>) {
        Task {
            await performWork {
                let url = try singleURL(from: result)
                let data = try readSecurityScopedData(from: url)
                let envelope = try FullFidelityArchiveCodec.decode(data)
                if let encrypted = envelope.encryptedPrivateData {
                    guard encrypted.salt != nil, encrypted.keyDerivationIterations != nil else {
                        throw ImportExportError.missingKeyDerivationMetadata
                    }
                    encryptedBackup = EncryptedBackupRequest(data: data, encrypted: encrypted)
                } else {
                    queueRestore(.full(data: data, key: nil))
                }
            }
        }
    }

    private func receiveLegacyImport(_ result: Result<[URL], Error>) {
        let source = selectedLegacySource
        Task {
            await performWork {
                let url = try singleURL(from: result)
                let data = try readSecurityScopedData(from: url)
                let batch = try source.stage(data, filename: url.lastPathComponent)
                stagedImport = ImportCandidateMatcher().matching(batch, against: importCatalog)
            }
        }
    }

    private func queueRestore(_ source: PendingRestore.Source) {
        pendingRestore = PendingRestore(source: source, mode: restorePolicy.mode)
        confirmsRestore = true
    }

    private func finishFullExportOptions() {
        scrubExportPassphrase()
        includesPrivateFeeds = false
        guard queuesFullExporterAfterDismiss else { return }
        queuesFullExporterAfterDismiss = false
        Task { @MainActor in
            await Task.yield()
            presentsFullExporter = true
        }
    }

    private func finishEncryptedUnlock() {
        encryptedBackup = nil
        guard let source = queuedRestoreAfterUnlock else { return }
        queuedRestoreAfterUnlock = nil
        Task { @MainActor in
            await Task.yield()
            queueRestore(source)
        }
    }

    private func scrubExportPassphrase() {
        exportPassphrase = ""
        exportPassphraseConfirmation = ""
    }

    private func performRestore(_ request: PendingRestore) async {
        pendingRestore = nil
        await performWork {
            let coordinator = try makeCoordinator()
            let oldNotificationIdentifiers = request.mode == .replaceAll
                ? try modelContext.fetch(FetchDescriptor<StartReminder>()).map(\.notificationIdentifier)
                : []
            if request.mode == .replaceAll {
                _ = try await writeRedactedDailyBackup()
            }

            let report: ArchiveRestoreReport
            switch request.source {
            case let .portable(package):
                report = try await coordinator.restorePortablePackage(package, mode: request.mode)
            case let .full(data, key):
                report = try await coordinator.restoreFullBackup(
                    data,
                    encryptionKey: key,
                    mode: request.mode
                )
            }
            if request.mode == .replaceAll,
               case let .full(data, _) = request.source {
                try restorePreferences(from: data)
            }
            let reminderResult = await reschedulePendingReminders(
                cancelling: oldNotificationIdentifiers
            )
            let reminderMessage = reminderResult.failures == 0
                ? " Rescheduled \(reminderResult.scheduled) start reminders."
                : " \(reminderResult.failures) start reminders could not be rescheduled."
            notice = ImportExportNotice(
                title: "Restore Complete",
                message: "Inserted \(report.insertedRecords) records and skipped \(report.skippedExistingRecords) existing records. \(report.warnings.count) warnings were recorded.\(reminderMessage)"
            )
            await refreshBackupList()
        }
    }

    private func createDailyBackup(showSuccess: Bool) async {
        await performWork {
            let url = try await writeRedactedDailyBackup()
            if showSuccess {
                notice = ImportExportNotice(
                    title: "Snapshot Created",
                    message: "Saved \(url.lastPathComponent)."
                )
            }
            await refreshBackupList()
        }
    }

    @discardableResult
    private func writeRedactedDailyBackup() async throws -> URL {
        let coordinator = try makeCoordinator(
            generator: DurabilityCoordinator.automaticRecoveryGenerator
        )
        let url = try await coordinator.writeDailyBackup(preferences: archivePreferences)
        lastBackupTimestamp = Date.now.timeIntervalSince1970
        lastBackupError = ""
        return url
    }

    private func queueLatestBackup() async {
        await performWork {
            let data = try await DailyBackupStore.applicationSupport().latestValidBackup()
            queueRestore(.full(data: data, key: nil))
        }
    }

    private func refreshBackupList() async {
        do {
            backupURLs = try await DailyBackupStore.applicationSupport().backupURLsNewestFirst()
        } catch {
            lastBackupError = error.localizedDescription
        }
    }

    private func restorePreferences(from data: Data) throws {
        let preferences = try FullFidelityArchiveCodec.decode(data).preferences
        if let value = preferences["library.grid-style"],
           LibraryGridStyle(rawValue: value) != nil {
            gridStyleRaw = value
        }
        if let value = preferences["reminders.default-hour"],
           let hour = Int(value),
           (0 ... 23).contains(hour) {
            defaultReminderHour = hour
        }
    }

    private func reschedulePendingReminders(
        cancelling oldIdentifiers: [String]
    ) async -> (scheduled: Int, failures: Int) {
        for identifier in oldIdentifiers {
            await services.reminders.cancel(identifier: identifier)
        }

        guard await services.reminders.authorization() == .authorized else {
            return (0, 0)
        }

        let reminders: [StartReminder]
        do {
            reminders = try modelContext.fetch(FetchDescriptor<StartReminder>())
        } catch {
            return (0, 1)
        }

        var scheduled = 0
        var failures = 0
        for reminder in reminders where reminder.state == .pending && reminder.fireAt > .now {
            guard let item = reminder.item else {
                failures += 1
                continue
            }
            do {
                try await services.reminders.schedule(ReminderRequest(
                    identifier: reminder.notificationIdentifier,
                    title: "Start \(item.title)",
                    body: "You planned to start this today.",
                    fireAt: reminder.fireAt,
                    timeZoneIdentifier: reminder.timeZoneIdentifier
                ))
                scheduled += 1
            } catch {
                failures += 1
            }
        }
        return (scheduled, failures)
    }

    private func performWork(_ operation: @escaping @MainActor () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch is CancellationError {
            // A dismissed document picker is not an archive failure.
        } catch {
            notice = ImportExportNotice(title: "Couldn’t Complete That", message: error.localizedDescription)
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>, label: String) {
        switch result {
        case let .success(url):
            notice = ImportExportNotice(title: "\(label) Saved", message: url.lastPathComponent)
        case let .failure(error):
            notice = ImportExportNotice(title: "Couldn’t Export", message: error.localizedDescription)
        }
    }

    private func singleURL(from result: Result<[URL], Error>) throws -> URL {
        let urls = try result.get()
        guard let url = urls.first else { throw CancellationError() }
        return url
    }

    private func readSecurityScopedData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let limit = FullBackupDocument.maximumByteCount
        if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > limit {
            throw ArchiveDocumentError.fileTooLarge(limit)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limit else {
            throw ArchiveDocumentError.fileTooLarge(limit)
        }
        return data
    }

    private var importCatalog: [ImportCatalogEntry] {
        items.map { item in
            let identifiers = (item.externalReferences ?? []).reduce(into: [String: String]()) {
                $0[$1.providerRaw] = $1.externalID
                if let url = $1.canonicalURLString { $0["source_url"] = url }
                if $1.isActiveFeed, let url = $1.canonicalURLString { $0["feed_url"] = url }
            }
            return ImportCatalogEntry(
                id: item.id,
                title: item.title,
                mediaKind: item.mediaKind.archiveKind,
                externalIdentifiers: identifiers
            )
        }
    }
}

private enum RestorePolicy: String, CaseIterable, Identifiable {
    case mergeNew
    case replaceAll

    var id: Self { self }

    var displayName: String {
        switch self {
        case .mergeNew: "Merge New Records"
        case .replaceAll: "Replace Everything"
        }
    }

    var mode: ArchiveRestoreMode {
        switch self {
        case .mergeNew: .mergeNew
        case .replaceAll: .replaceAll
        }
    }
}

private enum LegacyImportSource: String, CaseIterable, Identifiable {
    case sofa
    case overcast
    case opml

    var id: Self { self }

    var buttonTitle: String {
        switch self {
        case .sofa: "Import Sofa CSV"
        case .overcast: "Import Overcast CSV"
        case .opml: "Import Podcast OPML"
        }
    }

    var symbolName: String {
        switch self {
        case .sofa: "sofa"
        case .overcast: "waveform"
        case .opml: "dot.radiowaves.left.and.right"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .sofa, .overcast: [.commaSeparatedText, .plainText]
        case .opml: [.xml, .plainText]
        }
    }

    func stage(_ data: Data, filename: String) throws -> StagedImportBatch {
        switch self {
        case .sofa: try SofaCSVImporter().stage(data, sourceFilename: filename)
        case .overcast: try OvercastAllDataImporter().stage(data, sourceFilename: filename)
        case .opml: try OPMLPodcastImporter().stage(data, sourceFilename: filename)
        }
    }
}

private struct PendingRestore {
    enum Source {
        case portable(PortableArchivePackage)
        case full(data: Data, key: SymmetricKey?)
    }

    let source: Source
    let mode: ArchiveRestoreMode
}

private struct EncryptedBackupRequest: Identifiable {
    let id = UUID()
    let data: Data
    let encrypted: ArchiveEncryptedPrivateData
}

private struct ImportExportNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum ImportExportError: Error, LocalizedError {
    case missingKeyDerivationMetadata
    case unsupportedKeyDerivationIterations(Int)

    var errorDescription: String? {
        switch self {
        case .missingKeyDerivationMetadata:
            "This encrypted backup does not include the salt and iteration count needed to unlock it."
        case let .unsupportedKeyDerivationIterations(iterations):
            "This backup requests an unsupported passphrase work factor (\(iterations) iterations)."
        }
    }
}

private struct BackupUnlockView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var isUnlocking = false
    @State private var errorMessage: String?

    let request: EncryptedBackupRequest
    let unlocked: (SymmetricKey) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Backup Passphrase", text: $passphrase)
                        .textContentType(.password)
                } footer: {
                    Text("WhatFun authenticates the encrypted private-feed block before changing your library.")
                }
            }
            .navigationTitle("Unlock Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isUnlocking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock") { unlock() }
                        .disabled(passphrase.isEmpty || isUnlocking)
                }
            }
            .overlay { if isUnlocking { ProgressView() } }
            .alert("Couldn’t Unlock Backup", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Check the passphrase and try again.")
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isUnlocking)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func unlock() {
        isUnlocking = true
        let passphrase = passphrase
        let encrypted = request.encrypted
        Task {
            defer { isUnlocking = false }
            do {
                guard let salt = encrypted.salt,
                      let iterations = encrypted.keyDerivationIterations else {
                    throw ImportExportError.missingKeyDerivationMetadata
                }
                guard (1 ... BackupPassphrasePolicy.maximumImportedIterations).contains(iterations) else {
                    throw ImportExportError.unsupportedKeyDerivationIterations(iterations)
                }
                guard encrypted.algorithm == ArchivePrivateDataCipher.algorithm else {
                    throw ArchivePrivateDataCipherError.unsupportedAlgorithm(encrypted.algorithm)
                }
                let key = try await Task.detached(priority: .userInitiated) {
                    let key = try BackupKeyDerivation.deriveKey(
                        passphrase: passphrase,
                        salt: salt,
                        iterations: UInt32(iterations)
                    )
                    _ = try ArchivePrivateDataCipher.decryptPayload(encrypted, using: key)
                    return key
                }.value
                try Task.checkCancellation()
                unlocked(key)
            } catch is CancellationError {
                // The sheet is leaving; do not surface a stale failure.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private nonisolated enum BackupPassphrasePolicy {
    /// Keeps crafted backups from pinning a UI process while leaving room for future KDF tuning.
    static let maximumImportedIterations = 2_000_000
}

private extension MediaKind {
    var archiveKind: ArchiveMediaKind {
        switch self {
        case .book: .book
        case .comic: .comic
        case .movie: .movie
        case .tvShow: .television
        case .game: .game
        case .podcast: .podcast
        case .unknown: .book
        }
    }
}
