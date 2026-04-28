import Fluent
import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceAnalysisManager {
    private let directoryClient: AttendanceDirectoryServiceClient
    private let accessClient: AttendanceAccessServiceClient
    private let externalContextClient: AttendanceExternalContextServiceClient
    private let clusteringService: AttendanceClusteringService
    private let mlpInferenceService: AttendanceMLPInferenceService
    private let mlpFeedbackService: AttendanceMLPFeedbackService
    private let builder = AttendanceObservationBuilder()
    private let signalCalculator: AttendanceCoreSignalCalculator
    private let baselineWindowDays: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryClient: AttendanceDirectoryServiceClient,
        accessClient: AttendanceAccessServiceClient,
        externalContextClient: AttendanceExternalContextServiceClient,
        baselineWindowDays: Int,
        clusteringService: AttendanceClusteringService,
        mlpInferenceService: AttendanceMLPInferenceService,
        mlpFeedbackService: AttendanceMLPFeedbackService
    ) {
        self.directoryClient = directoryClient
        self.accessClient = accessClient
        self.externalContextClient = externalContextClient
        self.clusteringService = clusteringService
        self.mlpInferenceService = mlpInferenceService
        self.mlpFeedbackService = mlpFeedbackService
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
                guard employer.id != nil, employer.isAdmin == false else {
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

    func runClustering(
        dayString: String,
        userId: UUID?,
        rebuild: Bool,
        on database: Database
    ) async throws -> AttendanceClusteringRunResponse {
        let day = try AttendanceDay(dayString)
        let scope: AttendanceClusteringService.Scope = if let userId {
            .userDay(userId, day)
        } else {
            .day(day)
        }

        let execution = try await clusteringService.execute(scope: scope, rebuildModel: rebuild, on: database)
        let processedIds = Set(execution.processedResultIds)
        let results = try await AttendanceAnalysisResult.query(on: database)
            .filter(\.$day == day.startOfDay)
            .sort(\.$userId, .ascending)
            .all()
            .filter { result in
                processedIds.contains(result.id ?? UUID()) &&
                    (userId == nil || result.userId == userId)
            }

        let resultResponses = try results.map(makeResultResponse)
        let items = resultResponses.map { result in
            AttendanceClusteringRunItemResponse(
                userId: result.userId,
                day: result.day,
                status: result.status,
                clusteringStatus: result.clusteringStatus,
                wasClustered: result.id.map(execution.clusteredResultIds.contains) ?? false,
                result: result
            )
        }

        if userId != nil, items.isEmpty {
            throw Abort(.notFound, reason: "Attendance analysis result not found for requested user and day")
        }

        return AttendanceClusteringRunResponse(
            day: day.stringValue,
            userId: userId,
            processedCount: execution.processedCount,
            clusteredCount: execution.clusteredCount,
            skippedCount: execution.skippedCount,
            wasRebuilt: rebuild,
            modelVersion: execution.modelVersion,
            items: items
        )
    }

    func runMLP(
        dayString: String,
        userId: UUID?,
        rebuild: Bool,
        on database: Database
    ) async throws -> AttendanceMLPRunResponse {
        let day = try AttendanceDay(dayString)
        let scope: AttendanceMLPInferenceService.Scope = if let userId {
            .userDay(userId, day)
        } else {
            .day(day)
        }

        let execution = try await mlpInferenceService.execute(scope: scope, rebuild: rebuild, on: database)
        let processedIds = Set(execution.processedResultIds)
        let results = try await AttendanceAnalysisResult.query(on: database)
            .filter(\.$day == day.startOfDay)
            .sort(\.$userId, .ascending)
            .all()
            .filter { result in
                processedIds.contains(result.id ?? UUID()) &&
                    (userId == nil || result.userId == userId)
            }

        let resultResponses = try results.map(makeResultResponse)
        let items = resultResponses.map { result in
            AttendanceMLPRunItemResponse(
                userId: result.userId,
                day: result.day,
                status: result.status,
                mlpStatus: result.mlpStatus,
                wasInferred: result.id.map(execution.inferredResultIds.contains) ?? false,
                etaNN: result.etaNN,
                mlpModelVersion: result.mlpModelVersion,
                result: result
            )
        }

        if userId != nil, items.isEmpty {
            throw Abort(.notFound, reason: "Attendance analysis result not found for requested user and day")
        }

        return AttendanceMLPRunResponse(
            day: day.stringValue,
            userId: userId,
            processedCount: execution.processedCount,
            inferredCount: execution.inferredCount,
            failedCount: execution.failedCount,
            skippedCount: execution.skippedCount,
            wasRebuilt: rebuild,
            modelVersion: execution.modelVersion,
            items: items
        )
    }

    func submitMLPFeedback(
        userId: UUID,
        dayString: String,
        etaNN: Double,
        on database: Database
    ) async throws -> AttendanceMLPFeedbackResponse {
        let submission = try await mlpFeedbackService.submitFeedback(
            userId: userId,
            dayString: dayString,
            etaNN: etaNN,
            on: database
        )

        return AttendanceMLPFeedbackResponse(
            feedbackSampleId: submission.feedbackSampleId,
            pendingFeedbackCount: submission.pendingFeedbackCount,
            retrainingTriggered: submission.retrainingTriggered,
            retrainedModelVersion: submission.retrainedModelVersion,
            retrainingError: submission.retrainingError,
            result: try makeResultResponse(from: submission.result)
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
        let externalContextResult = await resolveExternalContext(day: day, observation: observation)
        let resultDraft = try await makeResultDraft(
            outcome: outcome,
            observation: observation,
            userId: userId,
            day: day,
            workNormMinutes: workNormMinutes,
            airAlertIntervals: externalContextResult.airAlertIntervals,
            trafficScore: externalContextResult.trafficScore,
            powerScore: externalContextResult.powerScore,
            weatherScore: externalContextResult.weatherScore,
            weatherContext: externalContextResult.weatherContext,
            externalContextNotes: externalContextResult.notes,
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
            .sort(\.$day, .ascending)
            .all()
            .filter { visibleResultStatuses.contains($0.status) }
        return try results.map(makeResultResponse)
    }
}

private extension AttendanceAnalysisManager {
    var visibleResultStatuses: Set<String> {
        [
            AttendanceAnalysisStatus.signalsReady.rawValue,
            AttendanceAnalysisStatus.clusteringTerminalStableNormal.rawValue,
            AttendanceAnalysisStatus.clusteringTechnicalOutlier.rawValue,
            AttendanceAnalysisStatus.readyForNextStage.rawValue
        ]
    }

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
            existing.clusterName = draft.clusterName
            existing.clusterScore = draft.clusterScore
            existing.clusterWeight = draft.clusterWeight
            existing.clusterModelVersion = draft.clusterModelVersion
            existing.clusterDistance = draft.clusterDistance
            existing.clusteringStatus = draft.clusteringStatus.rawValue
            existing.etaNN = draft.etaNN
            existing.mlpModelVersion = draft.mlpModelVersion
            existing.mlpStatus = draft.mlpStatus.rawValue
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
            clusterName: draft.clusterName,
            clusterScore: draft.clusterScore,
            clusterWeight: draft.clusterWeight,
            clusterModelVersion: draft.clusterModelVersion,
            clusterDistance: draft.clusterDistance,
            clusteringStatus: draft.clusteringStatus.rawValue,
            etaNN: draft.etaNN,
            mlpModelVersion: draft.mlpModelVersion,
            mlpStatus: draft.mlpStatus.rawValue,
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
            clusterName: result.clusterName ?? details.clusterName,
            clusterScore: result.clusterScore ?? details.clusterScore,
            clusterWeight: result.clusterWeight ?? details.clusterWeight,
            clusterModelVersion: result.clusterModelVersion ?? details.clusterModelVersion,
            clusterDistance: result.clusterDistance ?? details.clusterDistance,
            clusteringStatus: result.clusteringStatus ?? details.clusteringStatus,
            etaNN: result.etaNN,
            mlpModelVersion: result.mlpModelVersion,
            mlpStatus: result.mlpStatus,
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
        airAlertIntervals: [AirAlertInterval]?,
        trafficScore: Double?,
        powerScore: Double?,
        weatherScore: Double?,
        weatherContext: WeatherContextResolvedValue?,
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
                clusterName: nil,
                clusterScore: nil,
                clusterWeight: nil,
                clusterModelVersion: nil,
                clusterDistance: nil,
                clusteringStatus: .notApplicable,
                etaNN: nil,
                mlpModelVersion: nil,
                mlpStatus: .notReady,
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
                    arrivalTime: nil,
                    airAlertIntervals: nil,
                    trafficScore: nil,
                    powerScore: nil,
                    weatherScore: nil,
                    weatherContext: nil,
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
                clusterName: nil,
                clusterScore: nil,
                clusterWeight: nil,
                clusterModelVersion: nil,
                clusterDistance: nil,
                clusteringStatus: .notApplicable,
                etaNN: nil,
                mlpModelVersion: nil,
                mlpStatus: .notReady,
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
                    arrivalTime: nil,
                    airAlertIntervals: nil,
                    trafficScore: nil,
                    powerScore: nil,
                    weatherScore: nil,
                    weatherContext: nil,
                    externalContextNotes: nil
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
                    etaNN: nil,
                    mlpModelVersion: nil,
                    mlpStatus: .notReady,
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
                        arrivalTime: nil,
                        airAlertIntervals: nil,
                        trafficScore: nil,
                        powerScore: nil,
                        weatherScore: nil,
                        weatherContext: nil,
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
                clusterName: nil,
                clusterScore: nil,
                clusterWeight: nil,
                clusterModelVersion: nil,
                clusterDistance: nil,
                clusteringStatus: calculation.status == .signalsReady ? .notStarted : .notApplicable,
                etaNN: nil,
                mlpModelVersion: nil,
                mlpStatus: .notReady,
                details: makeDebugDetails(
                    from: outcome.details,
                    snapshot: calculation.snapshot,
                    debug: calculation.debug,
                    arrivalTime: observation.firstEntryTime,
                    airAlertIntervals: airAlertIntervals,
                    trafficScore: trafficScore,
                    powerScore: powerScore,
                    weatherScore: weatherScore,
                    weatherContext: weatherContext,
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
        arrivalTime: Date?,
        airAlertIntervals: [AirAlertInterval]?,
        trafficScore: Double?,
        powerScore: Double?,
        weatherScore: Double?,
        weatherContext: WeatherContextResolvedValue?,
        externalContextNotes: [String]?
    ) -> AttendanceAnalysisDebugDetails {
        let airAlertMinutes = AttendanceAirAlertImpactCalculator.totalMinutes(
            arrivalTime: arrivalTime,
            sessionRanges: source.sessionRanges,
            intervals: airAlertIntervals
        )

        return AttendanceAnalysisDebugDetails(
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
            airAlertIntervals: airAlertIntervals,
            airAlertMinutes: airAlertMinutes,
            trafficScore: trafficScore,
            powerScore: powerScore,
            weatherScore: weatherScore,
            weatherContext: weatherContext,
            externalContextNotes: externalContextNotes
        )
    }

    func resolveExternalContext(
        day: AttendanceDay,
        observation: AttendanceDayObservation?
    ) async -> (
        airAlertIntervals: [AirAlertInterval]?,
        trafficScore: Double?,
        powerScore: Double?,
        weatherScore: Double?,
        weatherContext: WeatherContextResolvedValue?,
        notes: [String]?
    ) {
        guard let observation, let arrivalTime = observation.firstEntryTime else {
            return (nil, nil, nil, nil, nil, nil)
        }

        do {
            let response = try await externalContextClient.dayContext(day: day.stringValue, arrivalTime: arrivalTime)
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

            return (
                airAlertIntervals,
                trafficScore,
                powerScore,
                weatherContext?.weatherScore,
                weatherContext,
                notes.isEmpty ? nil : notes
            )
        } catch {
            return (
                nil,
                nil,
                nil,
                nil,
                nil,
                [
                    "air_alerts_context_unavailable",
                    "traffic_context_unavailable",
                    "power_context_unavailable",
                    "weather_context_unavailable"
                ]
            )
        }
    }

    func arrivalHour(for arrivalTime: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")!
        return calendar.component(.hour, from: arrivalTime)
    }
}
