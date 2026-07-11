import SwiftData
import SwiftUI

struct ItemDetailView: View {
    private let itemID: UUID

    @Query private var matchingItems: [LibraryItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppServices.self) private var services

    @State private var presentedSheet: DetailSheet?
    @State private var showsDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var isRefreshingPodcast = false

    init(itemID: UUID) {
        self.itemID = itemID
        _matchingItems = Query(
            filter: #Predicate<LibraryItem> { $0.id == itemID }
        )
    }

    private var item: LibraryItem? { matchingItems.first }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ItemHero(item: item)
                        ItemPrimaryActions(
                            item: item,
                            log: { navigation.presentedSheet = .logSession(item.id) },
                            markDone: { presentedSheet = .markDone(item.id) },
                            continueItem: continueItem
                        )
                        ItemProgressSection(item: item)

                        if item.mediaKind == .tvShow ||
                            item.mediaKind == .comic ||
                            item.mediaKind == .podcast {
                            InstallmentSection(
                                item: item,
                                addTopLevel: { presentedSheet = .addUnit(item.id, nil) },
                                addChild: { presentedSheet = .addUnit(item.id, $0.id) },
                                addQuote: { presentedSheet = .addQuote($0.id) }
                            )
                        }

                        SessionHistorySection(item: item, deleteSession: deleteSession)
                        PersonalMetadataSection(item: item)
                        MilestoneSection(item: item)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .archiveBackground()
                .toolbar { toolbar(for: item) }
            } else {
                ContentUnavailableView(
                    "Item not found",
                    systemImage: "questionmark.folder",
                    description: Text("This item may have been moved or deleted.")
                )
                .archiveBackground()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case let .markDone(id):
                MarkDoneView(itemID: id)
            case let .addUnit(itemID, parentID):
                ContentUnitEditorView(itemID: itemID, parentUnitID: parentID)
            case let .addQuote(episodeID):
                QuoteEditorView(episodeID: episodeID)
            }
        }
        .confirmationDialog(
            "Move this item to Recently Deleted?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
                moveToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its complete history can be recovered for 30 days.")
        }
        .alert("Couldn’t Update Item", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    @ToolbarContentBuilder
    private func toolbar(for item: LibraryItem) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(item.isFavorite ? "Remove Favorite" : "Favorite", systemImage: item.isFavorite ? "heart.fill" : "heart") {
                item.isFavorite.toggle()
                item.updatedAt = .now
                saveContext()
            }
            .tint(item.isFavorite ? WhatFunTheme.coral : nil)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit", systemImage: "pencil") {
                navigation.presentedSheet = .editItem(item.id)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if item.mediaKind == .podcast {
                    Button("Refresh Podcast Feed", systemImage: "arrow.clockwise") {
                        Task { await refreshPodcast(item) }
                    }
                    .disabled(isRefreshingPodcast)

                    Divider()
                }

                statusMenu(for: item)

                Divider()

                Button("Archive", systemImage: "archivebox") {
                    do {
                        try ActivityService(context: modelContext).archive(item)
                        navigation.popCurrent()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    @ViewBuilder
    private func statusMenu(for item: LibraryItem) -> some View {
        Section("Status") {
            if item.status == .paused || item.status == .dropped {
                Button("Resume", systemImage: "play") { setStatus(.inProgress) }
            } else if item.status == .inProgress {
                Button("Pause", systemImage: "pause") { setStatus(.paused) }
            }
            if item.status != .dropped {
                Button("Drop", systemImage: "xmark.circle") { setStatus(.dropped) }
            }
            if item.status != .planned {
                Button("Return to Planned", systemImage: "bookmark") { setStatus(.planned) }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func continueItem(_ choice: ContinueChoice) {
        guard let item else { return }
        do {
            let service = ActivityService(context: modelContext)
            switch choice {
            case .repeatConsumption:
                _ = try service.startRepeat(for: item)
            case let .nextInstallment(unit):
                _ = try service.startNextInstallment(for: item, targetUnit: unit)
            }
            navigation.presentedSheet = .logSession(item.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setStatus(_ status: ConsumptionStatus) {
        guard let item else { return }
        let active = (item.cycles ?? [])
            .filter { $0.deletedAt == nil && ($0.status == .inProgress || $0.status == .paused) }
            .max { $0.ordinal < $1.ordinal }
        do {
            _ = try ActivityService(context: modelContext).setStatus(
                status,
                for: item,
                cycle: active,
                targetUnit: active?.targetUnit
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSession(_ session: ConsumptionSession) {
        guard let item else { return }
        session.deletedAt = .now
        session.updatedAt = .now
        ActivityProjection.rebuild(item)
        saveContext()
    }

    private func moveToTrash() {
        guard let item else { return }
        do {
            try ActivityService(context: modelContext).moveToTrash(item)
            navigation.popCurrent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshPodcast(_ item: LibraryItem) async {
        isRefreshingPodcast = true
        defer { isRefreshingPodcast = false }
        do {
            _ = try await PodcastFeedSyncService(
                context: modelContext,
                credentials: services.credentials,
                refresher: services.metadata.podcastFeeds
            ).refresh(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum DetailSheet: Identifiable {
    case markDone(UUID)
    case addUnit(UUID, UUID?)
    case addQuote(UUID)

    var id: String {
        switch self {
        case let .markDone(id): "done-\(id)"
        case let .addUnit(itemID, parentID): "unit-\(itemID)-\(parentID?.uuidString ?? "root")"
        case let .addQuote(id): "quote-\(id)"
        }
    }
}

private enum ContinueChoice {
    case repeatConsumption
    case nextInstallment(ContentUnit)
}

private struct ItemHero: View {
    let item: LibraryItem

    var body: some View {
        VStack(spacing: 18) {
            CoverArtworkView(item: item, contentMode: .fit)
                .aspectRatio(item.coverAspectRatio, contentMode: .fit)
                .frame(maxWidth: 210, maxHeight: 300)
                .background(WhatFunTheme.raisedBackground)
                .clipShape(CoverShape(cornerRadius: 28))
                .overlay {
                    CoverShape(cornerRadius: 28)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: WhatFunTheme.ink.opacity(0.18), radius: 16, y: 9)

            VStack(spacing: 7) {
                Text(item.title)
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .multilineTextAlignment(.center)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                }

                if let creator = item.creatorLine {
                    Text(creator)
                        .font(.subheadline)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Label(item.status.displayName, systemImage: item.status.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.status.color)

                    if item.effectiveRatingHalfSteps != nil {
                        RatingLabel(halfSteps: item.effectiveRatingHalfSteps, showsValue: true)
                    }
                }
            }

            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
                    .frame(maxWidth: 620, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

private struct ItemPrimaryActions: View {
    let item: LibraryItem
    let log: () -> Void
    let markDone: () -> Void
    let continueItem: (ContinueChoice) -> Void

    private var nextInstallment: ContentUnit? {
        let expectedKind: ContentUnitKind? = switch item.mediaKind {
        case .tvShow: .tvSeason
        case .comic: .comicVolume
        default: nil
        }
        guard let expectedKind else { return nil }
        return (item.units ?? [])
            .filter {
                $0.deletedAt == nil && $0.parentUnitID == nil &&
                    $0.unitKind == expectedKind && $0.status != .completed
            }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("Log Session", systemImage: "plus.circle.fill", action: log)
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)

                if item.status == .completed {
                    Menu {
                        if let nextInstallment {
                            Button("Start \(nextInstallment.title)", systemImage: "forward.end") {
                                continueItem(.nextInstallment(nextInstallment))
                            }
                        }
                        Button(repeatLabel, systemImage: "arrow.counterclockwise") {
                            continueItem(.repeatConsumption)
                        }
                    } label: {
                        Label("Continue", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
                } else {
                    Button("Mark Done", systemImage: "checkmark.circle", action: markDone)
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var repeatLabel: LocalizedStringKey {
        switch item.mediaKind {
        case .book, .comic: "Start Reread"
        case .movie, .tvShow: "Start Rewatch"
        case .game: "Start Replay"
        case .podcast: "Listen Again"
        case .unknown: "Start Again"
        }
    }
}

private struct ItemProgressSection: View {
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "History at a Glance")

            if let progress = item.progressFraction {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(item.mediaKind.accentColor)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }
            }

            HStack(spacing: 0) {
                HistoryMetric(value: item.sessionCount, label: "Sessions")
                Divider().frame(height: 34)
                HistoryMetric(value: item.cycleCount, label: "Cycles")
                Divider().frame(height: 34)
                HistoryMetric(value: item.repeatCount, label: "Repeats")
            }

            if let first = item.firstStartedAt {
                Label {
                    Text("Started \(first, format: .dateTime.day().month().year())")
                } icon: {
                    Image(systemName: "play.circle")
                }
                .font(.subheadline)
                .foregroundStyle(WhatFunTheme.secondaryInk)
            }

            if let completed = item.lastCompletedAt {
                Label {
                    Text("Completed \(completed, format: .dateTime.day().month().year())")
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                .font(.subheadline)
                .foregroundStyle(WhatFunTheme.secondaryInk)
            }
        }
    }
}

private struct HistoryMetric: View {
    let value: Int
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 2) {
            Text(value, format: .number)
                .font(.title2.bold().monospacedDigit())
                .fontDesign(.rounded)
            Text(label)
                .font(.caption)
                .foregroundStyle(WhatFunTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct InstallmentSection: View {
    let item: LibraryItem
    let addTopLevel: () -> Void
    let addChild: (ContentUnit) -> Void
    let addQuote: (ContentUnit) -> Void

    private var topLevelUnits: [ContentUnit] {
        (item.units ?? [])
            .filter { $0.deletedAt == nil && $0.parentUnitID == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: sectionTitle)
                Spacer()
                Button("Add", systemImage: "plus", action: addTopLevel)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            if topLevelUnits.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
                    .padding(.vertical, 10)
            } else {
                ForEach(topLevelUnits) { unit in
                    if let children = unit.children?.filter({ $0.deletedAt == nil }), !children.isEmpty {
                        DisclosureGroup {
                            VStack(spacing: 0) {
                                ForEach(children.sorted { $0.sortOrder < $1.sortOrder }) { child in
                                    UnitRow(
                                        unit: child,
                                        permitsChildren: false,
                                        addChild: {},
                                        addQuote: { addQuote(child) }
                                    )
                                    .padding(.leading, 12)
                                }
                            }
                        } label: {
                            UnitRow(
                                unit: unit,
                                permitsChildren: permitsChildren(unit),
                                addChild: { addChild(unit) },
                                addQuote: { addQuote(unit) }
                            )
                        }
                    } else {
                        UnitRow(
                            unit: unit,
                            permitsChildren: permitsChildren(unit),
                            addChild: { addChild(unit) },
                            addQuote: { addQuote(unit) }
                        )
                    }
                }
            }
        }
    }

    private var sectionTitle: LocalizedStringKey {
        switch item.mediaKind {
        case .tvShow: "Seasons & Episodes"
        case .comic: "Volumes & Issues"
        case .podcast: "Episodes"
        default: "Installments"
        }
    }

    private var emptyMessage: LocalizedStringKey {
        switch item.mediaKind {
        case .tvShow: "Add a season, then optional episodes."
        case .comic: "Add a volume, then optional individual issues."
        case .podcast: "Add a special episode you want to remember."
        default: "No installments yet."
        }
    }

    private func permitsChildren(_ unit: ContentUnit) -> Bool {
        unit.unitKind == .tvSeason || unit.unitKind == .comicVolume
    }
}

private struct UnitRow: View {
    let unit: ContentUnit
    let permitsChildren: Bool
    let addChild: () -> Void
    let addQuote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: unit.status.symbolName)
                    .foregroundStyle(unit.status.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.title)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(unit.status.displayName)
                        if unit.isNotable {
                            Label("Notable", systemImage: "quote.bubble.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(WhatFunTheme.secondaryInk)
                }
                Spacer()
                if let rating = unit.ratingHalfSteps {
                    RatingLabel(halfSteps: rating)
                }
                Menu {
                    if permitsChildren {
                        Button("Add Installment", systemImage: "plus") { addChild() }
                    }
                    if unit.unitKind == .podcastEpisode {
                        Button("Add Notable Quote", systemImage: "quote.bubble") { addQuote() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More actions for \(unit.title)")
                }
            }

            ForEach((unit.notableQuotes ?? []).filter { $0.deletedAt == nil }.sorted { $0.sortOrder < $1.sortOrder }) { quote in
                VStack(alignment: .leading, spacing: 3) {
                    Text("“\(quote.text)”")
                        .font(.subheadline)
                    if let timestamp = quote.timestampSeconds {
                        Text(Duration.seconds(timestamp).formatted(.time(pattern: .minuteSecond)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(WhatFunTheme.secondaryInk)
                    }
                    if let comment = quote.comment {
                        Text(comment)
                            .font(.caption)
                            .foregroundStyle(WhatFunTheme.secondaryInk)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct SessionHistorySection: View {
    let item: LibraryItem
    let deleteSession: (ConsumptionSession) -> Void

    private var sessions: [ConsumptionSession] {
        (item.cycles ?? [])
            .flatMap { $0.sessions ?? [] }
            .filter { $0.deletedAt == nil }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Session History",
                subtitle: sessions.isEmpty ? "No sessions logged yet" : "\(sessions.count) total"
            )

            ForEach(sessions) { session in
                SessionRow(session: session)
                    .contextMenu {
                        Button("Remove Session", systemImage: "trash", role: .destructive) {
                            deleteSession(session)
                        }
                    }
            }
        }
    }
}

private struct SessionRow: View {
    let session: ConsumptionSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(WhatFunTheme.coral)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.occurredAt, format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                    .font(.headline)

                HStack(spacing: 10) {
                    if let duration = session.durationSeconds {
                        Label(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)), systemImage: "timer")
                    }
                    if let progress = progressText {
                        Label(progress, systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
                .font(.caption)
                .foregroundStyle(WhatFunTheme.secondaryInk)

                if let note = session.note {
                    Text(note)
                        .font(.subheadline)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var progressText: String? {
        if let page = session.currentPage {
            return session.totalPagesSnapshot.map { "Page \(page) of \($0)" } ?? "Page \(page)"
        }
        if let elapsed = session.elapsedSeconds {
            return "\(elapsed / 60) min elapsed"
        }
        if let percent = session.completionPercent {
            return percent.formatted(.percent.scale(1).precision(.fractionLength(0 ... 1)))
        }
        if let seconds = session.gamePlaytimeTotalSnapshotSeconds {
            return "\((Double(seconds) / 3_600).formatted(.number.precision(.fractionLength(0 ... 1)))) hr played"
        }
        return nil
    }
}

private struct PersonalMetadataSection: View {
    let item: LibraryItem

    private var facets: [Facet] {
        (item.facetMemberships ?? []).compactMap(\.facet).sorted { $0.name < $1.name }
    }

    var body: some View {
        if item.comment != nil || !facets.isEmpty || item.mediaKind == .podcast || !(item.externalReferences ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Notes & Metadata")

                if let comment = item.comment {
                    Text(comment)
                }

                if item.mediaKind == .podcast {
                    if let state = item.podcastFollowState {
                        Label(state.displayName, systemImage: "dot.radiowaves.left.and.right")
                    }
                    if let style = item.podcastListeningStyle {
                        Text(style.displayName)
                            .foregroundStyle(WhatFunTheme.secondaryInk)
                    }
                }

                if !facets.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(facets) { facet in
                                Text(facet.name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(facet.kind == .tag ? WhatFunTheme.coral.opacity(0.16) : WhatFunTheme.sky.opacity(0.14), in: .capsule)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                ForEach((item.externalReferences ?? []).filter { $0.attributionText != nil }) { reference in
                    if let text = reference.attributionText {
                        if let value = reference.attributionURLString, let url = URL(string: value) {
                            Link(text, destination: url)
                                .font(.footnote)
                        } else {
                            Text(text).font(.footnote)
                        }
                    }
                }
            }
        }
    }
}

private struct MilestoneSection: View {
    let item: LibraryItem

    private var events: [ActivityEvent] {
        (item.activityEvents ?? [])
            .filter { $0.kind == .completed || $0.kind == .started || $0.kind == .reopened }
            .sorted { $0.effectiveAt > $1.effectiveAt }
    }

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "Milestones")
                ForEach(events.prefix(12)) { event in
                    HStack(spacing: 10) {
                        Image(systemName: symbol(for: event.kind))
                            .foregroundStyle(event.kind == .completed ? WhatFunTheme.sage : WhatFunTheme.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(for: event.kind))
                                .font(.subheadline.weight(.semibold))
                            Text(event.effectiveAt, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(WhatFunTheme.secondaryInk)
                        }
                    }
                }
            }
        }
    }

    private func label(for kind: ActivityEventKind) -> LocalizedStringKey {
        switch kind {
        case .completed: "Completed"
        case .started: "Started"
        case .reopened: "Resumed"
        default: "Updated"
        }
    }

    private func symbol(for kind: ActivityEventKind) -> String {
        switch kind {
        case .completed: "checkmark.circle.fill"
        case .started: "play.circle.fill"
        case .reopened: "arrow.clockwise.circle"
        default: "circle"
        }
    }
}
