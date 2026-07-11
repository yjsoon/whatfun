import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ItemEditorView: View {
    private let itemID: UUID?

    @Query private var matchingItems: [LibraryItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @State private var draft: ItemDraft
    @State private var didLoadExistingItem = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedCoverData: Data?
    @State private var isChoosingFile = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        itemID: UUID? = nil,
        initialKind: MediaKind = .book,
        initialTitle: String = ""
    ) {
        self.itemID = itemID
        let queryID = itemID ?? UUID()
        _matchingItems = Query(
            filter: #Predicate<LibraryItem> { $0.id == queryID }
        )
        _draft = State(
            initialValue: ItemDraft(mediaKind: initialKind, title: initialTitle)
        )
    }

    private var existingItem: LibraryItem? {
        itemID == nil ? nil : matchingItems.first
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                detailsSection
                typeSpecificSection
                organizationSection
                artworkSection
                reminderSection
                personalSection
            }
            .scrollContentBackground(.hidden)
            .background(WhatFunTheme.background)
            .navigationTitle(existingItem == nil ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(draft.trimmedTitle.isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .glassEffect(in: .rect(cornerRadius: 18))
                }
            }
            .task {
                guard !didLoadExistingItem, let existingItem else { return }
                draft = ItemDraft(item: existingItem)
                didLoadExistingItem = true
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    do {
                        selectedCoverData = try await item.loadTransferable(type: Data.self)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                importCover(result)
            }
            .alert("Couldn’t Save", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private var identitySection: some View {
        Section("Identity") {
            Picker("Media Type", selection: $draft.mediaKind) {
                ForEach(MediaKind.filterCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName)
                        .tag(kind)
                }
            }

            TextField("Title", text: $draft.title)
                .textInputAutocapitalization(.words)
            TextField("Subtitle", text: $draft.subtitle)
            TextField("Creator, director, host…", text: $draft.creatorLine)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Release year", text: $draft.releaseYear)
                .keyboardType(.numberPad)
            TextField("Summary", text: $draft.summary, axis: .vertical)
                .lineLimit(3 ... 8)

            Picker("Status", selection: $draft.status) {
                ForEach([
                    ConsumptionStatus.planned,
                    .inProgress,
                    .paused,
                    .completed,
                    .dropped,
                ], id: \.self) { status in
                    Label(status.displayName, systemImage: status.symbolName)
                        .tag(status)
                }
            }

            Picker("Rating", selection: $draft.ratingHalfSteps) {
                Text("Not Rated").tag(Int?.none)
                ForEach(1 ... 10, id: \.self) { halfSteps in
                    Text("\(Double(halfSteps) / 2, format: .number.precision(.fractionLength(1))) stars")
                        .tag(Int?.some(halfSteps))
                }
            }
        }
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch draft.mediaKind {
        case .book, .comic:
            Section(draft.mediaKind == .book ? "Reading" : "Comic") {
                TextField("Total pages (optional)", text: $draft.pageCount)
                    .keyboardType(.numberPad)
                if draft.mediaKind == .comic {
                    Text("Volumes and individual issues can be added from the item detail after saving.")
                        .font(.footnote)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
            }

        case .movie:
            Section("Movie") {
                TextField("Runtime in minutes (optional)", text: $draft.runtimeMinutes)
                    .keyboardType(.numberPad)
            }

        case .tvShow:
            Section("TV Show") {
                Text("Seasons and episodes can be added from the item detail. Season ratings derive the show rating until you override it here.")
                    .font(.footnote)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }

        case .game:
            Section("Game") {
                TextField("Platforms, comma separated", text: $draft.platforms)
            }

        case .podcast:
            Section("Podcast") {
                Picker("Following", selection: $draft.podcastFollowState) {
                    ForEach([
                        PodcastFollowState.following,
                        .paused,
                        .completed,
                        .dropped,
                    ], id: \.self) { state in
                        Text(state.displayName).tag(state)
                    }
                }

                Picker("Listening Style", selection: $draft.podcastListeningStyle) {
                    ForEach([
                        PodcastListeningStyle.everyEpisode,
                        .selectedEpisodes,
                        .keepAround,
                    ], id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                TextField("RSS feed URL (optional)", text: $draft.feedURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Toggle("Private or premium feed", isOn: $draft.isPrivateFeed)
                if draft.isPrivateFeed {
                    Text("The feed address is saved in Keychain and redacted from portable exports.")
                        .font(.footnote)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
            }

        case .unknown:
            EmptyView()
        }
    }

    private var organizationSection: some View {
        Section("Organization") {
            TextField("Tags, comma separated", text: $draft.tags)
            TextField("Genres, comma separated", text: $draft.genres)
        }
    }

    private var artworkSection: some View {
        let hasSelectedCover = selectedCoverData != nil

        return Section("Cover Art") {
            if let existingItem, existingItem.preferredArtwork != nil, selectedCoverData == nil {
                CoverArtworkView(item: existingItem, contentMode: .fit)
                    .aspectRatio(existingItem.coverAspectRatio, contentMode: .fit)
                    .frame(maxWidth: 120, maxHeight: 170)
                    .clipShape(CoverShape(cornerRadius: 15))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(
                    hasSelectedCover ? "Photo Selected" : "Choose from Photos",
                    systemImage: hasSelectedCover ? "checkmark.circle.fill" : "photo.on.rectangle"
                )
            }

            Button("Choose from Files", systemImage: "folder") {
                isChoosingFile = true
            }

            TextField("Or paste a cover URL", text: $draft.coverURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    }

    private var reminderSection: some View {
        Section("Start Date") {
            Toggle("Remind me once", isOn: $draft.hasStartReminder)
            if draft.hasStartReminder {
                DatePicker(
                    "When",
                    selection: $draft.startReminderDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Text("If it becomes overdue, WhatFun leaves it quietly on Home without repeated nags.")
                    .font(.footnote)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        }
    }

    private var personalSection: some View {
        Section("Personal") {
            Toggle("Favorite", isOn: $draft.isFavorite)
            TextField("Freeform comment", text: $draft.comment, axis: .vertical)
                .lineLimit(3 ... 8)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() async {
        guard !draft.trimmedTitle.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let isNew = existingItem == nil
            let item = existingItem ?? LibraryItem(
                mediaKind: draft.mediaKind,
                title: draft.trimmedTitle
            )
            let previousStatus = item.status
            apply(draft, to: item)
            try reconcileFacets(for: item)
            try await reconcileArtwork(for: item)
            try await reconcilePodcastFeed(for: item)
            let reminder = reconcileReminder(for: item)

            let activity = ActivityService(context: modelContext)
            if isNew {
                _ = try activity.register(item)
            }

            if draft.status != previousStatus || (isNew && draft.status != .planned) {
                try applyStatus(draft.status, to: item, using: activity)
            } else {
                ActivityProjection.rebuild(item)
                try modelContext.save()
            }

            try await schedule(reminder: reminder, for: item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ draft: ItemDraft, to item: LibraryItem) {
        item.mediaKind = draft.mediaKind
        item.setTitle(draft.trimmedTitle)
        item.subtitle = draft.subtitle.nilIfBlank
        item.creatorLine = draft.creatorLine.nilIfBlank
        item.summary = draft.summary.nilIfBlank
        item.releaseYear = Int(draft.releaseYear)
        item.pageCount = Int(draft.pageCount)
        item.runtimeSeconds = Int(draft.runtimeMinutes).map { max(0, $0) * 60 }
        item.comment = draft.comment.nilIfBlank
        item.isFavorite = draft.isFavorite
        item.setRating(halfSteps: draft.ratingHalfSteps)
        item.podcastFollowState = draft.mediaKind == .podcast ? draft.podcastFollowState : nil
        item.podcastListeningStyle = draft.mediaKind == .podcast ? draft.podcastListeningStyle : nil
        item.updatedAt = .now
    }

    private func applyStatus(
        _ status: ConsumptionStatus,
        to item: LibraryItem,
        using activity: ActivityService
    ) throws {
        let active = (item.cycles ?? [])
            .filter { $0.deletedAt == nil && ($0.status == .inProgress || $0.status == .paused) }
            .max { $0.ordinal < $1.ordinal }

        if status == .completed {
            let cycle: ConsumptionCycle
            if let active {
                cycle = active
            } else {
                cycle = try activity.startCycle(for: item)
            }
            _ = try activity.markDone(item: item, cycle: cycle, ratingHalfSteps: draft.ratingHalfSteps)
        } else if status == .inProgress, active == nil {
            _ = try activity.startCycle(for: item)
        } else {
            _ = try activity.setStatus(status, for: item, cycle: active)
        }
    }

    private func reconcileFacets(for item: LibraryItem) throws {
        for membership in item.facetMemberships ?? [] {
            modelContext.delete(membership)
        }
        item.facetMemberships = []

        let existingFacets = try modelContext.fetch(FetchDescriptor<Facet>())
        let requested: [(FacetKind, String)] =
            draft.tags.commaSeparated.map { (.tag, $0) } +
            draft.genres.commaSeparated.map { (.genre, $0) } +
            (draft.mediaKind == .game ? draft.platforms.commaSeparated.map { (.platform, $0) } : [])

        var memberships = [ItemFacetMembership]()
        for (index, request) in requested.enumerated() {
            let normalized = LibraryItem.normalize(request.1)
            let facet: Facet
            if let existing = existingFacets.first(where: {
                $0.kind == request.0 && $0.normalizedName == normalized
            }) {
                facet = existing
            } else {
                facet = Facet(kind: request.0, name: request.1)
                modelContext.insert(facet)
            }
            let membership = ItemFacetMembership(
                item: item,
                facet: facet,
                sortOrder: index
            )
            modelContext.insert(membership)
            memberships.append(membership)
        }
        item.facetMemberships = memberships
    }

    private func reconcileArtwork(for item: LibraryItem) async throws {
        if let selectedCoverData {
            let image = await ArtworkDownsampler.image(
                from: selectedCoverData,
                targetSize: CGSize(width: 1_600, height: 2_400),
                displayScale: 1
            )
            guard let image, let archivalData = image.jpegData(compressionQuality: 0.9) else {
                throw ArtworkRepositoryError.invalidImage
            }
            let asset = ArtworkAsset(ownerItem: item, kind: .userImage, imageData: archivalData)
            asset.pixelWidth = Int(image.size.width)
            asset.pixelHeight = Int(image.size.height)
            asset.aspectRatio = image.size.height > 0 ? image.size.width / image.size.height : nil
            modelContext.insert(asset)
            item.artworkAssets = (item.artworkAssets ?? []) + [asset]
            item.preferredArtworkID = asset.id
            return
        }

        guard let coverURL = draft.coverURL.nilIfBlank,
              URL(string: coverURL) != nil,
              item.preferredArtwork?.remoteURLString != coverURL
        else { return }
        let asset = ArtworkAsset(
            ownerItem: item,
            kind: .providerRemote,
            remoteURLString: coverURL
        )
        modelContext.insert(asset)
        item.artworkAssets = (item.artworkAssets ?? []) + [asset]
        item.preferredArtworkID = asset.id
    }

    private func reconcilePodcastFeed(for item: LibraryItem) async throws {
        guard item.mediaKind == .podcast, let feedURL = draft.feedURL.nilIfBlank else { return }
        let existing = (item.externalReferences ?? []).first { $0.providerRaw == "rss" }
        let reference = existing ?? ExternalReference(
            ownerItem: item,
            providerRaw: "rss",
            recordKindRaw: "feed",
            externalID: ArtworkRepository.hash(feedURL)
        )

        reference.isActiveFeed = true
        reference.isPrivateFeed = draft.isPrivateFeed
        if draft.isPrivateFeed {
            let key = reference.credentialKeychainID ?? "private-feed-\(item.id.uuidString)"
            try await services.credentials.set(feedURL, for: key)
            reference.credentialKeychainID = key
            reference.canonicalURLString = nil
        } else {
            if let key = reference.credentialKeychainID {
                try await services.credentials.removeValue(for: key)
            }
            reference.credentialKeychainID = nil
            reference.canonicalURLString = feedURL
        }

        if existing == nil {
            modelContext.insert(reference)
            item.externalReferences = (item.externalReferences ?? []) + [reference]
        }
    }

    private func reconcileReminder(for item: LibraryItem) -> StartReminder? {
        let existing = (item.reminders ?? []).first { $0.state == .pending }
        guard draft.hasStartReminder else {
            if let existing {
                existing.state = .cancelled
                existing.updatedAt = .now
            }
            return existing
        }

        let reminder = existing ?? StartReminder(item: item, fireAt: draft.startReminderDate)
        reminder.fireAt = draft.startReminderDate
        reminder.timeZoneIdentifier = TimeZone.current.identifier
        reminder.state = .pending
        reminder.updatedAt = .now
        if existing == nil {
            modelContext.insert(reminder)
            item.reminders = (item.reminders ?? []) + [reminder]
        }
        return reminder
    }

    private func schedule(reminder: StartReminder?, for item: LibraryItem) async throws {
        guard let reminder else { return }
        if reminder.state == .cancelled {
            await services.reminders.cancel(identifier: reminder.notificationIdentifier)
            return
        }

        var authorization = await services.reminders.authorization()
        if authorization == .notDetermined {
            authorization = try await services.reminders.requestAuthorization() ? .authorized : .denied
        }
        guard authorization == .authorized else { return }
        try await services.reminders.schedule(
            ReminderRequest(
                identifier: reminder.notificationIdentifier,
                title: "Start \(item.title)",
                body: "You planned to start this today.",
                fireAt: reminder.fireAt,
                timeZoneIdentifier: reminder.timeZoneIdentifier
            )
        )
    }

    private func importCover(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            selectedCoverData = try Data(contentsOf: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ItemDraft {
    var mediaKind: MediaKind
    var title = ""
    var subtitle = ""
    var creatorLine = ""
    var summary = ""
    var releaseYear = ""
    var pageCount = ""
    var runtimeMinutes = ""
    var comment = ""
    var isFavorite = false
    var status = ConsumptionStatus.planned
    var ratingHalfSteps: Int?
    var tags = ""
    var genres = ""
    var platforms = ""
    var coverURL = ""
    var feedURL = ""
    var isPrivateFeed = false
    var podcastFollowState = PodcastFollowState.following
    var podcastListeningStyle = PodcastListeningStyle.selectedEpisodes
    var hasStartReminder = false
    var startReminderDate = ItemDraft.defaultReminderDate

    init(mediaKind: MediaKind, title: String = "") {
        self.mediaKind = mediaKind
        self.title = title
    }

    init(item: LibraryItem) {
        mediaKind = item.mediaKind
        title = item.title
        subtitle = item.subtitle ?? ""
        creatorLine = item.creatorLine ?? ""
        summary = item.summary ?? ""
        releaseYear = item.releaseYear.map(String.init) ?? ""
        pageCount = item.pageCount.map(String.init) ?? ""
        runtimeMinutes = item.runtimeSeconds.map { String($0 / 60) } ?? ""
        comment = item.comment ?? ""
        isFavorite = item.isFavorite
        status = item.status
        ratingHalfSteps = item.ratingOverrideHalfSteps
        tags = Self.facetNames(item, kind: .tag)
        genres = Self.facetNames(item, kind: .genre)
        platforms = Self.facetNames(item, kind: .platform)
        coverURL = item.preferredArtwork?.remoteURLString ?? ""
        if let reference = (item.externalReferences ?? []).first(where: { $0.providerRaw == "rss" }) {
            feedURL = reference.canonicalURLString ?? ""
            isPrivateFeed = reference.isPrivateFeed
        }
        podcastFollowState = item.podcastFollowState ?? .following
        podcastListeningStyle = item.podcastListeningStyle ?? .selectedEpisodes
        if let reminder = (item.reminders ?? []).first(where: { $0.state == .pending }) {
            hasStartReminder = true
            startReminderDate = reminder.fireAt
        }
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var defaultReminderDate: Date {
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func facetNames(_ item: LibraryItem, kind: FacetKind) -> String {
        (item.facetMemberships ?? [])
            .compactMap(\.facet)
            .filter { $0.kind == kind }
            .map(\.name)
            .sorted()
            .joined(separator: ", ")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var commaSeparated: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
