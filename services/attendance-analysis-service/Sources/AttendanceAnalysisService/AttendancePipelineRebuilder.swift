import Fluent
import Foundation

struct AttendancePipelineRebuildSummary {
    let clusteringModelVersion: Int?
    let clusteredCount: Int
    let technicalOutlierCount: Int
    let mlpModelVersion: String?
    let inferredCount: Int
    let mlpFailedCount: Int
    let riskCalculatedCount: Int
}

struct AttendancePipelineRebuilder {
    private let clusteringService: AttendanceClusteringService
    private let mlpInferenceService: AttendanceMLPInferenceService
    private let riskScoreService: AttendanceRiskScoreService

    init(
        clusteringService: AttendanceClusteringService,
        mlpInferenceService: AttendanceMLPInferenceService,
        riskScoreService: AttendanceRiskScoreService
    ) {
        self.clusteringService = clusteringService
        self.mlpInferenceService = mlpInferenceService
        self.riskScoreService = riskScoreService
    }

    func rebuildAll(on database: Database) async throws -> AttendancePipelineRebuildSummary {
        let clusteringSummary = try await clusteringService.execute(scope: .allEligible, rebuildModel: true, on: database)
        let mlpSummary = try await mlpInferenceService.execute(scope: .allEligible, rebuild: true, on: database)
        let riskSummary = try await riskScoreService.execute(scope: .allEligible, rebuild: true, on: database)

        return AttendancePipelineRebuildSummary(
            clusteringModelVersion: clusteringSummary.modelVersion,
            clusteredCount: clusteringSummary.clusteredCount,
            technicalOutlierCount: clusteringSummary.technicalOutlierCount,
            mlpModelVersion: mlpSummary.modelVersion,
            inferredCount: mlpSummary.inferredCount,
            mlpFailedCount: mlpSummary.failedCount,
            riskCalculatedCount: riskSummary.calculatedCount
        )
    }
}
