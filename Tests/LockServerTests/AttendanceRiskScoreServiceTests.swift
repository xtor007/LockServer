import XCTest
@testable import AttendanceAnalysisService

final class AttendanceRiskScoreServiceTests: XCTestCase {
    func testCalculatesBoundedRiskScoreUsingConfiguredAlpha() throws {
        let service = AttendanceRiskScoreService(alpha: 1, deficitWeight: 2)

        let calculation = service.calculate(
            clusterWeight: 0.5,
            persistenceFactor: 0.4,
            etaNN: 0.8,
            deficitRatio: 0
        )

        let unwrappedCalculation = try XCTUnwrap(calculation)
        XCTAssertEqual(unwrappedCalculation.score, 0.5, accuracy: 0.0001)
        XCTAssertEqual(unwrappedCalculation.zone, .yellow)
    }

    func testClampsRiskScoreIntoUnitInterval() throws {
        let service = AttendanceRiskScoreService(alpha: 0, deficitWeight: 2)

        let calculation = service.calculate(
            clusterWeight: 0.8,
            persistenceFactor: 0.7,
            etaNN: 0.2,
            deficitRatio: 1
        )

        let unwrappedCalculation = try XCTUnwrap(calculation)
        XCTAssertEqual(unwrappedCalculation.score, 1)
        XCTAssertEqual(unwrappedCalculation.zone, .red)
    }

    func testAssignsZonesAtAlgorithmThresholds() {
        let service = AttendanceRiskScoreService(alpha: 1, deficitWeight: 2)

        XCTAssertEqual(service.zone(for: 0.30), .green)
        XCTAssertEqual(service.zone(for: 0.31), .yellow)
        XCTAssertEqual(service.zone(for: 0.70), .yellow)
        XCTAssertEqual(service.zone(for: 0.71), .red)
    }

    func testRejectsInvalidEtaNN() {
        let service = AttendanceRiskScoreService(alpha: 1, deficitWeight: 2)

        XCTAssertNil(service.calculate(clusterWeight: 0.5, persistenceFactor: 0.2, etaNN: -0.1, deficitRatio: 0.1))
        XCTAssertNil(service.calculate(clusterWeight: 0.5, persistenceFactor: 0.2, etaNN: 1.1, deficitRatio: 0.1))
    }

    func testDeficitRatioPullsUpLongUnderworkIntoHigherRiskBand() throws {
        let service = AttendanceRiskScoreService(alpha: 1, deficitWeight: 2)

        let calculation = service.calculate(
            clusterWeight: 0.2,
            persistenceFactor: 0.3333,
            etaNN: 0.056025,
            deficitRatio: 73.0 / 480.0
        )

        let unwrappedCalculation = try XCTUnwrap(calculation)
        XCTAssertEqual(unwrappedCalculation.score, 0.7931, accuracy: 0.0001)
        XCTAssertEqual(unwrappedCalculation.zone, .red)
    }
}
