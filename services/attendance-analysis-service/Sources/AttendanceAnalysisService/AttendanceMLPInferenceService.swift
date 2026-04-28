import Fluent
import Foundation
import SQLKit
import Vapor

struct AttendanceMLPInferenceService {
    enum Scope {
        case userDay(UUID, AttendanceDay)
        case day(AttendanceDay)
        case allEligible
    }

    struct ExecutionSummary {
        let modelVersion: String?
        let processedResultIds: [UUID]
        let inferredResultIds: Set<UUID>
        let failedResultIds: Set<UUID>
        let processedCount: Int
        let inferredCount: Int
        let failedCount: Int
        let skippedCount: Int
    }

    private let client: AttendanceMLPServiceClient
    private let featureBuilder = AttendanceMLPFeatureBuilder()
    private let decoder: JSONDecoder
    private let batchSize: Int

    init(client: AttendanceMLPServiceClient, batchSize: Int = 500) {
        self.client = client
        self.batchSize = max(batchSize, 1)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func execute(scope: Scope, rebuild: Bool, on database: Database) async throws -> ExecutionSummary {
        let scopeRows = try await loadScopeRows(scope, on: database)
        let processedIds = scopeRows.compactMap(\.resultId)

        guard processedIds.isEmpty == false else {
            return ExecutionSummary(
                modelVersion: nil,
                processedResultIds: [],
                inferredResultIds: [],
                failedResultIds: [],
                processedCount: 0,
                inferredCount: 0,
                failedCount: 0,
                skippedCount: 0
            )
        }

        let rowsToInfer = scopeRows.filter { row in
            guard row.isEligibleForMLP else {
                return false
            }
            return rebuild || row.etaNN == nil
        }

        guard rowsToInfer.isEmpty == false else {
            return ExecutionSummary(
                modelVersion: scopeRows.compactMap(\.mlpModelVersion).first,
                processedResultIds: processedIds,
                inferredResultIds: [],
                failedResultIds: [],
                processedCount: scopeRows.count,
                inferredCount: 0,
                failedCount: 0,
                skippedCount: scopeRows.count
            )
        }

        let prepared = prepare(rowsToInfer)
        var updates = prepared.failures
        let inferenceUpdates = try await infer(prepared.candidates)
        updates.append(contentsOf: inferenceUpdates)

        try await apply(updates: updates, on: database)

        let inferredIds = Set(updates.filter { $0.mlpStatus == .ready }.map(\.resultId))
        let failedIds = Set(updates.filter { $0.mlpStatus == .failed }.map(\.resultId))

        return ExecutionSummary(
            modelVersion: updates.compactMap(\.mlpModelVersion).first,
            processedResultIds: processedIds,
            inferredResultIds: inferredIds,
            failedResultIds: failedIds,
            processedCount: scopeRows.count,
            inferredCount: inferredIds.count,
            failedCount: failedIds.count,
            skippedCount: scopeRows.count - updates.count
        )
    }
}

private extension AttendanceMLPInferenceService {
    struct ResultCandidateRow: Decodable {
        let id: String
        let userId: String
        let dayString: String
        let status: String
        let etaNN: Double?
        let mlpModelVersion: String?
        let mlpStatus: String?
        let zS: Double?
        let zT: Double?
        let f: Double?
        let detailsJson: String

        enum CodingKeys: String, CodingKey {
            case id
            case userId
            case dayString
            case status
            case etaNN
            case mlpModelVersion
            case mlpStatus
            case zS
            case zT
            case f
            case detailsJson
        }

        var resultId: UUID? {
            UUID(uuidString: id)
        }

        var isEligibleForMLP: Bool {
            status == AttendanceAnalysisStatus.readyForNextStage.rawValue
        }
    }

    struct PreparedCandidate {
        let resultId: UUID
        let requestId: String
        let featureValues: [Double]
    }

    struct PreparedRows {
        let candidates: [PreparedCandidate]
        let failures: [ResultUpdate]
    }

    struct ResultUpdate {
        let resultId: UUID
        let etaNN: Double?
        let mlpModelVersion: String?
        let mlpStatus: AttendanceMLPStatus
    }

