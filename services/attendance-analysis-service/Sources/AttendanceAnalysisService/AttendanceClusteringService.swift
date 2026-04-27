import Fluent
import Foundation
import SQLKit
import Vapor

struct AttendanceClusteringService {
    enum Scope {
        case userDay(UUID, AttendanceDay)
        case day(AttendanceDay)
        case allEligible
    }

    struct ExecutionSummary {
        let modelVersion: Int?
        let processedResultIds: [UUID]
        let clusteredResultIds: Set<UUID>
        let processedCount: Int
        let clusteredCount: Int
        let skippedCount: Int
        let technicalOutlierCount: Int
    }

    private let engine = AttendanceClusteringEngine()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func execute(scope: Scope, rebuildModel: Bool, on database: Database) async throws -> ExecutionSummary {
        let scopeRows = try await loadScopeRows(scope, on: database)
        let processedIds = scopeRows.compactMap(\.resultId)
        guard processedIds.isEmpty == false else {
            return ExecutionSummary(
                modelVersion: try await currentModel(on: database)?.version,
                processedResultIds: [],
                clusteredResultIds: [],
                processedCount: 0,
                clusteredCount: 0,
                skippedCount: 0,
                technicalOutlierCount: 0
            )
        }

        let rowsToProcess = scopeRows.filter { row in
            guard row.isEligibleForClustering else {
                return false
            }
            return rebuildModel || row.isPendingClustering
        }

        guard rowsToProcess.isEmpty == false else {
            return ExecutionSummary(
                modelVersion: try await currentModel(on: database)?.version,
                processedResultIds: processedIds,
                clusteredResultIds: [],
                processedCount: scopeRows.count,
                clusteredCount: 0,
                skippedCount: scopeRows.count,
                technicalOutlierCount: 0
            )
        }

        let model = try await loadOrTrainModel(rebuildModel: rebuildModel, on: database)
        let updates = rowsToProcess.compactMap { row -> ResultUpdate? in
            guard let resultId = row.resultId, let vector = row.vector else {
                return nil
            }

            let assignment = engine.assign(vector, using: model)
            return ResultUpdate(
                resultId: resultId,
                status: assignment.status,
                clusterName: assignment.clusterName,
                clusterScore: assignment.clusterScore,
                clusterWeight: assignment.clusterWeight,
                clusterModelVersion: assignment.clusterModelVersion,
                clusterDistance: assignment.clusterDistance,
                clusteringStatus: assignment.clusteringStatus,
                clusteringNotes: assignment.clusteringNotes
            )
        }

        try await apply(updates: updates, on: database)

        return ExecutionSummary(
            modelVersion: model.version,
            processedResultIds: processedIds,
            clusteredResultIds: Set(updates.map(\.resultId)),
            processedCount: scopeRows.count,
            clusteredCount: updates.count,
            skippedCount: scopeRows.count - updates.count,
            technicalOutlierCount: updates.filter { $0.clusteringStatus == .technicalOutlier }.count
        )
    }
}

private extension AttendanceClusteringService {
    struct ResultCandidateRow: Decodable {
        let id: String
        let userId: String
        let dayString: String
        let status: String
        let clusteringStatus: String?
        let zS: Double?
        let zT: Double?
        let f: Double?

        var resultId: UUID? {
            UUID(uuidString: id)
        }

        var vector: AttendanceClusteringEngine.FeatureVector? {
            guard let zS, let zT, let f else {
                return nil
            }
            return AttendanceClusteringEngine.FeatureVector(zS: zS, zT: zT, f: f)
        }

        var isEligibleForClustering: Bool {
            vector != nil
        }

        var isPendingClustering: Bool {
            guard isEligibleForClustering else {
                return false
            }

            guard let clusteringStatus else {
                return true
            }

            switch AttendanceClusteringStatus(rawValue: clusteringStatus) {
            case .none, .some(.notStarted):
                return true
            case .some(.notApplicable), .some(.readyForNextStage), .some(.stableNormalTerminal), .some(.technicalOutlier):
                return false
            }
        }
    }

