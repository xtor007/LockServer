import Foundation
import LockServerCore

enum PowerContextFallback {
    static func makeSignal(for arrivalTime: Date) -> DTEKPowerCitySignal {
        let scenario = scenario(for: arrivalTime)
        return DTEKPowerCitySignal(
            publishedAt: publishedAt(for: arrivalTime),
            text: scenario.summary
        )
    }

    static func makeSourceAggregate(for arrivalTime: Date) -> PowerSourceAggregate {
        let scenario = scenario(for: arrivalTime)
        return PowerSourceAggregate(
            signalType: scenario.signalType,
            signalPublishedAt: scenario.isStable ? nil : publishedAt(for: arrivalTime),
            signalSummary: scenario.summary
        )
    }
}

private extension PowerContextFallback {
    struct Scenario {
        let signalType: String
        let summary: String

        var isStable: Bool {
            signalType == "stable"
        }
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static func scenario(for arrivalTime: Date) -> Scenario {
        var generator = DeterministicSeededGenerator(seed: DeterministicSeededGenerator.stableSeed(for: "power|\(hourKey(for: arrivalTime))"))
        let month = utcCalendar.component(.month, from: arrivalTime)
        let hour = utcCalendar.component(.hour, from: arrivalTime)
        let isWinterLoad = [11, 12, 1, 2, 3].contains(month)
        let isPeakHour = (7...10).contains(hour) || (17...21).contains(hour)
        let roll = Int.random(in: 0..<100, using: &generator)

        let emergencyThreshold = isWinterLoad ? (isPeakHour ? 7 : 4) : (isPeakHour ? 3 : 1)
        let scheduledThreshold = emergencyThreshold + (isWinterLoad ? (isPeakHour ? 24 : 12) : (isPeakHour ? 11 : 5))

        if roll < emergencyThreshold {
            return Scenario(
                signalType: "emergency_outage",
                summary: "Deterministic fallback: emergency outage signal for Kyiv during the analyzed arrival window."
            )
        }

        if roll < scheduledThreshold {
            return Scenario(
                signalType: "scheduled_outage",
                summary: "Deterministic fallback: scheduled outage window for Kyiv during the analyzed arrival window."
            )
        }

        return Scenario(
            signalType: "stable",
            summary: "Deterministic fallback: no outage signal for Kyiv during the analyzed arrival window."
        )
    }

    static func publishedAt(for arrivalTime: Date) -> Date {
        arrivalTime.addingTimeInterval(-45 * 60)
    }

    static func hourKey(for arrivalTime: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour], from: arrivalTime)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(components.hour ?? 0)"
    }
}
