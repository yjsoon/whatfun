import Foundation

nonisolated enum ArchiveDateCodec {
    static func string(from date: Date) -> String {
        var wholeSeconds = floor(date.timeIntervalSince1970)
        var nanoseconds = Int(((date.timeIntervalSince1970 - wholeSeconds) * 1_000_000_000).rounded())
        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let base = formatter.string(from: Date(timeIntervalSince1970: wholeSeconds))
        return "\(base).\(String(format: "%09d", nanoseconds))Z"
    }

    static func date(from value: String) -> Date? {
        if value.hasSuffix("Z"),
           let decimalPoint = value.lastIndex(of: ".")
        {
            let base = String(value[..<decimalPoint])
            let fractionStart = value.index(after: decimalPoint)
            let fractionEnd = value.index(before: value.endIndex)
            let fraction = String(value[fractionStart ..< fractionEnd])
            if base.count == 19,
               (1 ... 9).contains(fraction.count),
               fraction.allSatisfy(\.isNumber),
               let baseDate = baseDate(from: base),
               let digits = Int(fraction)
            {
                let divisor = pow(10, Double(fraction.count))
                return Date(timeIntervalSince1970: baseDate.timeIntervalSince1970 + Double(digits) / divisor)
            }
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func baseDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
}