    struct ResultUpdate {
        let resultId: UUID
        let status: AttendanceAnalysisStatus
        let clusterName: String
        let clusterScore: Double?
        let clusterWeight: Double?
        let clusterModelVersion: Int
        let clusterDistance: Double
        let clusteringStatus: AttendanceClusteringStatus
        let clusteringNotes: [String]?
    }

    func loadOrTrainModel(rebuildModel: Bool, on database: Database) async throws -> AttendanceClusteringEngine.ModelSnapshot {
        if rebuildModel == false, let currentModel = try await currentModel(on: database) {
            return currentModel
        }

        let trainingPoints = try await loadTrainingPoints(on: database)
        let version = try await nextModelVersion(on: database)
        let model = try engine.train(points: trainingPoints, version: version)
        try await store(model: model, on: database)
        return model
    }

    func currentModel(on database: Database) async throws -> AttendanceClusteringEngine.ModelSnapshot? {
        guard let record = try await AttendanceClusteringModelRecord.query(on: database)
            .sort(\.$modelVersion, .descending)
            .first() else {
            return nil
        }

        return try decodeModel(record)
    }

    func nextModelVersion(on database: Database) async throws -> Int {
        let latestVersion = try await AttendanceClusteringModelRecord.query(on: database)
            .sort(\.$modelVersion, .descending)
            .first()?
            .modelVersion

        return (latestVersion ?? 0) + 1
    }

    func store(model: AttendanceClusteringEngine.ModelSnapshot, on database: Database) async throws {
        let normalizationJson = try encode(model.normalization)
        let centroidsJson = try encode(model.clusters.map(\.centroid))
        let trustRadiiJson = try encode(model.clusters.map(\.trustRadius))
        let definitionsJson = try encode(model.clusters.map {
            AttendanceClusteringEngine.ClusterDefinition(
                behaviorKey: $0.behaviorKey,
                name: $0.name,
                weight: $0.weight
            )
        })

        let record = AttendanceClusteringModelRecord(
            modelVersion: model.version,
            normalizationJson: normalizationJson,
            centroidsJson: centroidsJson,
            trustRadiiJson: trustRadiiJson,
            clusterDefinitionsJson: definitionsJson
        )
        try await record.create(on: database)
    }

    func decodeModel(_ record: AttendanceClusteringModelRecord) throws -> AttendanceClusteringEngine.ModelSnapshot {
        let normalization = try decode(AttendanceClusteringEngine.Normalization.self, from: record.normalizationJson)
        let centroids = try decode([[Double]].self, from: record.centroidsJson)
        let trustRadii = try decode([Double].self, from: record.trustRadiiJson)
        let definitions = try decode([AttendanceClusteringEngine.ClusterDefinition].self, from: record.clusterDefinitionsJson)

        let clusters = zip(zip(definitions, centroids), trustRadii).map { entry in
            let definitionAndCentroid = entry.0
            let definition = definitionAndCentroid.0
            let centroid = definitionAndCentroid.1
            let radius = entry.1

            return AttendanceClusteringEngine.Cluster(
                behaviorKey: definition.behaviorKey,
                name: definition.name,
                weight: definition.weight,
                centroid: centroid,
                trustRadius: radius
            )
        }

        return AttendanceClusteringEngine.ModelSnapshot(
            version: record.modelVersion,
            normalization: normalization,
            clusters: clusters
        )
    }

