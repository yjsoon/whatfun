import Foundation

enum HistoryPeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case week
    case month
    case year

    var id: Self { self }

    var calendarComponent: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: calendarComponent, for: date) {
            return interval
        }

        let start = calendar.startOfDay(for: date)
        let fallbackEnd = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return DateInterval(start: start, end: fallbackEnd)
    }

    func contains(_ candidate: Date, relativeTo date: Date, calendar: Calendar) -> Bool {
        interval(containing: date, calendar: calendar).contains(candidate)
    }
}

struct SessionOccurrence: Sendable, Equatable {
    let itemID: UUID
    let occurredAt: Date
}

struct SessionCount: Sendable, Equatable, Identifiable {
    var id: UUID { itemID }

    let itemID: UUID
    let count: Int
    let firstOccurredAt: Date
    let lastOccurredAt: Date
}

enum SessionAggregator {
    static func counts(
        for occurrences: some Sequence<SessionOccurrence>,
        in interval: DateInterval
    ) -> [SessionCount] {
        var buckets: [UUID: [Date]] = [:]

        for occurrence in occurrences where interval.contains(occurrence.occurredAt) {
            buckets[occurrence.itemID, default: []].append(occurrence.occurredAt)
        }

        return buckets.compactMap { itemID, dates in
            guard let first = dates.min(), let last = dates.max() else { return nil }
            return SessionCount(
                itemID: itemID,
                count: dates.count,
                firstOccurredAt: first,
                lastOccurredAt: last
            )
        }
        .sorted {
            if $0.lastOccurredAt == $1.lastOccurredAt {
                return $0.itemID.uuidString < $1.itemID.uuidString
            }
            return $0.lastOccurredAt > $1.lastOccurredAt
        }
    }
}

