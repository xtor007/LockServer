import Fluent
import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceFixtureMaterializationSummary {
    let regularUserCount: Int
    let fixtureDayCount: Int
    let observationCount: Int
    let resultCount: Int
    let signalReadyCount: Int
    let clusteredCount: Int
    let technicalOutlierCount: Int
    let clusteringModelVersion: Int?
    let contextDayCount: Int
}

struct AttendanceFixtureMaterializer {
    private let externalContextClient: AttendanceExternalContextServiceClient
    private let clusteringService: AttendanceClusteringService
    private let builder = AttendanceObservationBuilder()
    private let signalCalculator: AttendanceCoreSignalCalculator
    private let baselineWindowDays: Int
    private let encoder: JSONEncoder

    init(
        externalContextClient: AttendanceExternalContextServiceClient,
        baselineWindowDays: Int,
        clusteringService: AttendanceClusteringService
    ) {
        self.externalContextClient = externalContextClient
        self.clusteringService = clusteringService
        self.baselineWindowDays = max(baselineWindowDays, 1)
        self.signalCalculator = AttendanceCoreSignalCalculator(baselineWindowDays: self.baselineWindowDays)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func materialize(on database: Database) async throws -> AttendanceFixtureMaterializationSummary {
        let users = SeedUsers.regularUsers.sorted { $0.id.uuidString < $1.id.uuidString }
        let days = try SeedUsers.attendanceFixtureDays.map(AttendanceDay.init)
        let preparedLogsByUser = makePreparedLogsByUser()
        let emptyPreparedLogs = builder.prepare([])
        let dayArrivalHours = collectArrivalHours(users: users, days: days, preparedLogsByUser: preparedLogsByUser)
        let dayContexts = try await loadExternalContexts(for: dayArrivalHours)

        try await AttendanceAnalysisResult.query(on: database).delete()
        try await AttendanceDayObservation.query(on: database).delete()

        var observationBatch = [AttendanceDayObservation]()
        var resultBatch = [AttendanceAnalysisResult]()
        var observationCount = 0
        var resultCount = 0
        var signalReadyCount = 0

        for user in users {
            let preparedLogs = preparedLogsByUser[user.id] ?? emptyPreparedLogs
            var history = [AttendanceCoreSignalCalculator.ObservationInput]()

            for day in days {
                let outcome = builder.build(for: day, preparedLogs: preparedLogs, workNormMinutes: user.workNormMinutes)
                let observation = makeObservation(from: outcome.observation, userId: user.id, day: day)
                let context = externalContext(for: day, arrivalTime: observation?.firstEntryTime, in: dayContexts)
                let result = try makeResult(
                    for: user,
                    day: day,
                    outcome: outcome,
                    observation: observation,
                    history: history,
                    context: context
                )

                if let observation {
                    observationBatch.append(observation)
                    observationCount += 1
                }

                resultBatch.append(result)
                resultCount += 1
                if result.status == AttendanceAnalysisStatus.signalsReady.rawValue {
                    signalReadyCount += 1
                }

                if let observation,
                   observation.isTechnicalAnomaly == false,
                   let firstEntryTime = observation.firstEntryTime {
                    history.append(
                        AttendanceCoreSignalCalculator.ObservationInput(
                            day: day,
                            firstEntryTime: firstEntryTime,
                            workedMinutes: observation.workedMinutes
                        )
                    )
                }

                if observationBatch.count >= 1_000 {
                    try await observationBatch.create(on: database)
                    observationBatch.removeAll(keepingCapacity: true)
                }

                if resultBatch.count >= 1_000 {
                    try await resultBatch.create(on: database)
                    resultBatch.removeAll(keepingCapacity: true)
                }
            }
        }

        if observationBatch.isEmpty == false {
            try await observationBatch.create(on: database)
        }

        if resultBatch.isEmpty == false {
            try await resultBatch.create(on: database)
        }

        let clusteringSummary = try await clusteringService.execute(scope: .allEligible, rebuildModel: true, on: database)

        return AttendanceFixtureMaterializationSummary(
            regularUserCount: users.count,
            fixtureDayCount: days.count,
            observationCount: observationCount,
            resultCount: resultCount,
            signalReadyCount: signalReadyCount,
            clusteredCount: clusteringSummary.clusteredCount,
            technicalOutlierCount: clusteringSummary.technicalOutlierCount,
            clusteringModelVersion: clusteringSummary.modelVersion,
            contextDayCount: dayContexts.count
        )
    }
}

private extension AttendanceFixtureMaterializer {
    struct ExternalContextSnapshot {
        let airAlertIntervals: [AirAlertInterval]?
        let trafficScore: Double?
        let powerScore: Double?
        let weatherScore: Double?
        let weatherContext: WeatherContextResolvedValue?
        let notes: [String]?
    }