    func loadTrainingPoints(on database: Database) async throws -> [AttendanceClusteringEngine.TrainingPoint] {
        let sampledRows = try await rawResultRows(
            sql: database,
            whereClause: """
            z_s IS NOT NULL
            AND z_t IS NOT NULL
            AND f IS NOT NULL
            AND status != 'clustering_technical_outlier'
            AND MOD(CRC32(CONCAT(BIN_TO_UUID(user_id), DATE_FORMAT(day, '%Y-%m-%d'))), 20) = 0
            """
        )
        let rows = sampledRows.count >= AttendanceBehaviorCluster.allCases.count
            ? sampledRows
            : try await rawResultRows(
                sql: database,
                whereClause: """
                z_s IS NOT NULL
                AND z_t IS NOT NULL
                AND f IS NOT NULL
                AND status != 'clustering_technical_outlier'
                """
            )

        return try rows.compactMap { row in
            guard let resultId = row.resultId,
                  let userId = UUID(uuidString: row.userId),
                  let vector = row.vector else {
                return nil
            }

            return AttendanceClusteringEngine.TrainingPoint(
                resultId: resultId,
                userId: userId,
                day: try AttendanceDay(row.dayString),
                vector: vector
            )
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
                whereClause: """
                z_s IS NOT NULL
                AND z_t IS NOT NULL
                AND f IS NOT NULL
                """,
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
                    clustering_status AS clusteringStatus,
                    z_s AS zS,
                    z_t AS zT,
                    f AS f
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
                clusteringStatus: result.clusteringStatus,
                zS: result.zS,
                zT: result.zT,
                f: result.f
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
                    result.status = update.status.rawValue
                    result.clusterName = update.clusterName
                    result.clusterScore = update.clusterScore
                    result.clusterWeight = update.clusterWeight
                    result.clusterModelVersion = update.clusterModelVersion
                    result.clusterDistance = update.clusterDistance
                    result.clusteringStatus = update.clusteringStatus.rawValue
                    try await result.update(on: transaction)
                }
                return
            }

            try await sqlDatabase.raw("DROP TEMPORARY TABLE IF EXISTS attendance_clustering_assignments").run()
            try await sqlDatabase.raw(
                """
                CREATE TEMPORARY TABLE attendance_clustering_assignments (
                    result_id CHAR(36) PRIMARY KEY,
                    status VARCHAR(64) NOT NULL,
                    cluster_name VARCHAR(64) NOT NULL,
                    cluster_score DOUBLE NULL,
                    cluster_weight DOUBLE NULL,
                    cluster_model_version INT NOT NULL,
                    cluster_distance DOUBLE NOT NULL,
                    clustering_status VARCHAR(64) NOT NULL
                )
                """
            ).run()

            let batchSize = 1_000
            var startIndex = 0
            while startIndex < updates.count {
                let endIndex = min(startIndex + batchSize, updates.count)
                let batch = updates[startIndex..<endIndex]
                let values = batch.map { update in
                    "('\(escaped(update.resultId.uuidString))', '\(escaped(update.status.rawValue))', '\(escaped(update.clusterName))', \(sqlValue(update.clusterScore)), \(sqlValue(update.clusterWeight)), \(update.clusterModelVersion), \(update.clusterDistance), '\(escaped(update.clusteringStatus.rawValue))')"
                }.joined(separator: ", ")

                try await sqlDatabase.raw(
                    """
                    INSERT INTO attendance_clustering_assignments (
                        result_id,
                        status,
                        cluster_name,
                        cluster_score,
                        cluster_weight,
                        cluster_model_version,
                        cluster_distance,
                        clustering_status
                    )
                    VALUES \(unsafeRaw: values)
                    """
                ).run()

                startIndex = endIndex
            }

            try await sqlDatabase.raw(
                """
                UPDATE attendance_analysis_results AS results
                JOIN attendance_clustering_assignments AS assignments
                    ON results.id = UUID_TO_BIN(assignments.result_id)
                SET
                    results.status = assignments.status,
                    results.cluster_name = assignments.cluster_name,
                    results.cluster_score = assignments.cluster_score,
                    results.cluster_weight = assignments.cluster_weight,
                    results.cluster_model_version = assignments.cluster_model_version,
                    results.cluster_distance = assignments.cluster_distance,
                    results.clustering_status = assignments.clustering_status
                """
            ).run()
        }
    }

    func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to encode clustering model")
        }
        return string
    }

    func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    func sqlValue(_ value: Double?) -> String {
        guard let value else {
            return "NULL"
        }
        return "\(value)"
    }

    func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
