import Foundation
import LockServerContracts

struct PowerSourceAggregate: Codable, Equatable {
    let signalType: String
    let signalPublishedAt: Date?
    let signalSummary: String
}

enum PowerContextAggregator {
    static func makeSourceAggregate(
        arrivalTime: Date,
        maxSignalAgeHours: Int,
        signals: [DTEKPowerCitySignal]
    ) -> PowerSourceAggregate {
        let minPublishedAt = arrivalTime.addingTimeInterval(-Double(maxSignalAgeHours) * 60 * 60)
        let applicableSignals = signals
            .filter { signal in
                signal.publishedAt <= arrivalTime &&
                    (signal.publishedAt >= minPublishedAt || appliesToExplicitTargetDay(signal, arrivalTime: arrivalTime))
            }
            .sorted { $0.publishedAt < $1.publishedAt }
            .compactMap { signal -> (signal: DTEKPowerCitySignal, type: PowerSignalType)? in
                let signalType = classify(signal.text)
                guard signalType.isOutage else {
                    return nil
                }
                guard applies(signal, arrivalTime: arrivalTime) else {
                    return nil
                }
                return (signal, signalType)
            }

        guard let selectedSignal = applicableSignals.last else {
            return PowerSourceAggregate(
                signalType: PowerSignalType.stable.rawValue,
                signalPublishedAt: nil,
                signalSummary: "No official DTEK Kyiv outage directive found for this day and hour."
            )
        }

        return PowerSourceAggregate(
            signalType: selectedSignal.type.rawValue,
            signalPublishedAt: selectedSignal.signal.publishedAt,
            signalSummary: summarize(selectedSignal.signal.text)
        )
    }

    static func makeResolvedValue(sourceAggregate: PowerSourceAggregate) -> PowerContextResolvedValue {
        let signalType = PowerSignalType(rawValue: sourceAggregate.signalType) ?? .stable
        return PowerContextResolvedValue(powerScore: signalType.score)
    }
}

private extension PowerContextAggregator {
    enum PowerSignalType: String, Codable {
        case stable = "stable"
        case scheduledOutage = "scheduled_outage"
        case emergencyOutage = "emergency_outage"

        var score: Double {
            switch self {
            case .stable:
                return 0
            case .scheduledOutage:
                return 7
            case .emergencyOutage:
                return 10
            }
        }

        var isOutage: Bool {
            self != .stable
        }
    }

    static func classify(_ text: String) -> PowerSignalType {
        let normalized = text.lowercased()

        if normalized.contains("екстрен") {
            return .emergencyOutage
        }
        if normalized.contains("графіки відключень") || normalized.contains("графіки включень") || normalized.contains("застосовуються графіки") {
            return .scheduledOutage
        }
        return .stable
    }

    static func summarize(_ text: String) -> String {
        guard text.count > 220 else {
            return text
        }
        return String(text.prefix(220)) + "..."
    }

    static func applies(_ signal: DTEKPowerCitySignal, arrivalTime: Date) -> Bool {
        if let targetDay = explicitTargetDay(for: signal) {
            return utcCalendar.isDate(arrivalTime, inSameDayAs: targetDay)
        }
        return utcCalendar.isDate(arrivalTime, inSameDayAs: signal.publishedAt)
    }

    static func appliesToExplicitTargetDay(_ signal: DTEKPowerCitySignal, arrivalTime: Date) -> Bool {
        guard let targetDay = explicitTargetDay(for: signal) else {
            return false
        }
        return utcCalendar.isDate(arrivalTime, inSameDayAs: targetDay)
    }

    static func explicitTargetDay(for signal: DTEKPowerCitySignal) -> Date? {
        let nsRange = NSRange(signal.text.startIndex..<signal.text.endIndex, in: signal.text)
        guard let match = targetDayRegex.firstMatch(in: signal.text, options: [], range: nsRange),
              let dayRange = Range(match.range(at: 1), in: signal.text),
              let monthRange = Range(match.range(at: 2), in: signal.text),
              let day = Int(signal.text[dayRange]),
              let month = monthNumber(for: String(signal.text[monthRange]))
        else {
            return nil
        }

        let publishedComponents = utcCalendar.dateComponents([.year], from: signal.publishedAt)
        var targetComponents = DateComponents()
        targetComponents.calendar = utcCalendar
        targetComponents.timeZone = utcTimeZone
        targetComponents.year = publishedComponents.year
        targetComponents.month = month
        targetComponents.day = day
        targetComponents.hour = 0
        targetComponents.minute = 0
        targetComponents.second = 0

        return utcCalendar.date(from: targetComponents)
    }

    static func monthNumber(for month: String) -> Int? {
        ukrainianMonths[month.lowercased()]
    }

    static let targetDayRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})\s+(січня|лютого|березня|квітня|травня|червня|липня|серпня|вересня|жовтня|листопада|грудня)\b"#,
        options: []
    )

    static let ukrainianMonths: [String: Int] = [
        "січня": 1,
        "лютого": 2,
        "березня": 3,
        "квітня": 4,
        "травня": 5,
        "червня": 6,
        "липня": 7,
        "серпня": 8,
        "вересня": 9,
        "жовтня": 10,
        "листопада": 11,
        "грудня": 12
    ]

    static let utcTimeZone = TimeZone(secondsFromGMT: 0) ?? .current

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }()
}