    func makePreparedLogsByUser() -> [UUID: AttendanceObservationBuilder.PreparedLogs] {
        Dictionary(grouping: SeedUsers.accessEntries, by: \.employerID).mapValues { entries in
            let logs = entries
                .sorted { $0.time < $1.time }
                .map { EnterModel(isOn: $0.isOn, time: $0.time) }
            return builder.prepare(logs)
        }
    }

    func collectArrivalHours(
        users: [SeedUser],
        days: [AttendanceDay],
        preparedLogsByUser: [UUID: AttendanceObservationBuilder.PreparedLogs]
    ) -> [AttendanceDay: Set<Int>] {
        var result = [AttendanceDay: Set<Int>]()
        let emptyPreparedLogs = builder.prepare([])

        for user in users {
            let preparedLogs = preparedLogsByUser[user.id] ?? emptyPreparedLogs
            for day in days {
                let outcome = builder.build(for: day, preparedLogs: preparedLogs, workNormMinutes: user.workNormMinutes)
                guard let firstEntryTime = outcome.observation?.firstEntryTime else {
                    continue
                }
                result[day, default: []].insert(arrivalHour(for: firstEntryTime))
            }
        }

        return result
    }

    func loadExternalContexts(for dayArrivalHours: [AttendanceDay: Set<Int>]) async throws -> [AttendanceDay: ExternalContextDayResponse] {
        var responses = [AttendanceDay: ExternalContextDayResponse]()

        for day in dayArrivalHours.keys.sorted() {
            guard let hours = dayArrivalHours[day]?.sorted(), hours.isEmpty == false else {
                continue
            }

            var lastResponse: ExternalContextDayResponse?
            for hour in hours {
                let arrivalTime = day.startOfDay.addingTimeInterval(TimeInterval(hour * 60 * 60))
                lastResponse = try await externalContextClient.dayContext(day: day.stringValue, arrivalTime: arrivalTime)
            }

            if let lastResponse {
                responses[day] = lastResponse
            }
        }

        return responses
    }

    func makeObservation(from draft: AttendanceObservationDraft?, userId: UUID, day: AttendanceDay) -> AttendanceDayObservation? {
        guard let draft else {
            return nil
        }

        return AttendanceDayObservation(
            userId: userId,
            day: day.startOfDay,
            firstEntryTime: draft.firstEntryTime,
            workedMinutes: draft.workedMinutes,
            breakMinutes: draft.breakMinutes,
            sessionsCount: draft.sessionsCount,
            isTechnicalAnomaly: draft.isTechnicalAnomaly,
            anomalyReason: draft.anomalyReason
        )
    }

    func makeResult(
        for user: SeedUser,
        day: AttendanceDay,
        outcome: AttendanceObservationBuildOutcome,
        observation: AttendanceDayObservation?,
        history: [AttendanceCoreSignalCalculator.ObservationInput],
        context: ExternalContextSnapshot
    ) throws -> AttendanceAnalysisResult {
        let draft = makeResultDraft(
            workNormMinutes: user.workNormMinutes,
            day: day,
            outcome: outcome,
            observation: observation,
            history: history,
            context: context
        )

        return AttendanceAnalysisResult(
            userId: user.id,
            day: day.startOfDay,
            status: draft.status.rawValue,
            observationId: observation?.id,
            historyDaysUsed: draft.historyDaysUsed,
            averageStartMinutes: draft.averageStartMinutes,
            stddevStartMinutes: draft.stddevStartMinutes,
            stddevWorkedMinutes: draft.stddevWorkedMinutes,
            workNormMinutes: draft.workNormMinutes,
            zS: draft.zS,
            zT: draft.zT,
            f: draft.f,
            clusterName: draft.clusterName,
            clusterScore: draft.clusterScore,
            clusterWeight: draft.clusterWeight,
            clusterModelVersion: draft.clusterModelVersion,
            clusterDistance: draft.clusterDistance,
            clusteringStatus: draft.clusteringStatus.rawValue,
            detailsJson: try encode(draft.details)
        )
    }

