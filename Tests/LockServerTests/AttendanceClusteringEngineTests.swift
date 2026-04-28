import XCTest
@testable import AttendanceAnalysisService

final class AttendanceClusteringEngineTests: XCTestCase {
    private let engine = AttendanceClusteringEngine()

    func testTrainsReusableModelAndAssignsExpectedClusters() throws {
        let model = try engine.train(points: trainingPoints(), version: 1)

        XCTAssertEqual(model.clusters.count, 4)
        XCTAssertEqual(model.normalization.featureSpaceVersion, AttendanceClusteringEngine.featureSpaceVersion)

        let stableAssignment = engine.assign(.init(zS: 1.1, zT: 0.1, f: 0.0), using: model)
        XCTAssertEqual(stableAssignment.clusterName, "Stable Normal")
        XCTAssertEqual(stableAssignment.status, .clusteringTerminalStableNormal)
        XCTAssertEqual(stableAssignment.clusteringStatus, .stableNormalTerminal)
        XCTAssertEqual(stableAssignment.clusterScore, 0)

        let flexibleAssignment = engine.assign(.init(zS: -0.2, zT: 1.95, f: 0.05), using: model)
        XCTAssertEqual(flexibleAssignment.clusterName, "Flexible Normal")
        XCTAssertEqual(flexibleAssignment.status, .readyForNextStage)
        XCTAssertEqual(flexibleAssignment.clusterScore, 0.2)

        let episodicAssignment = engine.assign(.init(zS: -1.55, zT: 0.55, f: 0.15), using: model)
        XCTAssertEqual(episodicAssignment.clusterName, "Episodic Deficit")
        XCTAssertEqual(episodicAssignment.status, .readyForNextStage)
        XCTAssertEqual(episodicAssignment.clusterScore, 0.5)

        let systematicAssignment = engine.assign(.init(zS: -2.75, zT: 1.1, f: 0.85), using: model)
        XCTAssertEqual(systematicAssignment.clusterName, "Systematic Anomaly")
        XCTAssertEqual(systematicAssignment.status, .readyForNextStage)
        XCTAssertEqual(systematicAssignment.clusterScore, 0.8)
    }

    func testMarksPointOutsideAllTrustRadiiAsTechnicalOutlier() throws {
        let model = try engine.train(points: trainingPoints(), version: 4)

        let assignment = engine.assign(.init(zS: -7.5, zT: 7.5, f: 1.0), using: model)

        XCTAssertEqual(assignment.status, .clusteringTechnicalOutlier)
        XCTAssertEqual(assignment.clusteringStatus, .technicalOutlier)
        XCTAssertEqual(assignment.clusterName, AttendanceBehaviorCluster.technicalOutlierName)
        XCTAssertNil(assignment.clusterScore)
        XCTAssertNotNil(assignment.clusteringNotes)
    }

    func testOverworkedLateDayStaysStableBecauseItHasNoTimeDeficit() throws {
        let model = try engine.train(points: trainingPoints(), version: 7)

        let assignment = engine.assign(.init(zS: 0.8, zT: 4.0, f: 0.65), using: model)

        XCTAssertEqual(assignment.clusterName, "Stable Normal")
        XCTAssertEqual(assignment.status, .clusteringTerminalStableNormal)
        XCTAssertEqual(assignment.clusteringStatus, .stableNormalTerminal)
        XCTAssertEqual(assignment.clusterScore, 0)
    }

    func testModerateDeficitWithHugeLateZScoreDoesNotBecomeTechnicalOutlier() throws {
        let model = try engine.train(points: trainingPoints(), version: 8)

        let assignment = engine.assign(.init(zS: -3.0556, zT: 13.4352, f: 0.3333), using: model)

        XCTAssertEqual(assignment.status, .readyForNextStage)
        XCTAssertEqual(assignment.clusteringStatus, .readyForNextStage)
        XCTAssertNotEqual(assignment.clusterName, AttendanceBehaviorCluster.technicalOutlierName)
        XCTAssertNotNil(assignment.clusterScore)
    }
}

private extension AttendanceClusteringEngineTests {
    func trainingPoints() throws -> [AttendanceClusteringEngine.TrainingPoint] {
        let values: [(String, String, Double, Double, Double)] = [
            ("10000000-0000-0000-0000-000000000001", "2026-04-21", 1.0, 0.0, 0.0),
            ("10000000-0000-0000-0000-000000000002", "2026-04-22", 1.3, 0.2, 0.0),
            ("10000000-0000-0000-0000-000000000003", "2026-04-23", 0.9, -0.1, 0.0),
            ("10000000-0000-0000-0000-000000000004", "2026-04-24", 1.1, 0.1, 0.55),
            ("10000000-0000-0000-0000-000000000005", "2026-04-25", 0.8, -0.2, 0.7),
            ("20000000-0000-0000-0000-000000000001", "2026-04-21", -0.25, 1.8, 0.1),
            ("20000000-0000-0000-0000-000000000002", "2026-04-22", -0.1, 1.6, 0.05),
            ("20000000-0000-0000-0000-000000000003", "2026-04-23", -0.35, 2.3, 0.1),
            ("30000000-0000-0000-0000-000000000001", "2026-04-21", -1.4, 0.5, 0.1),
            ("30000000-0000-0000-0000-000000000002", "2026-04-22", -1.8, 0.7, 0.15),
            ("30000000-0000-0000-0000-000000000003", "2026-04-23", -1.2, 0.3, 0.2),
            ("40000000-0000-0000-0000-000000000001", "2026-04-21", -2.9, 1.2, 0.75),
            ("40000000-0000-0000-0000-000000000002", "2026-04-22", -2.6, 0.9, 0.9),
            ("40000000-0000-0000-0000-000000000003", "2026-04-23", -3.1, 1.5, 0.85)
        ]

        return try values.enumerated().map { index, value in
            AttendanceClusteringEngine.TrainingPoint(
                resultId: UUID(uuidString: value.0)!,
                userId: UUID(uuidString: String(format: "90000000-0000-0000-0000-%012d", index + 1))!,
                day: try AttendanceDay(value.1),
                vector: .init(zS: value.2, zT: value.3, f: value.4)
            )
        }
    }
}
