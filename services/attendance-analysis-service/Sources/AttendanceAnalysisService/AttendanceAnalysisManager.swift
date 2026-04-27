import Fluent
import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceAnalysisManager {
    private let directoryClient: AttendanceDirectoryServiceClient
    private let accessClient: AttendanceAccessServiceClient
    private let externalContextClient: AttendanceExternalContextServiceClient
    private let builder = AttendanceObservationBuilder()
    private let signalCalculator: AttendanceCoreSignalCalculator
    private let baselineWindowDays: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryClient: AttendanceDirectoryServiceClient,
        accessClient: AttendanceAccessServiceClient,
        externalContextClient: AttendanceExternalContextServiceClient,
        baselineWindowDays: Int
    ) {
        self.directoryClient = directoryClient
        self.accessClient = accessClient
        self.externalContextClient = externalContextClient
        self.baselineWindowDays = max(baselineWindowDays, 1)
        self.signalCalculator = AttendanceCoreSignalCalculator(baselineWindowDays: self.baselineWindowDays)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func runObservation(
        userId: UUID,
        dayString: String,
        rebuild: Bool,
        context: AuthenticatedUserContext,
        on database: Database
    ) async throws -> AttendanceObservationRunResponse {
        let day = try AttendanceDay(dayString)

        if !rebuild, let storedBundle = try await storedBundle(userId: userId, day: day, on: database) {
            return AttendanceObservationRunResponse(
                status: storedBundle.result.status,
                observation: storedBundle.observation,
                result: storedBundle.result,
                wasRebuilt: false
            )
        }

        let employer = try await directoryClient.employer(id: userId)
        return try await runObservation(
            employer: employer,
            day: day,
            rebuild: rebuild,
            context: context,
            on: database
        )
    }

    func runObservationsForAllUsers(
        dayString: String,
        rebuild: Bool,
        context: AuthenticatedUserContext,
        on database: Database
    ) async throws -> AttendanceObservationBatchResponse {
        let day = try AttendanceDay(dayString)
        let employers = try await directoryClient.employers()
            .compactMap { employer -> EmployerModel? in
                guard employer.id != nil else {
                    return nil
                }
                return employer
            }
            .sorted {
                ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
            }

        var items = [AttendanceObservationRunResponse]()
        items.reserveCapacity(employers.count)

        for employer in employers {
            let response = try await runObservation(
                employer: employer,
                day: day,
                rebuild: rebuild,
                context: context,
                on: database
            )
            items.append(response)
        }

        return AttendanceObservationBatchResponse(
            day: day.stringValue,
            processedCount: items.count,
            wasRebuilt: rebuild,
            items: items
        )
    }
}

private extension AttendanceAnalysisManager {
    func runObservation(
        employer: EmployerModel,
        day: AttendanceDay,
        rebuild: Bool,
        context: AuthenticatedUserContext,
        on database: Database
    ) async throws -> AttendanceObservationRunResponse {
        guard let userId = employer.id else {
            throw Abort(.internalServerError, reason: "Employer id is required for attendance analysis")
        }

        if !rebuild, let storedBundle = try await storedBundle(userId: userId, day: day, on: database) {
            return AttendanceObservationRunResponse(
                status: storedBundle.result.status,
                observation: storedBundle.observation,
                result: storedBundle.result,
                wasRebuilt: false
            )
        }

        let workNormMinutes = employer.workNormMinutes ?? SeedUsers.defaultWorkNormMinutes
        let logs = try await accessClient.logs(userId: userId, context: context)

        let initialOutcome = builder.build(for: day, logs: logs.logs, workNormMinutes: workNormMinutes)
        let observationDraft = initialOutcome.observation.map {
            AttendanceObservationDraft(
                userId: userId,
                day: $0.day,
                firstEntryTime: $0.firstEntryTime,
                workedMinutes: $0.workedMinutes,
                breakMinutes: $0.breakMinutes,
                sessionsCount: $0.sessionsCount,
                isTechnicalAnomaly: $0.isTechnicalAnomaly,
                anomalyReason: $0.anomalyReason
            )
        }
        let outcome = AttendanceObservationBuildOutcome(status: initialOutcome.status, observation: observationDraft, details: initialOutcome.details)

        let observation = try await upsertObservation(outcome.observation, userId: userId, day: day, on: database)
        let trafficContextResult = await resolveTrafficContext(day: day, observation: observation)
        let resultDraft = try await makeResultDraft(
            outcome: outcome,
            observation: observation,
            userId: userId,
            day: day,
            workNormMinutes: workNormMinutes,
            trafficScore: trafficContextResult.score,
            externalContextNotes: trafficContextResult.notes,
            on: database
        )
        let result = try await upsertResult(userId: userId, day: day, draft: resultDraft, on: database)

        return AttendanceObservationRunResponse(
            status: resultDraft.status.rawValue,
            observation: observation.map(makeObservationResponse),
            result: try makeResultResponse(from: result),
            wasRebuilt: rebuild
        )
    }
}

