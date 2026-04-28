import Foundation
import LockServerContracts

enum AttendanceAirAlertImpactCalculator {
    private static let preArrivalWindowSeconds: TimeInterval = 60 * 60

    static func totalMinutes(
        arrivalTime: Date?,
        sessionRanges: [AttendanceDebugSession],
        intervals: [AirAlertInterval]?
    ) -> Int? {
        breakdown(arrivalTime: arrivalTime, sessionRanges: sessionRanges, intervals: intervals)?.totalMinutes
    }

    static func breakdown(
        arrivalTime: Date?,
        sessionRanges: [AttendanceDebugSession],
        intervals: [AirAlertInterval]?
    ) -> Breakdown? {
        guard let arrivalTime, let intervals else {
            return nil
        }

        let preArrivalInterval = DateInterval(
            start: arrivalTime.addingTimeInterval(-preArrivalWindowSeconds),
            end: arrivalTime
        )
        let preArrivalMinutes = overlapMinutes(intervals: intervals, with: [preArrivalInterval])
        let gapMinutes = overlapMinutes(intervals: intervals, with: gapIntervals(from: sessionRanges))

        return Breakdown(
            preArrivalMinutes: preArrivalMinutes,
            gapMinutes: gapMinutes,
            totalMinutes: preArrivalMinutes + gapMinutes
        )
    }
}

extension AttendanceAirAlertImpactCalculator {
    struct Breakdown: Equatable {
        let preArrivalMinutes: Int
        let gapMinutes: Int
        let totalMinutes: Int
    }
}

private extension AttendanceAirAlertImpactCalculator {
    static func gapIntervals(from sessionRanges: [AttendanceDebugSession]) -> [DateInterval] {
        let sortedSessions = sessionRanges.sorted { $0.start < $1.start }
        guard sortedSessions.count >= 2 else {
            return []
        }

        return zip(sortedSessions, sortedSessions.dropFirst()).compactMap { current, next in
            guard next.start > current.end else {
                return nil
            }
            return DateInterval(start: current.end, end: next.start)
        }
    }

    static func overlapMinutes(intervals: [AirAlertInterval], with windows: [DateInterval]) -> Int {
        guard intervals.isEmpty == false, windows.isEmpty == false else {
            return 0
        }

        let totalSeconds = windows.reduce(0.0) { partialResult, window in
            partialResult + intervals.reduce(0.0) { seconds, interval in
                seconds + overlapSeconds(
                    lhs: DateInterval(start: interval.startedAt, end: interval.endedAt),
                    rhs: window
                )
            }
        }

        return Int(totalSeconds / 60.0)
    }

    static func overlapSeconds(lhs: DateInterval, rhs: DateInterval) -> TimeInterval {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard end > start else {
            return 0
        }
        return end.timeIntervalSince(start)
    }
}