    func makeResultDraft(
        workNormMinutes: Int,
        day: AttendanceDay,
        outcome: AttendanceObservationBuildOutcome,
        observation: AttendanceDayObservation?,
        history: [AttendanceCoreSignalCalculator.ObservationInput],
        context: ExternalContextSnapshot
    ) -> AttendanceAnalysisResultDraft {
        switch outcome.status {
        case .notReady:
            return AttendanceAnalysisResultDraft(
                status: .notReady,
                observationId: nil,
                historyDaysUsed: 0,
                averageStartMinutes: nil,
                stddevStartMinutes: nil,
                stddevWorkedMinutes: nil,
                workNormMinutes: workNormMinutes,
                zS: nil,
                zT: nil,
                f: nil,
                clusterName: nil,
                clusterScore: nil,
                clusterWeight: nil,
                clusterModelVersion: nil,
                clusterDistance: nil,
                clusteringStatus: .notApplicable,
                details: makeDebugDetails(
                    from: outcome.details,
                    snapshot: AttendanceCoreSignalCalculator.Snapshot(
                        historyDaysUsed: 0,
                        averageStartMinutes: nil,
                        stddevStartMinutes: nil,
                        stddevWorkedMinutes: nil,
                        workNormMinutes: workNormMinutes,
                        zS: nil,
                        zT: nil,
                        f: nil
                    ),
                    debug: AttendanceCoreSignalCalculator.Debug(
                        baselineWindowDays: baselineWindowDays,
                        historyDays: [],
                        deficitHistoryDaysCount: 0,
                        calculationNotes: []
                    ),
                    context: ExternalContextSnapshot(
                        airAlertIntervals: nil,
                        trafficScore: nil,
                        powerScore: nil,
                        weatherScore: nil,
                        weatherContext: nil,
                        notes: nil
                    )
                )
            )

        case .technicalAnomaly:
            return AttendanceAnalysisResultDraft(
                status: .technicalAnomaly,
                observationId: observation?.id,
                historyDaysUsed: 0,
                averageStartMinutes: nil,
                stddevStartMinutes: nil,
                stddevWorkedMinutes: nil,
                workNormMinutes: workNormMinutes,
                zS: nil,
                zT: nil,
                f: nil,
                clusterName: nil,
                clusterScore: nil,
                clusterWeight: nil,
                clusterModelVersion: nil,
                clusterDistance: nil,
                clusteringStatus: .notApplicable,
                details: makeDebugDetails(
                    from: outcome.details,
                    snapshot: AttendanceCoreSignalCalculator.Snapshot(
                        historyDaysUsed: 0,
                        averageStartMinutes: nil,
                        stddevStartMinutes: nil,
                        stddevWorkedMinutes: nil,
                        workNormMinutes: workNormMinutes,
                        zS: nil,
                        zT: nil,
                        f: nil
                    ),
                    debug: AttendanceCoreSignalCalculator.Debug(
                        baselineWindowDays: baselineWindowDays,
                        historyDays: [],
                        deficitHistoryDaysCount: 0,
                        calculationNotes: ["target_day_technical_anomaly"]
                    ),
                    context: ExternalContextSnapshot(
                        airAlertIntervals: nil,
                        trafficScore: nil,
                        powerScore: nil,
                        weatherScore: nil,
                        weatherContext: nil,
                        notes: nil
                    )
                )
            )

        case .observationBuilt, .signalsReady, .insufficientHistory, .clusteringTerminalStableNormal, .clusteringTechnicalOutlier, .readyForNextStage:
            guard let observation, let firstEntryTime = observation.firstEntryTime else {
                return AttendanceAnalysisResultDraft(
                    status: .notReady,
                    observationId: observation?.id,
                    historyDaysUsed: 0,
                    averageStartMinutes: nil,
                    stddevStartMinutes: nil,
                    stddevWorkedMinutes: nil,
                    workNormMinutes: workNormMinutes,
                    zS: nil,
                    zT: nil,
                    f: nil,
                    clusterName: nil,
                    clusterScore: nil,
                    clusterWeight: nil,
                    clusterModelVersion: nil,
                    clusterDistance: nil,
                    clusteringStatus: .notApplicable,
                    details: makeDebugDetails(
                        from: outcome.details,
                        snapshot: AttendanceCoreSignalCalculator.Snapshot(
                            historyDaysUsed: 0,
                            averageStartMinutes: nil,
                            stddevStartMinutes: nil,
                            stddevWorkedMinutes: nil,
                            workNormMinutes: workNormMinutes,
                            zS: nil,
                            zT: nil,
                            f: nil
                        ),
                        debug: AttendanceCoreSignalCalculator.Debug(
                            baselineWindowDays: baselineWindowDays,
                            historyDays: [],
                            deficitHistoryDaysCount: 0,
                            calculationNotes: ["missing_first_entry_time_for_signal_stage"]
                        ),
                        context: ExternalContextSnapshot(
                            airAlertIntervals: nil,
                            trafficScore: nil,
                            powerScore: nil,
                            weatherScore: nil,
                            weatherContext: nil,
                            notes: nil
                        )
                    )
                )
            }

            let calculation = signalCalculator.calculate(
                target: AttendanceCoreSignalCalculator.ObservationInput(
                    day: day,
                    firstEntryTime: firstEntryTime,
                    workedMinutes: observation.workedMinutes
                ),
                history: history,
                workNormMinutes: workNormMinutes
            )

            return AttendanceAnalysisResultDraft(
                status: calculation.status,
                observationId: observation.id,
                historyDaysUsed: calculation.snapshot.historyDaysUsed,
                averageStartMinutes: calculation.snapshot.averageStartMinutes,
                stddevStartMinutes: calculation.snapshot.stddevStartMinutes,
                stddevWorkedMinutes: calculation.snapshot.stddevWorkedMinutes,
                workNormMinutes: calculation.snapshot.workNormMinutes,
                zS: calculation.snapshot.zS,
                zT: calculation.snapshot.zT,
                f: calculation.snapshot.f,
                clusterName: nil,
                clusterScore: nil,
                clusterWeight: nil,
                clusterModelVersion: nil,
                clusterDistance: nil,
                clusteringStatus: calculation.status == .signalsReady ? .notStarted : .notApplicable,
                details: makeDebugDetails(
                    from: outcome.details,
                    snapshot: calculation.snapshot,
                    debug: calculation.debug,
                    context: context
                )
            )
        }
    }

