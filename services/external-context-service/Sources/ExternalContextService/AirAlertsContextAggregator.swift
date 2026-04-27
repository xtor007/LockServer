import Foundation
import LockServerContracts

struct AirAlertsSourceAggregate: Codable, Equatable {
    let intervals: [AirAlertInterval]
}

enum AirAlertsContextAggregator {
    static func makeSourceAggregate(rawPayload: MockAirAlertsRawPayload) -> AirAlertsSourceAggregate {
        AirAlertsSourceAggregate(intervals: normalize(rawPayload.intervals))
    }

    static func makeResolvedValue(sourceAggregate: AirAlertsSourceAggregate) -> AirAlertsContextResolvedValue {
        AirAlertsContextResolvedValue(intervals: normalize(sourceAggregate.intervals))
    }
}

private extension AirAlertsContextAggregator {
    static func normalize(_ intervals: [AirAlertInterval]) -> [AirAlertInterval] {
        intervals
            .filter { $0.endedAt > $0.startedAt }
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.endedAt < rhs.endedAt
                }
                return lhs.startedAt < rhs.startedAt
            }
    }
}
