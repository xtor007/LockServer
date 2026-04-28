import XCTest
import Vapor
@testable import AttendanceAnalysisService

final class AttendanceMLPFeedbackServiceTests: XCTestCase {
    func testBuildsFeedbackSnapshotFromStoredResult() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let service = AttendanceMLPFeedbackService(
            client: AttendanceMLPServiceClient(client: app.client, baseURL: "http://127.0.0.1:8087")
        )
        let result = AttendanceAnalysisResult(
            userId: UUID(),
            day: try AttendanceDay("2026-04-28").startOfDay,
            status: AttendanceAnalysisStatus.readyForNextStage.rawValue,
            observationId: nil,
            historyDaysUsed: 3,
            averageStartMinutes: 540,
            stddevStartMinutes: 12,
            stddevWorkedMinutes: 24,
            workNormMinutes: 480,
            zS: -1.25,
            zT: 2.5,
            f: 0.4,
            clusterName: "episodic_deficit",
            clusterScore: 0.52,
            clusterWeight: 0.5,
            clusterModelVersion: 2,
            clusterDistance: 0.31,
            clusteringStatus: AttendanceClusteringStatus.readyForNextStage.rawValue,
            etaNN: 0.58,
            mlpModelVersion: "attendance-mlp-old",
            mlpStatus: AttendanceMLPStatus.ready.rawValue,
            detailsJson: try encodeDetails(
                makeDetails(
                    airAlertMinutes: 106,
                    trafficScore: 4.1715,
                    powerScore: 1,
                    weatherScore: 0.7
                )
            )
        )

        let snapshot = try service.makeFeedbackSnapshot(from: result, correctedEtaNN: 0.63)

        XCTAssertEqual(snapshot.zS, -1.25)
        XCTAssertEqual(snapshot.zT, 2.5)
        XCTAssertEqual(snapshot.f, 0.4)
        XCTAssertEqual(snapshot.airAlertMinutes, 106)
        XCTAssertEqual(snapshot.trafficScore, 4.1715)
        XCTAssertEqual(snapshot.powerScore, 1)
        XCTAssertEqual(snapshot.weatherScore, 0.7)
        XCTAssertEqual(snapshot.etaNNTarget, 0.63)
        XCTAssertEqual(snapshot.sourceModelVersion, "attendance-mlp-old")
    }

    func testThrowsWhenSourceModelVersionMissing() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        let service = AttendanceMLPFeedbackService(
            client: AttendanceMLPServiceClient(client: app.client, baseURL: "http://127.0.0.1:8087")
        )
        let result = AttendanceAnalysisResult(
            userId: UUID(),
            day: try AttendanceDay("2026-04-28").startOfDay,
            status: AttendanceAnalysisStatus.readyForNextStage.rawValue,
            observationId: nil,
            historyDaysUsed: 3,
            averageStartMinutes: 540,
            stddevStartMinutes: 12,
            stddevWorkedMinutes: 24,
            workNormMinutes: 480,
            zS: -1.25,
            zT: 2.5,
            f: 0.4,
            clusterName: "episodic_deficit",
            clusterScore: 0.52,
            clusterWeight: 0.5,
            clusterModelVersion: 2,
            clusterDistance: 0.31,
            clusteringStatus: AttendanceClusteringStatus.readyForNextStage.rawValue,
            etaNN: 0.58,
            mlpModelVersion: nil,
            mlpStatus: AttendanceMLPStatus.ready.rawValue,
            detailsJson: try encodeDetails(
                makeDetails(
                    airAlertMinutes: 106,
                    trafficScore: 4.1715,
                    powerScore: 1,
                    weatherScore: 0.7
                )
            )
        )

        XCTAssertThrowsError(try service.makeFeedbackSnapshot(from: result, correctedEtaNN: 0.63))
    }
}

private extension AttendanceMLPFeedbackServiceTests {
    func makeDetails(
        airAlertMinutes: Int?,
        trafficScore: Double?,
        powerScore: Double?,
        weatherScore: Double?
    ) -> AttendanceAnalysisDebugDetails {
        AttendanceAnalysisDebugDetails(
            workNormMinutes: 480,
            rawEventCount: 0,
            rawEvents: [],
            sessionStartsCount: 0,
            completedSessionsCount: 0,
            sessionRanges: [],
            anomalyReasons: [],
            note: nil,
            baselineWindowDays: 3,
            historyDaysUsed: 3,
            baselineHistoryDays: [],
            deficitHistoryDaysCount: 1,
            averageStartMinutes: 540,
            stddevStartMinutes: 12,
            stddevWorkedMinutes: 24,
            zS: -1.25,
            zT: 2.5,
            f: 0.4,
            calculationNotes: [],
            airAlertIntervals: [],
            airAlertMinutes: airAlertMinutes,
            trafficScore: trafficScore,
            powerScore: powerScore,
            weatherScore: weatherScore,
            weatherContext: nil,
            externalContextNotes: nil,
            clusterName: "episodic_deficit",
            clusterScore: 0.52,
            clusterWeight: 0.5,
            clusterModelVersion: 2,
            clusterDistance: 0.31,
            clusteringStatus: AttendanceClusteringStatus.readyForNextStage.rawValue,
            clusteringNotes: []
        )
    }

    func encodeDetails(_ details: AttendanceAnalysisDebugDetails) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(details)
        guard let string = String(data: data, encoding: .utf8) else {
            throw XCTSkip("Failed to encode debug details")
        }
        return string
    }
}
