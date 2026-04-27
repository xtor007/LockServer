import Foundation
import Vapor

struct ExternalContextDay: Hashable, Comparable, Sendable {
    let startOfDay: Date

    init(_ value: String) throws {
        guard let date = Self.formatter.date(from: value) else {
            throw Abort(.badRequest, reason: "Day must use yyyy-MM-dd format in UTC")
        }
        self.startOfDay = date
    }

    init(date: Date) {
        self.startOfDay = Self.calendar.startOfDay(for: date)
    }

    var stringValue: String {
        Self.formatter.string(from: startOfDay)
    }

    static func < (lhs: ExternalContextDay, rhs: ExternalContextDay) -> Bool {
        lhs.startOfDay < rhs.startOfDay
    }
}

private extension ExternalContextDay {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")!
        return calendar
    }()

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
