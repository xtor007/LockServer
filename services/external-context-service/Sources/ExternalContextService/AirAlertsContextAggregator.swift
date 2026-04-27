import Foundation
import LockServerContracts

struct AirAlertsSourceAggregate: Codable, Equatable {
    let intervals: [AirAlertInterval]
}

enum AirAlertsContextAggregator {
    static func makeSourceAggregate(day: ExternalContextDay, rawPayload: AirAlertsRawPayload) -> AirAlertsSourceAggregate {
        AirAlertsSourceAggregate(intervals: normalize(makeIntervals(day: day, alerts: rawPayload.alerts)))
    }

    static func makeResolvedValue(sourceAggregate: AirAlertsSourceAggregate) -> AirAlertsContextResolvedValue {
        AirAlertsContextResolvedValue(intervals: normalize(sourceAggregate.intervals))
    }
}

private extension AirAlertsContextAggregator {
    static func makeIntervals(day: ExternalContextDay, alerts: [AirAlertsRawAlert]) -> [AirAlertInterval] {
        let dayEnd = day.startOfDay.addingTimeInterval(24 * 60 * 60)
        let openIntervalEnd = day == ExternalContextDay(date: Date()) ? min(Date(), dayEnd) : dayEnd

        return alerts.compactMap { alert in
            guard alert.alertType == "air_raid" else {
                return nil
            }

            let startedAt = max(alert.startedAt, day.startOfDay)
            let endedAt = min(alert.finishedAt ?? openIntervalEnd, dayEnd)
            guard endedAt > startedAt else {
                return nil
            }

            return AirAlertInterval(startedAt: startedAt, endedAt: endedAt)
        }
    }

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
