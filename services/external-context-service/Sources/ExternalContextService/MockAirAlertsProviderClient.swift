import Foundation
import LockServerContracts

struct MockAirAlertsRawPayload: Codable, Equatable {
    let day: String
    let city: String
    let generatedAt: Date
    let intervals: [AirAlertInterval]
}

struct MockAirAlertsProviderFetchOutput: Equatable {
    let rawPayload: MockAirAlertsRawPayload
    let sourceURL: String
}

struct MockAirAlertsProviderClient {
    private let configuration: MockAirAlertsConfiguration

    init(configuration: MockAirAlertsConfiguration) {
        self.configuration = configuration
    }

    func fetchAirAlerts(for day: ExternalContextDay) async throws -> MockAirAlertsProviderFetchOutput {
        let intervals = generateIntervals(for: day)
        let generatedAt = intervals.last?.endedAt ?? day.startOfDay

        return MockAirAlertsProviderFetchOutput(
            rawPayload: MockAirAlertsRawPayload(
                day: day.stringValue,
                city: configuration.city,
                generatedAt: generatedAt,
                intervals: intervals
            ),
            sourceURL: configuration.sourceURL
        )
    }
}

private extension MockAirAlertsProviderClient {
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    func generateIntervals(for day: ExternalContextDay) -> [AirAlertInterval] {
        var generator = SeededGenerator(seed: seed(for: day))
        let dayMinutes = 24 * 60
        let intervalCount = Int.random(
            in: configuration.minimumIntervalsPerDay...configuration.maximumIntervalsPerDay,
            using: &generator
        )

        var nextStartMinute = Int.random(in: 0...150, using: &generator)
        var intervals: [AirAlertInterval] = []

        for _ in 0..<intervalCount {
            let remainingMinutes = dayMinutes - nextStartMinute
            guard remainingMinutes >= configuration.minimumDurationMinutes else {
                break
            }

            let maximumDuration = min(configuration.maximumDurationMinutes, remainingMinutes)
            let duration = Int.random(
                in: configuration.minimumDurationMinutes...maximumDuration,
                using: &generator
            )

            let startedAt = day.startOfDay.addingTimeInterval(TimeInterval(nextStartMinute * 60))
            let endedAt = startedAt.addingTimeInterval(TimeInterval(duration * 60))
            intervals.append(AirAlertInterval(startedAt: startedAt, endedAt: endedAt))

            let gap = Int.random(
                in: configuration.minimumGapMinutes...configuration.maximumGapMinutes,
                using: &generator
            )
            nextStartMinute += duration + gap
        }

        if intervals.isEmpty {
            let startedAt = day.startOfDay.addingTimeInterval(8 * 60 * 60)
            let endedAt = startedAt.addingTimeInterval(TimeInterval(configuration.minimumDurationMinutes * 60))
            return [AirAlertInterval(startedAt: startedAt, endedAt: endedAt)]
        }

        return intervals
    }

    func seed(for day: ExternalContextDay) -> UInt64 {
        let input = "\(configuration.city)|\(day.stringValue)"
        return input.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