    func makeDebugDetails(
        from source: AttendanceAnalysisDebugDetails,
        snapshot: AttendanceCoreSignalCalculator.Snapshot,
        debug: AttendanceCoreSignalCalculator.Debug,
        context: ExternalContextSnapshot
    ) -> AttendanceAnalysisDebugDetails {
        AttendanceAnalysisDebugDetails(
            workNormMinutes: snapshot.workNormMinutes,
            rawEventCount: source.rawEventCount,
            rawEvents: source.rawEvents,
            sessionStartsCount: source.sessionStartsCount,
            completedSessionsCount: source.completedSessionsCount,
            sessionRanges: source.sessionRanges,
            anomalyReasons: source.anomalyReasons,
            note: source.note,
            baselineWindowDays: debug.baselineWindowDays,
            historyDaysUsed: snapshot.historyDaysUsed,
            baselineHistoryDays: debug.historyDays,
            deficitHistoryDaysCount: debug.deficitHistoryDaysCount,
            averageStartMinutes: snapshot.averageStartMinutes,
            stddevStartMinutes: snapshot.stddevStartMinutes,
            stddevWorkedMinutes: snapshot.stddevWorkedMinutes,
            zS: snapshot.zS,
            zT: snapshot.zT,
            f: snapshot.f,
            calculationNotes: debug.calculationNotes.isEmpty ? nil : debug.calculationNotes,
            airAlertIntervals: context.airAlertIntervals,
            trafficScore: context.trafficScore,
            powerScore: context.powerScore,
            weatherScore: context.weatherScore,
            weatherContext: context.weatherContext,
            externalContextNotes: context.notes
        )
    }

    func externalContext(
        for day: AttendanceDay,
        arrivalTime: Date?,
        in responses: [AttendanceDay: ExternalContextDayResponse]
    ) -> ExternalContextSnapshot {
        guard let arrivalTime,
              let response = responses[day]
        else {
            return ExternalContextSnapshot(
                airAlertIntervals: nil,
                trafficScore: nil,
                powerScore: nil,
                weatherScore: nil,
                weatherContext: nil,
                notes: nil
            )
        }

        let targetHour = arrivalHour(for: arrivalTime)
        let airAlertIntervals = response.contexts.first(where: { $0.factor == ExternalContextFactor.airAlerts.rawValue })?.intervals
        let trafficScore = response.contexts
            .first(where: { $0.factor == ExternalContextFactor.traffic.rawValue })?
            .values?
            .first(where: { $0.arrivalHour == targetHour })?
            .score
        let powerScore = response.contexts
            .first(where: { $0.factor == ExternalContextFactor.powerAvailability.rawValue })?
            .values?
            .first(where: { $0.arrivalHour == targetHour })?
            .score
        let weatherContext = response.contexts
            .first(where: { $0.factor == ExternalContextFactor.weather.rawValue })?
            .values?
            .first(where: { $0.arrivalHour == targetHour })?
            .weather
        let notes = [
            airAlertIntervals == nil ? "air_alerts_context_unavailable" : nil,
            trafficScore == nil ? "traffic_context_unavailable" : nil,
            powerScore == nil ? "power_context_unavailable" : nil,
            weatherContext == nil ? "weather_context_unavailable" : nil
        ].compactMap { $0 }

        return ExternalContextSnapshot(
            airAlertIntervals: airAlertIntervals,
            trafficScore: trafficScore,
            powerScore: powerScore,
            weatherScore: weatherContext?.weatherScore,
            weatherContext: weatherContext,
            notes: notes.isEmpty ? nil : notes
        )
    }

    func encode(_ details: AttendanceAnalysisDebugDetails) throws -> String {
        let data = try encoder.encode(details)
        guard let string = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to encode attendance fixture result details")
        }
        return string
    }

    func arrivalHour(for arrivalTime: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.component(.hour, from: arrivalTime)
    }
}
