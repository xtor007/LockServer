import Fluent
import Foundation
import SQLKit
import Vapor

struct AttendanceMLPFeedbackService {
    struct SubmissionSummary {
        let feedbackSampleId: UUID
        let pendingFeedbackCount: Int
        let retrainingTriggered: Bool
        let retrainedModelVersion: String?
        let retrainingError: String?
        let result: AttendanceAnalysisResult
    }

    struct FeedbackSnapshot {
        let userId: UUID
        let day: Date
        let zS: Double
        let zT: Double
        let f: Double
        let airAlertMinutes: Int
        let trafficScore: Double
        let powerScore: Double
        let weatherScore: Double
        let etaNNTarget: Double
        let sourceModelVersion: String
    }

    private let client: AttendanceMLPServiceClient
    private let featureBuilder = AttendanceMLPFeatureBuilder()
    private let retrainingThreshold: Int
    private let decoder: JSONDecoder
    private let advisoryLockName = "attendance_mlp_feedback_retraining"

    init(client: AttendanceMLPServiceClient, retrainingThreshold: Int = 500) {
        self.client = client
        self.retrainingThreshold = max(retrainingThreshold, 1)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func submitFeedback(
        userId: UUID,
        dayString: String,
        etaNN: Double,
        on database: Database
    ) async throws -> SubmissionSummary {
        guard etaNN.isFinite, (0...1).contains(etaNN) else {
            throw Abort(.badRequest, reason: "etaNn must be a finite number in range [0, 1]")
        }

        let day = try AttendanceDay(dayString)
        guard let storedResult = try await findResult(userId: userId, day: day, on: database) else {
            throw Abort(.notFound, reason: "Attendance analysis result not found for requested user and day")
        }

        guard let resultId = storedResult.id else {
            throw Abort(.internalServerError, reason: "Attendance analysis result id is missing")
        }

        let snapshot = try makeFeedbackSnapshot(from: storedResult, correctedEtaNN: etaNN)
        let feedbackSampleId = try await database.transaction { transaction in
            guard let result = try await AttendanceAnalysisResult.find(resultId, on: transaction) else {
                throw Abort(.notFound, reason: "Attendance analysis result not found for requested user and day")
            }

            result.etaNN = etaNN
            result.mlpStatus = AttendanceMLPStatus.manuallyCorrected.rawValue
            try await result.update(on: transaction)

            let sample = AttendanceMLPFeedbackSample(
                userId: snapshot.userId,
                day: snapshot.day,
                zS: snapshot.zS,
                zT: snapshot.zT,
                f: snapshot.f,
                airAlertMinutes: snapshot.airAlertMinutes,
                trafficScore: snapshot.trafficScore,
                powerScore: snapshot.powerScore,
                weatherScore: snapshot.weatherScore,
                etaNNTarget: snapshot.etaNNTarget,
                sourceModelVersion: snapshot.sourceModelVersion
            )
            try await sample.create(on: transaction)

            guard let sampleId = sample.id else {
                throw Abort(.internalServerError, reason: "Attendance MLP feedback sample id is missing")
            }
            return sampleId
        }

        let retrainingOutcome = await attemptAutomaticRetraining(on: database)
        guard let updatedResult = try await AttendanceAnalysisResult.find(resultId, on: database) else {
            throw Abort(.internalServerError, reason: "Updated attendance analysis result not found")
        }

        return SubmissionSummary(
            feedbackSampleId: feedbackSampleId,
            pendingFeedbackCount: retrainingOutcome.pendingFeedbackCount,
            retrainingTriggered: retrainingOutcome.retrainingTriggered,
            retrainedModelVersion: retrainingOutcome.retrainedModelVersion,
            retrainingError: retrainingOutcome.retrainingError,
            result: updatedResult
        )
    }

    func makeFeedbackSnapshot(from result: AttendanceAnalysisResult, correctedEtaNN: Double) throws -> FeedbackSnapshot {
        guard let modelVersion = result.mlpModelVersion, modelVersion.isEmpty == false else {
            throw Abort(.unprocessableEntity, reason: "Attendance analysis result does not have a source MLP model version")
        }

        let details = try decodeDetails(result.detailsJson)
        let featureVector = try featureBuilder.build(
            from: .init(
                zS: result.zS,
                zT: result.zT,
                f: result.f,
                details: details
            )
        )

        guard result.status == AttendanceAnalysisStatus.readyForNextStage.rawValue else {
            throw Abort(.unprocessableEntity, reason: "Attendance analysis result is not eligible for MLP feedback")
        }

        return FeedbackSnapshot(
            userId: result.userId,
            day: result.day,
            zS: featureVector.orderedValues[0],
            zT: featureVector.orderedValues[1],
            f: featureVector.orderedValues[2],
            airAlertMinutes: Int(featureVector.orderedValues[3]),
            trafficScore: featureVector.orderedValues[4],
            powerScore: featureVector.orderedValues[5],
            weatherScore: featureVector.orderedValues[6],
            etaNNTarget: correctedEtaNN,
            sourceModelVersion: modelVersion
        )
    }
}

private extension AttendanceMLPFeedbackService {
    struct RetrainingOutcome {
        let pendingFeedbackCount: Int
        let retrainingTriggered: Bool
        let retrainedModelVersion: String?
        let retrainingError: String?
    }

    struct AdvisoryLockRow: Decodable {
        let acquired: Int
    }

    func attemptAutomaticRetraining(on database: Database) async -> RetrainingOutcome {
        if let sqlDatabase = database as? any SQLDatabase {
            return await attemptAutomaticRetrainingWithLock(sqlDatabase: sqlDatabase, on: database)
        }

        return await retrainingLoop(on: database)
    }

