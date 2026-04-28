import Fluent
import Foundation
import SQLKit
import Vapor

struct AttendanceRiskScoreService {
    enum Scope {
        case userDay(UUID, AttendanceDay)
        case day(AttendanceDay)
        case allEligible
    }

    struct ExecutionSummary {
        let processedResultIds: [UUID]
        let calculatedResultIds: Set<UUID>
        let processedCount: Int
        let calculatedCount: Int
        let skippedCount: Int
    }

    struct Calculation {
        let score: Double
        let zone: AttendanceRiskZone
    }

    let alpha: Double
    let deficitWeight: Double

    init(alpha: Double, deficitWeight: Double) {
        self.alpha = max(alpha, 0)
        self.deficitWeight = max(deficitWeight, 0)
    }

    func execute(scope: Scope, rebuild: Bool, on database: Database) async throws -> ExecutionSummary {
        let scopeRows = try await loadScopeRows(scope, on: database)
        let processedIds = scopeRows.compactMap(\.resultId)

        guard processedIds.isEmpty == false else {
            return ExecutionSummary(
                processedResultIds: [],
                calculatedResultIds: [],
                processedCount: 0,
                calculatedCount: 0,
                skippedCount: 0
            )
        }

        let rowsToCalculate = scopeRows.filter { row in
            guard row.isEligibleForRisk else {
                return false
            }
            return rebuild || row.hasPersistedRisk == false
        }

        guard rowsToCalculate.isEmpty == false else {
            return ExecutionSummary(
                processedResultIds: processedIds,
                calculatedResultIds: [],
                processedCount: scopeRows.count,
                calculatedCount: 0,
                skippedCount: scopeRows.count
            )
        }

        let updates = rowsToCalculate.compactMap { row -> ResultUpdate? in
            guard let resultId = row.resultId,
                  let clusterWeight = row.clusterWeight,
                  let persistenceFactor = row.f,
                  let etaNN = row.etaNN,
                  let deficitRatio = row.deficitRatio,
                  let calculation = calculate(
                    clusterWeight: clusterWeight,
                    persistenceFactor: persistenceFactor,
                    etaNN: etaNN,
                    deficitRatio: deficitRatio
                  ) else {
                return nil
            }

            return ResultUpdate(
                resultId: resultId,
                riskScore: calculation.score,
                riskZone: calculation.zone
            )
        }

        try await apply(updates: updates, on: database)

        let calculatedIds = Set(updates.map(\.resultId))
        return ExecutionSummary(
            processedResultIds: processedIds,
            calculatedResultIds: calculatedIds,
            processedCount: scopeRows.count,
            calculatedCount: calculatedIds.count,
            skippedCount: scopeRows.count - calculatedIds.count
        )
    }

    func calculate(clusterWeight: Double, persistenceFactor: Double, etaNN: Double, deficitRatio: Double) -> Calculation? {
        guard clusterWeight.isFinite,
              persistenceFactor.isFinite,
              etaNN.isFinite,
              deficitRatio.isFinite,
              (0...1).contains(etaNN) else {
            return nil
        }

        let denominator = 1 + (alpha * etaNN)
        guard denominator.isFinite, denominator > 0 else {
            return nil
        }

        let boundedDeficitRatio = min(max(deficitRatio, 0), 1)
        let rawScore = (clusterWeight + persistenceFactor + (deficitWeight * boundedDeficitRatio)) / denominator
        guard rawScore.isFinite else {
            return nil
        }

        let boundedScore = min(max(rawScore, 0), 1)
        return Calculation(
            score: boundedScore,
            zone: zone(for: boundedScore)
        )
    }

    func zone(for score: Double) -> AttendanceRiskZone {
        if score <= 0.30 {
            return .green
        }
        if score <= 0.70 {
            return .yellow
        }
        return .red
    }
}

private extension AttendanceRiskScoreService {
    struct ResultCandidateRow: Decodable {
        let id: String
        let status: String
        let clusteringStatus: String?
        let clusterWeight: Double?
        let f: Double?
        let etaNN: Double?
        let workNormMinutes: Int?
        let workedMinutes: Int?
        let riskScore: Double?
        let riskZone: String?

        var resultId: UUID? {
            UUID(uuidString: id)
        }

        var isEligibleForRisk: Bool {
            status == AttendanceAnalysisStatus.readyForNextStage.rawValue &&
                clusteringStatus == AttendanceClusteringStatus.readyForNextStage.rawValue &&
                clusterWeight != nil &&
                f != nil &&
                etaNN != nil &&
                deficitRatio != nil
        }

        var hasPersistedRisk: Bool {
            riskScore != nil && (riskZone?.isEmpty == false)
        }

        var deficitRatio: Double? {
            guard let workNormMinutes, workNormMinutes > 0, let workedMinutes else {
                return nil
            }

            let deficitMinutes = max(0, workNormMinutes - workedMinutes)
            return min(max(Double(deficitMinutes) / Double(workNormMinutes), 0), 1)
        }
    }

