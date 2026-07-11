import Foundation
import UserNotifications

enum ReminderAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

struct ReminderRequest: Sendable, Equatable {
    let identifier: String
    let title: String
    let body: String
    let fireAt: Date
    let timeZoneIdentifier: String
}

protocol ReminderScheduling: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func schedule(_ request: ReminderRequest) async throws
    func cancel(identifier: String) async
}

actor LocalReminderScheduler: ReminderScheduling {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .autoupdatingCurrent) {
        self.center = center
        self.calendar = calendar
    }

    func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func schedule(_ request: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .autoupdatingCurrent
        let components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: request.fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let notification = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(notification)
    }

    func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

actor InMemoryReminderScheduler: ReminderScheduling {
    var authorizationState = ReminderAuthorization.authorized
    private(set) var requests: [String: ReminderRequest] = [:]

    func authorization() -> ReminderAuthorization {
        authorizationState
    }

    func requestAuthorization() -> Bool {
        authorizationState = .authorized
        return true
    }

    func schedule(_ request: ReminderRequest) {
        requests[request.identifier] = request
    }

    func cancel(identifier: String) {
        requests[identifier] = nil
    }

    func request(identifier: String) -> ReminderRequest? {
        requests[identifier]
    }
}