    func attemptAutomaticRetrainingWithLock(
        sqlDatabase: any SQLDatabase,
        on database: Database
    ) async -> RetrainingOutcome {
        do {
            guard try await acquireAdvisoryLock(on: sqlDatabase) else {
                let pending = (try? await pendingFeedbackCount(on: database)) ?? 0
                return RetrainingOutcome(
                    pendingFeedbackCount: pending,
                    retrainingTriggered: false,
                    retrainedModelVersion: nil,
                    retrainingError: nil
                )
            }
        } catch {
            let pending = (try? await pendingFeedbackCount(on: database)) ?? 0
            return RetrainingOutcome(
                pendingFeedbackCount: pending,
                retrainingTriggered: false,
                retrainedModelVersion: nil,
                retrainingError: String(describing: error)
            )
        }

        let outcome = await retrainingLoop(on: database)
        try? await releaseAdvisoryLock(on: sqlDatabase)
        return outcome
    }

    func retrainingLoop(on database: Database) async -> RetrainingOutcome {
        var pendingCount = (try? await pendingFeedbackCount(on: database)) ?? 0
        var retrainingTriggered = false
        var retrainedModelVersion: String?

        while pendingCount >= retrainingThreshold {
            do {
                let batch = try await loadPendingBatch(limit: retrainingThreshold, on: database)
                guard batch.count == retrainingThreshold else {
                    pendingCount = batch.count
                    break
                }

                let response = try await client.retrain(
                    feedbackSamples: batch.compactMap(makeRetrainSample)
                )
                try await markConsumed(sampleIds: batch.compactMap(\.id), modelVersion: response.modelVersion, on: database)

                retrainingTriggered = true
                retrainedModelVersion = response.modelVersion
                pendingCount = try await pendingFeedbackCount(on: database)
            } catch {
                return RetrainingOutcome(
                    pendingFeedbackCount: pendingCount,
                    retrainingTriggered: retrainingTriggered,
                    retrainedModelVersion: retrainedModelVersion,
                    retrainingError: String(describing: error)
                )
            }
        }

        return RetrainingOutcome(
            pendingFeedbackCount: pendingCount,
            retrainingTriggered: retrainingTriggered,
            retrainedModelVersion: retrainedModelVersion,
            retrainingError: nil
        )
    }

    func makeRetrainSample(_ sample: AttendanceMLPFeedbackSample) -> AttendanceMLPServiceClient.RetrainFeedbackSample? {
        guard let sampleId = sample.id else {
            return nil
        }

        return AttendanceMLPServiceClient.RetrainFeedbackSample(
            sampleId: sampleId.uuidString,
            zS: sample.zS,
            zT: sample.zT,
            f: sample.f,
            airAlertMinutes: sample.airAlertMinutes,
            trafficScore: sample.trafficScore,
            powerScore: sample.powerScore,
            weatherScore: sample.weatherScore,
            etaNNTarget: sample.etaNNTarget,
            sourceModelVersion: sample.sourceModelVersion
        )
    }

    func pendingFeedbackCount(on database: Database) async throws -> Int {
        try await AttendanceMLPFeedbackSample.query(on: database)
            .filter(\.$consumedModelVersion == nil)
            .count()
    }

    func loadPendingBatch(limit: Int, on database: Database) async throws -> [AttendanceMLPFeedbackSample] {
        let samples = try await AttendanceMLPFeedbackSample.query(on: database)
            .filter(\.$consumedModelVersion == nil)
            .all()

        return samples
            .sorted(by: pendingFeedbackOrder)
            .prefix(limit)
            .map { $0 }
    }

    func pendingFeedbackOrder(_ lhs: AttendanceMLPFeedbackSample, _ rhs: AttendanceMLPFeedbackSample) -> Bool {
        let lhsCreatedAt = lhs.createdAt ?? .distantPast
        let rhsCreatedAt = rhs.createdAt ?? .distantPast
        if lhsCreatedAt != rhsCreatedAt {
            return lhsCreatedAt < rhsCreatedAt
        }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }

    func markConsumed(sampleIds: [UUID], modelVersion: String, on database: Database) async throws {
        guard sampleIds.isEmpty == false else {
            return
        }

        try await database.transaction { transaction in
            for sampleId in sampleIds {
                guard let sample = try await AttendanceMLPFeedbackSample.find(sampleId, on: transaction) else {
                    continue
                }
                sample.consumedModelVersion = modelVersion
                try await sample.update(on: transaction)
            }
        }
    }

    func findResult(userId: UUID, day: AttendanceDay, on database: Database) async throws -> AttendanceAnalysisResult? {
        try await AttendanceAnalysisResult.query(on: database)
            .filter(\.$userId == userId)
            .filter(\.$day == day.startOfDay)
            .first()
    }

    func decodeDetails(_ detailsJson: String) throws -> AttendanceAnalysisDebugDetails {
        try decoder.decode(AttendanceAnalysisDebugDetails.self, from: Data(detailsJson.utf8))
    }

    func acquireAdvisoryLock(on database: any SQLDatabase) async throws -> Bool {
        let rows = try await database.raw(
            "SELECT GET_LOCK(\(bind: advisoryLockName), 0) AS acquired"
        ).all(decoding: AdvisoryLockRow.self)
        return rows.first?.acquired == 1
    }

    func releaseAdvisoryLock(on database: any SQLDatabase) async throws {
        _ = try await database.raw(
            "SELECT RELEASE_LOCK(\(bind: advisoryLockName)) AS released"
        ).run()
    }
}
