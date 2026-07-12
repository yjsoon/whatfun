import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.updatedAt, order: .reverse)]
    ) private var items: [LibraryItem]

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.calendar) private var calendar
    @State private var mediaFilter = MediaFilter.all
    @State private var historyPeriod = HistoryPeriod.week

    private var visibleItems: [LibraryItem] {
        items.filter { $0.archivedAt == nil && mediaFilter.includes($0) }
    }

    private var rails: HomeRailPartition<LibraryItem> {
        HomeRails.partition(visibleItems, now: .now) { item in
            HomeRails.Snapshot(
                status: item.status,
                isFollowedPodcast: item.mediaKind == .podcast && item.podcastFollowState == .following,
                earliestPendingReminderFireDate: (item.reminders ?? [])
                    .filter { $0.state == .pending }
                    .map(\.fireAt)
                    .min()
            )
        }
    }

    private var activeItems: [LibraryItem] { rails.active }

    private var plannedItems: [LibraryItem] { rails.planned }

    private var overdueItems: [LibraryItem] { rails.overdue }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                MediaFilterBar(selection: $mediaFilter)

                if items.isEmpty {
                    welcome
                } else {
                    if !overdueItems.isEmpty {
                        overdueSection
                    }

                    if !activeItems.isEmpty {
                        activeSection
                    }

                    if !plannedItems.isEmpty {
                        upNextSection
                    }

                    ConsumedHistorySection(
                        items: visibleItems,
                        period: historyPeriod,
                        referenceDate: .now,
                        calendar: calendar,
                        selection: $historyPeriod
                    )
                    .id(historyPeriod)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("WhatFun")
        .archiveBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "person.crop.circle") {
                    navigation.showSettings()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !activeItems.isEmpty {
                        Section("Log a Session") {
                            ForEach(activeItems.prefix(8)) { item in
                                Button(item.title, systemImage: item.mediaKind.symbolName) {
                                    navigation.presentedSheet = .logSession(item.id)
                                }
                            }
                        }
                    }

                    Button("Add Item", systemImage: "plus") {
                        navigation.presentedSheet = .addItem
                    }
                } label: {
                    Label("Quick Actions", systemImage: "plus")
                }
            }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("Make room for fun", systemImage: "sparkles")
        } description: {
            Text("Add something you want to read, watch, play, or hear. Each time you return to it, log a new session.")
        } actions: {
            Button("Add Your First Item", systemImage: "plus") {
                navigation.presentedSheet = .addItem
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 480)
    }

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Ready When You Are",
                subtitle: "Start-date reminders that have passed"
            )

            ForEach(overdueItems) { item in
                Button {
                    navigation.showItem(item.id, from: .home)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(WhatFunTheme.coral)
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .font(.headline)
                            Text("Still planned—no pressure")
                                .font(.caption)
                                .foregroundStyle(WhatFunTheme.secondaryInk)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "In Your Orbit",
                subtitle: "One session at a time"
            )
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(activeItems) { item in
                        ActiveItemTile(item: item) {
                            navigation.showItem(item.id, from: .home)
                        } log: {
                            navigation.presentedSheet = .logSession(item.id)
                        }
                        .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 14)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Up Next",
                subtitle: "Planned, whenever you feel like it"
            )
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(plannedItems.prefix(10)) { item in
                        LibraryItemTile(item: item, style: .flow) {
                            navigation.showItem(item.id, from: .home)
                        }
                        .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 14)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
}

private struct ActiveItemTile: View {
    let item: LibraryItem
    let open: () -> Void
    let log: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryItemTile(item: item, style: .flow, action: open)

            Button("Log Session", systemImage: "plus.circle.fill", action: log)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
    }
}

private struct ConsumedHistorySection: View {
    @Query private var sessions: [ConsumptionSession]

    let items: [LibraryItem]
    let period: HistoryPeriod
    let selection: Binding<HistoryPeriod>

    init(
        items: [LibraryItem],
        period: HistoryPeriod,
        referenceDate: Date,
        calendar: Calendar,
        selection: Binding<HistoryPeriod>
    ) {
        self.items = items
        self.period = period
        self.selection = selection

        let interval = period.interval(containing: referenceDate, calendar: calendar)
        let start = interval.start
        let end = interval.end
        _sessions = Query(
            filter: #Predicate<ConsumptionSession> { session in
                session.deletedAt == nil && session.occurredAt >= start && session.occurredAt < end
            },
            sort: [SortDescriptor(\ConsumptionSession.occurredAt, order: .reverse)]
        )
    }

    private var counts: [(item: LibraryItem, summary: SessionCount)] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let interval: DateInterval
        if let first = sessions.last?.occurredAt, let last = sessions.first?.occurredAt {
            interval = DateInterval(start: first, end: last.addingTimeInterval(0.001))
        } else {
            interval = DateInterval(start: .distantPast, end: .distantFuture)
        }
        return SessionAggregator.counts(
            for: sessions.map { SessionOccurrence(itemID: $0.rootItemID, occurredAt: $0.occurredAt) },
            in: interval
        ).compactMap { summary in
            byID[summary.itemID].map { ($0, summary) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: heading)
                Spacer()
            }

            Picker("History Period", selection: selection) {
                Text("Week").tag(HistoryPeriod.week)
                Text("Month").tag(HistoryPeriod.month)
                Text("Year").tag(HistoryPeriod.year)
            }
            .pickerStyle(.segmented)

            if counts.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "calendar",
                    description: Text("Sessions you log in this calendar \(period.rawValue) will appear here.")
                )
                .frame(minHeight: 190)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(counts, id: \.item.id) { entry in
                        ConsumedItemRow(item: entry.item, count: entry.summary.count)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var heading: LocalizedStringKey {
        switch period {
        case .week: "Consumed This Week"
        case .month: "Consumed This Month"
        case .year: "Consumed This Year"
        }
    }
}

private struct ConsumedItemRow: View {
    let item: LibraryItem
    let count: Int
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.showItem(item.id, from: .home)
        } label: {
            HStack(spacing: 12) {
                CoverArtworkView(item: item)
                    .aspectRatio(item.coverAspectRatio, contentMode: .fit)
                    .frame(width: 48, height: 62)
                    .clipShape(CoverShape(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(WhatFunTheme.ink)
                        .lineLimit(2)
                    Text(item.mediaKind.displayName)
                        .font(.caption)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                }

                Spacer()

                if count > 1 {
                    Text("× \(count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WhatFunTheme.coral)
                        .accessibilityLabel("\(count) sessions")
                } else {
                    Image(systemName: "checkmark")
                        .foregroundStyle(WhatFunTheme.sage)
                        .accessibilityLabel("1 session")
                }
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
