import Foundation
import LockServerContracts

struct AttendanceObservationBuilder {
    struct PreparedLogs {
        fileprivate var rawEventsByDay: [AttendanceDay: [AttendanceDebugEvent]] = [:]
        fileprivate var sessionStartsByDay: [AttendanceDay: [Date]] = [:]
        fileprivate var sessionsByDay: [AttendanceDay: [AttendanceDebugSession]] = [:]
        fileprivate var anomalyReasonsByDay: [AttendanceDay: [String]] = [:]
    }

    private let maximumSessionMinutes = 16 * 60

    func build(for day: AttendanceDay, logs: [EnterModel], workNormMinutes: Int) -> AttendanceObservationBuildOutcome {
        build(for: day, preparedLogs: prepare(logs), workNormMinutes: workNormMinutes)
    }

    func prepare(_ logs: [EnterModel]) -> PreparedLogs {
        parse(logs)
    }

    func build(
        for day: AttendanceDay,
        preparedLogs: PreparedLogs,
        workNormMinutes: Int
    ) -> AttendanceObservationBuildOutcome {
        let rawEvents = preparedLogs.rawEventsByDay[day] ?? []
        let sessionStarts = preparedLogs.sessionStartsByDay[day] ?? []
        let sessions = preparedLogs.sessionsByDay[day] ?? []
        let anomalyReasons = unique(preparedLogs.anomalyReasonsByDay[day] ?? [])

        guard !rawEvents.isEmpty || !sessionStarts.isEmpty || !sessions.isEmpty || !anomalyReasons.isEmpty else {
            return AttendanceObservationBuildOutcome(
                status: .notReady,
                observation: nil,
                details: AttendanceAnalysisDebugDetails(
                    workNormMinutes: workNormMinutes,
                    rawEventCount: 0,
                    rawEvents: [],
                    sessionStartsCount: 0,
                    completedSessionsCount: 0,
                    sessionRanges: [],
                    anomalyReasons: [],
                    note: "no_raw_events_for_day",
                    baselineWindowDays: nil,
                    historyDaysUsed: nil,
                    baselineHistoryDays: nil,
                    deficitHistoryDaysCount: nil,
                    averageStartMinutes: nil,
                    stddevStartMinutes: nil,
                    stddevWorkedMinutes: nil,
                    zS: nil,
                    zT: nil,
                    f: nil,
                    calculationNotes: nil
                )
            )
        }

        let workedMinutes = sessions.reduce(0) { $0 + $1.workedMinutes }
        let breakMinutes = calculateBreakMinutes(for: sessions)
        let firstEntryTime = sessionStarts.first
        let observation = AttendanceObservationDraft(
            userId: UUID(),
            day: day,
            firstEntryTime: firstEntryTime,
            workedMinutes: workedMinutes,
            breakMinutes: breakMinutes,
            sessionsCount: sessionStarts.count,
            isTechnicalAnomaly: !anomalyReasons.isEmpty,
            anomalyReason: anomalyReasons.isEmpty ? nil : anomalyReasons.joined(separator: "; ")
        )

        return AttendanceObservationBuildOutcome(
            status: anomalyReasons.isEmpty ? .observationBuilt : .technicalAnomaly,
            observation: observation,
            details: AttendanceAnalysisDebugDetails(
                workNormMinutes: workNormMinutes,
                rawEventCount: rawEvents.count,
                rawEvents: rawEvents,
                sessionStartsCount: sessionStarts.count,
                completedSessionsCount: sessions.count,
                sessionRanges: sessions,
                anomalyReasons: anomalyReasons,
                note: nil,
                baselineWindowDays: nil,
                historyDaysUsed: nil,
                baselineHistoryDays: nil,
                deficitHistoryDaysCount: nil,
                averageStartMinutes: nil,
                stddevStartMinutes: nil,
                stddevWorkedMinutes: nil,
                zS: nil,
                zT: nil,
                f: nil,
                calculationNotes: nil
            )
        )
    }
}

private extension AttendanceObservationBuilder {
    func parse(_ logs: [EnterModel]) -> PreparedLogs {
        var parsed = PreparedLogs()
        let sortedLogs = logs.sorted { $0.time < $1.time }
        var openStart: Date?

        for log in sortedLogs {
            if log.isOn {
                if let unmatchedStart = openStart {
                    addAnomaly("consecutive_enter_events", for: AttendanceDay(date: unmatchedStart), to: &parsed)
                }

                let eventDay = AttendanceDay(date: log.time)
                parsed.rawEventsByDay[eventDay, default: []].append(AttendanceDebugEvent(type: "enter", time: log.time))
                parsed.sessionStartsByDay[eventDay, default: []].append(log.time)
                openStart = log.time
                continue
            }

            guard let start = openStart else {
                let eventDay = AttendanceDay(date: log.time)
                parsed.rawEventsByDay[eventDay, default: []].append(AttendanceDebugEvent(type: "exit", time: log.time))
                addAnomaly("exit_without_matching_enter", for: eventDay, to: &parsed)
                continue
            }

            let sessionDay = AttendanceDay(date: start)
            parsed.rawEventsByDay[sessionDay, default: []].append(AttendanceDebugEvent(type: "exit", time: log.time))
            let workedMinutes = Int(log.time.timeIntervalSince(start) / 60)

            if workedMinutes < 0 {
                addAnomaly("exit_before_enter", for: sessionDay, to: &parsed)
            } else if workedMinutes > maximumSessionMinutes {
                addAnomaly("session_longer_than_16_hours", for: sessionDay, to: &parsed)
            } else {
                parsed.sessionsByDay[sessionDay, default: []].append(
                    AttendanceDebugSession(start: start, end: log.time, workedMinutes: workedMinutes)
                )
            }

            openStart = nil
        }

        if let openStart {
            addAnomaly("missing_exit", for: AttendanceDay(date: openStart), to: &parsed)
        }

        return parsed
    }

    func addAnomaly(_ reason: String, for day: AttendanceDay, to parsed: inout PreparedLogs) {
        parsed.anomalyReasonsByDay[day, default: []].append(reason)
    }

    func calculateBreakMinutes(for sessions: [AttendanceDebugSession]) -> Int {
        zip(sessions, sessions.dropFirst()).reduce(0) { partialResult, pair in
            partialResult + max(Int(pair.1.start.timeIntervalSince(pair.0.end) / 60), 0)
        }
    }

    func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
