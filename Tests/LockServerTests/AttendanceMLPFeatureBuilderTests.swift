import XCTest
@testable import AttendanceAnalysisService

final class AttendanceMLPFeatureBuilderTests: XCTestCase {
    func testBuildsFeatureVectorInExpectedOrder() throws {
        let vector = try AttendanceMLPFeatureBuilder().build(
            from: .init(
                zS: -1.5,
                zT: 2.25,
                f: 0.4,
                details: makeDetails(
                    airAlertMinutes: 106,
                    trafficScore: 4.1715,
                    powerScore: 0,
                    weatherScore: 0.7
                )
            )
        )

        XCTAssertEqual(
            vector.orderedValues,
            [-1.5, 2.25, 0.4, 106, 4.1715, 0, 0.7]
        )
    }

    func testThrowsWhenRequiredFeatureIsMissing() {
        XCTAssertThrowsError(
            try AttendanceMLPFeatureBuilder().build(
                from: .init(
                    zS: -1.5,
                    zT: 2.25,
                    f: 0.4,
                    details: makeDetails(
                        airAlertMinutes: nil,
                        trafficScore: 4.1715,
                        powerScore: 0,
                        weatherScore: 0.7
                    )
                )
            )
        )
    }
}

private extension AttendanceMLPFeatureBuilderTests {
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
            stddevStartMinutes: 10,
            stddevWorkedMinutes: 20,
            zS: -1.5,
            zT: 2.25,
            f: 0.4,
            calculationNotes: [],
            airAlertIntervals: [],
            airAlertMinutes: airAlertMinutes,
            trafficScore: trafficScore,
            powerScore: powerScore,
            weatherScore: weatherScore,
            weatherContext: nil,
            externalContextNotes: nil
        )
    }
}