    func prepare(_ rows: [ResultCandidateRow]) -> PreparedRows {
        var candidates = [PreparedCandidate]()
        var failures = [ResultUpdate]()
        candidates.reserveCapacity(rows.count)
        failures.reserveCapacity(rows.count)

        for row in rows {
            guard let resultId = row.resultId else {
                continue
            }

            do {
                let details = try decodeDetails(row.detailsJson)
                let featureVector = try featureBuilder.build(
                    from: .init(
                        zS: row.zS,
                        zT: row.zT,
                        f: row.f,
                        details: details
                    )
                )
                candidates.append(
                    PreparedCandidate(
                        resultId: resultId,
                        requestId: resultId.uuidString,
                        featureValues: featureVector.orderedValues
                    )
                )
            } catch {
                failures.append(
                    ResultUpdate(
                        resultId: resultId,
                        etaNN: nil,
                        mlpModelVersion: nil,
                        mlpStatus: .failed
                    )
                )
            }
        }

        return PreparedRows(candidates: candidates, failures: failures)
    }

    func infer(_ candidates: [PreparedCandidate]) async throws -> [ResultUpdate] {
        guard candidates.isEmpty == false else {
            return []
        }

        var updates = [ResultUpdate]()
        updates.reserveCapacity(candidates.count)

        var startIndex = 0
        while startIndex < candidates.count {
            let endIndex = min(startIndex + batchSize, candidates.count)
            let batch = Array(candidates[startIndex..<endIndex])
            let batchUpdates = try await inferBatch(batch)
            updates.append(contentsOf: batchUpdates)
            startIndex = endIndex
        }

        return updates
    }

    func inferBatch(_ batch: [PreparedCandidate]) async throws -> [ResultUpdate] {
        do {
            let response = try await client.infer(
                items: batch.map { candidate in
                    AttendanceMLPServiceClient.InferenceItem(
                        requestId: candidate.requestId,
                        features: candidate.featureValues
                    )
                }
            )

            guard response.featureOrder == AttendanceMLPFeatureBuilder.featureOrder else {
                return batch.map { candidate in
                    ResultUpdate(
                        resultId: candidate.resultId,
                        etaNN: nil,
                        mlpModelVersion: nil,
                        mlpStatus: .failed
                    )
                }
            }

            let resultsByRequestId = Dictionary(uniqueKeysWithValues: response.results.map { ($0.requestId, $0) })
            return batch.map { candidate in
                guard let result = resultsByRequestId[candidate.requestId],
                      result.modelVersion == response.modelVersion,
                      result.diagnostics.featureOrder == AttendanceMLPFeatureBuilder.featureOrder,
                      result.diagnostics.inputFeatures.count == AttendanceMLPFeatureBuilder.featureOrder.count,
                      result.diagnostics.normalizedFeatures.count == AttendanceMLPFeatureBuilder.featureOrder.count,
                      result.etaNN.isFinite,
                      (0...1).contains(result.etaNN) else {
                    return ResultUpdate(
                        resultId: candidate.resultId,
                        etaNN: nil,
                        mlpModelVersion: nil,
                        mlpStatus: .failed
                    )
                }

                return ResultUpdate(
                    resultId: candidate.resultId,
                    etaNN: result.etaNN,
                    mlpModelVersion: response.modelVersion,
                    mlpStatus: .ready
                )
            }
        } catch {
            return batch.map { candidate in
                ResultUpdate(
                    resultId: candidate.resultId,
                    etaNN: nil,
                    mlpModelVersion: nil,
                    mlpStatus: .failed
                )
            }
        }
    }

    func loadScopeRows(_ scope: Scope, on database: Database) async throws -> [ResultCandidateRow] {
        switch scope {
        case let .userDay(userId, day):
            return try await rawResultRows(
                sql: database,
                whereClause: """
                user_id = UUID_TO_BIN('\(userId.uuidString)')
                AND DATE_FORMAT(day, '%Y-%m-%d') = '\(day.stringValue)'
                """,
                orderBy: "day ASC"
            )
        case let .day(day):
            return try await rawResultRows(
                sql: database,
                whereClause: "DATE_FORMAT(day, '%Y-%m-%d') = '\(day.stringValue)'",
                orderBy: "user_id ASC"
            )
        case .allEligible:
            return try await rawResultRows(
                sql: database,
                whereClause: "status = '\(AttendanceAnalysisStatus.readyForNextStage.rawValue)'",
                orderBy: "user_id ASC, day ASC"
            )
        }
    }

