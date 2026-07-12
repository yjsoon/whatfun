import Foundation

nonisolated struct HomeRailPartition<Item> {
    let active: [Item]
    let planned: [Item]
    let overdue: [Item]
}

nonisolated enum HomeRails {
    struct Snapshot: Sendable, Equatable {
        var status: ConsumptionStatus
        var isFollowedPodcast: Bool
        var earliestPendingReminderFireDate: Date?

        init(
            status: ConsumptionStatus,
            isFollowedPodcast: Bool = false,
            earliestPendingReminderFireDate: Date? = nil
        ) {
            self.status = status
            self.isFollowedPodcast = isFollowedPodcast
            self.earliestPendingReminderFireDate = earliestPendingReminderFireDate
        }
    }

    static func partition<Item>(
        _ items: some Sequence<Item>,
        now: Date,
        snapshot: (Item) -> Snapshot
    ) -> HomeRailPartition<Item> {
        var active: [Item] = []
        var planned: [Item] = []
        var overdue: [Item] = []

        for item in items {
            let details = snapshot(item)
            let isActive = details.status == .inProgress || details.status == .paused ||
                details.isFollowedPodcast

            if isActive {
                active.append(item)
            } else if details.status == .planned {
                planned.append(item)
            }

            if details.status == .planned,
               let fireAt = details.earliestPendingReminderFireDate, fireAt < now {
                overdue.append(item)
            }
        }

        return HomeRailPartition(active: active, planned: planned, overdue: overdue)
    }
}