    struct ResultUpdate {
        let resultId: UUID
        let riskScore: Double
        let riskZone: AttendanceRiskZone
    }

    func loadScopeRows(_ scope: Scope, on database: Database) async throws -> [ResultCandidateRow] {
        switch scope {
        case let .userDay(userId, day):
            return try await rawResultRows(
                sql: database,
                whereClause: """
                results.user_id = UUID_TO_BIN('\(userId.uuidString)')
                AND DATE_FORMAT(results.day, '%Y-%m-%d') = '\(day.stringValue)'
                """,
                orderBy: "results.day ASC"
            )
        case let .day(day):
            return try await rawResultRows(
                sql: database,
                whereClause: "DATE_FORMAT(results.day, '%Y-%m-%d') = '\(day.stringValue)'",
                orderBy: "results.user_id ASC"
            )
        case .allEligible:
            return try await rawResultRows(
                sql: database,
                whereClause: "results.status = '\(AttendanceAnalysisStatus.readyForNextStage.rawValue)'",
                orderBy: "results.user_id ASC, results.day ASC"
            )
        }
    }

    func rawResultRows(sql database: Database, whereClause: String, orderBy: String = "results.user_id ASC, results.day ASC") async throws -> [ResultCandidateRow] {
        if let sqlDatabase = database as? any SQLDatabase {
            return try await sqlDatabase.raw(
                """
                SELECT
                    BIN_TO_UUID(results.id) AS id,
                    results.status AS status,
                    results.clustering_status AS clusteringStatus,
                    results.cluster_weight AS clusterWeight,
                    results.f AS f,
                    results.eta_nn AS etaNN,
                    results.work_norm_minutes AS workNormMinutes,
                    observations.worked_minutes AS workedMinutes,
                    results.risk_score AS riskScore,
                    results.risk_zone AS riskZone
                FROM attendance_analysis_results AS results
                LEFT JOIN attendance_day_observations AS observations
                    ON results.observation_id = observations.id
                WHERE \(unsafeRaw: whereClause)
                ORDER BY \(unsafeRaw: orderBy)
                """
            ).all(decoding: ResultCandidateRow.self)
        }

        let results = try await AttendanceAnalysisResult.query(on: database)
            .sort(\.$userId, .ascending)
            .sort(\.$day, .ascending)
            .all()

        var rows = [ResultCandidateRow]()
        rows.reserveCapacity(results.count)

        for result in results {
            let workedMinutes: Int? = if let observationId = result.observationId {
                try await AttendanceDayObservation.find(observationId, on: database)?.workedMinutes
            } else {
                nil
            }

            rows.append(
                ResultCandidateRow(
                    id: result.id?.uuidString ?? "",
                    status: result.status,
                    clusteringStatus: result.clusteringStatus,
                    clusterWeight: result.clusterWeight,
                    f: result.f,
                    etaNN: result.etaNN,
                    workNormMinutes: result.workNormMinutes,
                    workedMinutes: workedMinutes,
                    riskScore: result.riskScore,
                    riskZone: result.riskZone
                )
            )
        }

        return rows
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
                    result.riskScore = update.riskScore
                    result.riskZone = update.riskZone.rawValue
                    try await result.update(on: transaction)
                }
                return
            }

            try await sqlDatabase.raw("DROP TEMPORARY TABLE IF EXISTS attendance_risk_assignments").run()
            try await sqlDatabase.raw(
                """
                CREATE TEMPORARY TABLE attendance_risk_assignments (
                    result_id CHAR(36) PRIMARY KEY,
                    risk_score DOUBLE NOT NULL,
                    risk_zone VARCHAR(32) NOT NULL
                )
                """
            ).run()

            let batchSize = 1_000
            var startIndex = 0
            while startIndex < updates.count {
                let endIndex = min(startIndex + batchSize, updates.count)
                let batch = updates[startIndex..<endIndex]
                let values = batch.map { update in
                    "('\(escaped(update.resultId.uuidString))', \(update.riskScore), '\(escaped(update.riskZone.rawValue))')"
                }.joined(separator: ", ")

                try await sqlDatabase.raw(
                    """
                    INSERT INTO attendance_risk_assignments (
                        result_id,
                        risk_score,
                        risk_zone
                    )
                    VALUES \(unsafeRaw: values)
                    """
                ).run()

                startIndex = endIndex
            }

            try await sqlDatabase.raw(
                """
                UPDATE attendance_analysis_results AS results
                JOIN attendance_risk_assignments AS assignments
                    ON results.id = UUID_TO_BIN(assignments.result_id)
                SET
                    results.risk_score = assignments.risk_score,
                    results.risk_zone = assignments.risk_zone
                """
            ).run()
        }
    }

    func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