    func rawResultRows(sql database: Database, whereClause: String, orderBy: String = "user_id ASC, day ASC") async throws -> [ResultCandidateRow] {
        if let sqlDatabase = database as? any SQLDatabase {
            return try await sqlDatabase.raw(
                """
                SELECT
                    BIN_TO_UUID(id) AS id,
                    BIN_TO_UUID(user_id) AS userId,
                    DATE_FORMAT(day, '%Y-%m-%d') AS dayString,
                    status,
                    eta_nn AS etaNN,
                    mlp_model_version AS mlpModelVersion,
                    mlp_status AS mlpStatus,
                    z_s AS zS,
                    z_t AS zT,
                    f AS f,
                    details_json AS detailsJson
                FROM attendance_analysis_results
                WHERE \(unsafeRaw: whereClause)
                ORDER BY \(unsafeRaw: orderBy)
                """
            ).all(decoding: ResultCandidateRow.self)
        }

        let results = try await AttendanceAnalysisResult.query(on: database)
            .sort(\.$userId, .ascending)
            .sort(\.$day, .ascending)
            .all()

        return results.compactMap { result in
            ResultCandidateRow(
                id: result.id?.uuidString ?? "",
                userId: result.userId.uuidString,
                dayString: AttendanceDay(date: result.day).stringValue,
                status: result.status,
                etaNN: result.etaNN,
                mlpModelVersion: result.mlpModelVersion,
                mlpStatus: result.mlpStatus,
                zS: result.zS,
                zT: result.zT,
                f: result.f,
                detailsJson: result.detailsJson
            )
        }
    }

    func apply(updates: [ResultUpdate], on database: Database) async throws {
        guard updates.isEmpty == false else {
            return
        }

        try await database.transaction { transaction in
            guard let sqlDatabase = transaction as? any SQLDatabase else {
                for update in updates {
                    guard let result = try await AttendanceAnalysisResult.find(update.resultId, on: transaction) else {
                        continue
                    }
                    result.etaNN = update.etaNN
                    result.mlpModelVersion = update.mlpModelVersion
                    result.mlpStatus = update.mlpStatus.rawValue
                    try await result.update(on: transaction)
                }
                return
            }

            try await sqlDatabase.raw("DROP TEMPORARY TABLE IF EXISTS attendance_mlp_assignments").run()
            try await sqlDatabase.raw(
                """
                CREATE TEMPORARY TABLE attendance_mlp_assignments (
                    result_id CHAR(36) PRIMARY KEY,
                    eta_nn DOUBLE NULL,
                    mlp_model_version VARCHAR(191) NULL,
                    mlp_status VARCHAR(64) NOT NULL
                )
                """
            ).run()

            let sqlBatchSize = 1_000
            let escaped: (String) -> String = { value in
                value.replacingOccurrences(of: "'", with: "''")
            }
            let sqlValue: (Double?) -> String = { value in
                guard let value else {
                    return "NULL"
                }
                return "\(value)"
            }
            let sqlStringValue: (String?) -> String = { value in
                guard let value else {
                    return "NULL"
                }
                return "'\(escaped(value))'"
            }
            var startIndex = 0
            while startIndex < updates.count {
                let endIndex = min(startIndex + sqlBatchSize, updates.count)
                let batch = updates[startIndex..<endIndex]
                let values = batch.map { update in
                    "('\(escaped(update.resultId.uuidString))', \(sqlValue(update.etaNN)), \(sqlStringValue(update.mlpModelVersion)), '\(escaped(update.mlpStatus.rawValue))')"
                }.joined(separator: ", ")

                try await sqlDatabase.raw(
                    """
                    INSERT INTO attendance_mlp_assignments (
                        result_id,
                        eta_nn,
                        mlp_model_version,
                        mlp_status
                    )
                    VALUES \(unsafeRaw: values)
                    """
                ).run()

                startIndex = endIndex
            }

            try await sqlDatabase.raw(
                """
                UPDATE attendance_analysis_results AS results
                JOIN attendance_mlp_assignments AS assignments
                    ON results.id = UUID_TO_BIN(assignments.result_id)
                SET
                    results.eta_nn = assignments.eta_nn,
                    results.mlp_model_version = assignments.mlp_model_version,
                    results.mlp_status = assignments.mlp_status
                """
            ).run()
        }
    }

    func decodeDetails(_ detailsJson: String) throws -> AttendanceAnalysisDebugDetails {
        try decoder.decode(AttendanceAnalysisDebugDetails.self, from: Data(detailsJson.utf8))
    }

}