extension AttendanceAnalysisManager {
    func observations(userId: UUID, on database: Database) async throws -> [AttendanceDayObservationResponse] {
        let observations = try await AttendanceDayObservation.query(on: database)
            .filter(\.$userId == userId)
            .sort(\.$day, .ascending)
            .all()
        return observations.map(makeObservationResponse)
    }

    func observation(userId: UUID, dayString: String, on database: Database) async throws -> AttendanceDayObservationResponse {
        let day = try AttendanceDay(dayString)
        guard let observation = try await findObservation(userId: userId, day: day, on: database) else {
            throw Abort(.notFound, reason: "Attendance observation not found")
        }
        return makeObservationResponse(observation)
    }

    func results(userId: UUID, on database: Database) async throws -> [AttendanceAnalysisResultResponse] {
        let results = try await AttendanceAnalysisResult.query(on: database)
            .filter(\.$userId == userId)
            .filter(\.$status == AttendanceAnalysisStatus.signalsReady.rawValue)
            .sort(\.$day, .ascending)
            .all()
        return try results.map(makeResultResponse)
    }
}

private extension AttendanceAnalysisManager {
    typealias StoredBundle = (observation: AttendanceDayObservationResponse?, result: AttendanceAnalysisResultResponse)

    func storedBundle(userId: UUID, day: AttendanceDay, on database: Database) async throws -> StoredBundle? {
        guard let result = try await findResult(userId: userId, day: day, on: database) else {
            return nil
        }

        let observation: AttendanceDayObservationResponse?
        if let observationId = result.observationId, let storedObservation = try await AttendanceDayObservation.find(observationId, on: database) {
            observation = makeObservationResponse(storedObservation)
        } else {
            observation = nil
        }

        return (observation, try makeResultResponse(from: result))
    }

    func findObservation(userId: UUID, day: AttendanceDay, on database: Database) async throws -> AttendanceDayObservation? {
        try await AttendanceDayObservation.query(on: database)
            .filter(\.$userId == userId)
            .filter(\.$day == day.startOfDay)
            .first()
    }

    func findResult(userId: UUID, day: AttendanceDay, on database: Database) async throws -> AttendanceAnalysisResult? {
        try await AttendanceAnalysisResult.query(on: database)
            .filter(\.$userId == userId)
            .filter(\.$day == day.startOfDay)
            .first()
    }

    func upsertObservation(_ draft: AttendanceObservationDraft?, userId: UUID, day: AttendanceDay, on database: Database) async throws -> AttendanceDayObservation? {
        let existing = try await findObservation(userId: userId, day: day, on: database)

        guard let draft else {
            if let existing {
                try await existing.delete(on: database)
            }
            return nil
        }

        if let existing {
            existing.firstEntryTime = draft.firstEntryTime
            existing.workedMinutes = draft.workedMinutes
            existing.breakMinutes = draft.breakMinutes
            existing.sessionsCount = draft.sessionsCount
            existing.isTechnicalAnomaly = draft.isTechnicalAnomaly
            existing.anomalyReason = draft.anomalyReason
            try await existing.update(on: database)
            return existing
        }

        let observation = AttendanceDayObservation(
            userId: draft.userId,
            day: draft.day.startOfDay,
            firstEntryTime: draft.firstEntryTime,
            workedMinutes: draft.workedMinutes,
            breakMinutes: draft.breakMinutes,
            sessionsCount: draft.sessionsCount,
            isTechnicalAnomaly: draft.isTechnicalAnomaly,
            anomalyReason: draft.anomalyReason
        )
        try await observation.create(on: database)
        return observation
    }

    func upsertResult(
        userId: UUID,
        day: AttendanceDay,
        draft: AttendanceAnalysisResultDraft,
        on database: Database
    ) async throws -> AttendanceAnalysisResult {
        let detailsJson = try encode(draft.details)

        if let existing = try await findResult(userId: userId, day: day, on: database) {
            existing.status = draft.status.rawValue
            existing.observationId = draft.observationId
            existing.historyDaysUsed = draft.historyDaysUsed
            existing.averageStartMinutes = draft.averageStartMinutes
            existing.stddevStartMinutes = draft.stddevStartMinutes
            existing.stddevWorkedMinutes = draft.stddevWorkedMinutes
            existing.workNormMinutes = draft.workNormMinutes
            existing.zS = draft.zS
            existing.zT = draft.zT
            existing.f = draft.f
            existing.detailsJson = detailsJson
            try await existing.update(on: database)
            return existing
        }

        let result = AttendanceAnalysisResult(
            userId: userId,
            day: day.startOfDay,
            status: draft.status.rawValue,
            observationId: draft.observationId,
            historyDaysUsed: draft.historyDaysUsed,
            averageStartMinutes: draft.averageStartMinutes,
            stddevStartMinutes: draft.stddevStartMinutes,
            stddevWorkedMinutes: draft.stddevWorkedMinutes,
            workNormMinutes: draft.workNormMinutes,
            zS: draft.zS,
            zT: draft.zT,
            f: draft.f,
            detailsJson: detailsJson
        )
        try await result.create(on: database)
        return result
    }

