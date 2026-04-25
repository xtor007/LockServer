import Fluent
import Foundation
import LockServerContracts
import LockServerCore
import Vapor

struct AttendanceAnalysisManager {
    private let directoryClient: AttendanceDirectoryServiceClient
    private let accessClient: AttendanceAccessServiceClient
    private let builder = AttendanceObservationBuilder()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryClient: AttendanceDirectoryServiceClient, accessClient: AttendanceAccessServiceClient) {
        self.directoryClient = directoryClient
        self.accessClient = accessClient

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
        let result = try await upsertResult(
            userId: userId,
            day: day,
            status: outcome.status.rawValue,
            observationId: observation?.id,
            details: outcome.details,
            on: database
        )

        return AttendanceObservationRunResponse(
            status: outcome.status.rawValue,
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
        status: String,
        observationId: UUID?,
        details: AttendanceAnalysisDebugDetails,
        on database: Database
    ) async throws -> AttendanceAnalysisResult {
        let detailsJson = try encode(details)

        if let existing = try await findResult(userId: userId, day: day, on: database) {
            existing.status = status
            existing.observationId = observationId
            existing.detailsJson = detailsJson
            try await existing.update(on: database)
            return existing
        }

        let result = AttendanceAnalysisResult(
            userId: userId,
            day: day.startOfDay,
            status: status,
            observationId: observationId,
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
        AttendanceAnalysisResultResponse(
            id: result.id,
            userId: result.userId,
            day: AttendanceDay(date: result.day).stringValue,
            status: result.status,
            observationId: result.observationId,
            detailsJson: try decode(result.detailsJson),
            createdAt: result.createdAt,
            updatedAt: result.updatedAt
        )
    }
}
