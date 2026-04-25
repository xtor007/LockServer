import XCTest
@testable import LockServerContracts
@testable import LockServerCore

final class StatisticCalculatorTests: XCTestCase {
    func testAverageTimeUsesWholeDayPairs() {
        let formatter = ISO8601DateFormatter()
        let logs = [
            EnterModel(isOn: true, time: formatter.date(from: "2026-04-23T09:00:00Z")!),
            EnterModel(isOn: false, time: formatter.date(from: "2026-04-23T13:00:00Z")!),
            EnterModel(isOn: true, time: formatter.date(from: "2026-04-24T10:00:00Z")!),
            EnterModel(isOn: false, time: formatter.date(from: "2026-04-24T14:00:00Z")!)
        ]

        let average = StatisticCalculator(enters: logs).averageTime

        XCTAssertEqual(average, 4, accuracy: 0.0001)
    }

    func testCardHasherMatchesLegacyHash() {
        XCTAssertEqual(CardCodeHasher.hash("E28E892A"), 67)
    }
}