    func encode(_ details: AttendanceAnalysisDebugDetails) throws -> String {
        let data = try encoder.encode(details)
        guard let string = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to encode attendance details")
        }
        return string
    }

    func decode(_ detailsJson: String) throws -> AttendanceAnalysisDebugDetails {
        let data = Data(detailsJson.utf8)
        return try decoder.decode(AttendanceAnalysisDebugDetails.self, from: data)
    }

    func makeObservationResponse(_ observation: AttendanceDayObservation) -> AttendanceDayObservationResponse {
        AttendanceDayObservationResponse(
            id: observation.id,
            userId: observation.userId,
            day: AttendanceDay(date: observation.day).stringValue,
            firstEntryTime: observation.firstEntryTime,
            workedMinutes: observation.workedMinutes,
            breakMinutes: observation.breakMinutes,
            sessionsCount: observation.sessionsCount,
            isTechnicalAnomaly: observation.isTechnicalAnomaly,
            anomalyReason: observation.anomalyReason,
            createdAt: observation.createdAt,
            updatedAt: observation.updatedAt
        )
    }

    func makeResultResponse(from result: AttendanceAnalysisResult) throws -> AttendanceAnalysisResultResponse {
        let details = try decode(result.detailsJson)
        return AttendanceAnalysisResultResponse(
            id: result.id,
            userId: result.userId,
            day: AttendanceDay(date: result.day).stringValue,
            status: result.status,
            observationId: result.observationId,
            historyDaysUsed: result.historyDaysUsed ?? details.historyDaysUsed ?? 0,
            averageStartMinutes: result.averageStartMinutes ?? details.averageStartMinutes,
            stddevStartMinutes: result.stddevStartMinutes ?? details.stddevStartMinutes,
            stddevWorkedMinutes: result.stddevWorkedMinutes ?? details.stddevWorkedMinutes,
            workNormMinutes: result.workNormMinutes ?? details.workNormMinutes,
            zS: result.zS ?? details.zS,
            zT: result.zT ?? details.zT,
            f: result.f ?? details.f,
            detailsJson: details,
            createdAt: result.createdAt,
            updatedAt: result.updatedAt
        )
    }
}

private extension AttendanceAnalysisManager {
    func makeResultDraft(
        outcome: AttendanceObservationBuildOutcome,
        observation: AttendanceDayObservation?,
        userId: UUID,
        day: AttendanceDay,
        workNormMinutes: Int,
        trafficScore: Double?,
        externalContextNotes: [String]?,
        on database: Database
    ) async throws -> AttendanceAnalysisResultDraft {
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
                    trafficScore: nil,
                    externalContextNotes: nil
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
                    trafficScore: nil,
                    externalContextNotes: nil
                )
            )

        case .observationBuilt, .signalsReady, .insufficientHistory:
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
                        trafficScore: nil,
                        externalContextNotes: nil
                    )
                )
            }

            let history = try await previousValidObservations(userId: userId, before: day, on: database)
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
                details: makeDebugDetails(
                    from: outcome.details,
                    snapshot: calculation.snapshot,
                    debug: calculation.debug,
                    trafficScore: trafficScore,
                    externalContextNotes: externalContextNotes
                )
            )
        }
    }

    func previousValidObservations(
        userId: UUID,
        before day: AttendanceDay,
        on database: Database
    ) async throws -> [AttendanceCoreSignalCalculator.ObservationInput] {
        let observations = try await AttendanceDayObservation.query(on: database)
            .filter(\.$userId == userId)
            .filter(\.$day < day.startOfDay)
            .filter(\.$isTechnicalAnomaly == false)
            .sort(\.$day, .descending)
            .all()

        return observations.compactMap { observation in
            guard let firstEntryTime = observation.firstEntryTime else {
                return nil
            }

            return AttendanceCoreSignalCalculator.ObservationInput(
                day: AttendanceDay(date: observation.day),
                firstEntryTime: firstEntryTime,
                workedMinutes: observation.workedMinutes
            )
        }
    }

    func makeDebugDetails(
        from source: AttendanceAnalysisDebugDetails,
        snapshot: AttendanceCoreSignalCalculator.Snapshot,
        debug: AttendanceCoreSignalCalculator.Debug,
        trafficScore: Double?,
        externalContextNotes: [String]?
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
            trafficScore: trafficScore,
            externalContextNotes: externalContextNotes
        )
    }

    func resolveTrafficContext(day: AttendanceDay, observation: AttendanceDayObservation?) async -> (score: Double?, notes: [String]?) {
        guard let observation, let arrivalTime = observation.firstEntryTime else {
            return (nil, nil)
        }

        do {
            let response = try await externalContextClient.resolveTraffic(day: day.stringValue, arrivalTime: arrivalTime)
            return (response.trafficScore, nil)
        } catch {
            return (nil, ["traffic_context_unavailable"])
        }
    }
}
