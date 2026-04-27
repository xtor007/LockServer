import XCTest
@testable import AccessService
import LockServerContracts
import LockServerCore

final class AccessStatisticsAggregatorTests: XCTestCase {
    func testAggregatorMatchesStatisticCalculatorPerEmployer() {
        let formatter = ISO8601DateFormatter()
        let firstEmployer = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let secondEmployer = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

        let enters = [
            AccessEnter(employerID: firstEmployer, time: formatter.date(from: "2026-04-21T09:00:00Z")!, isOn: true),
            AccessEnter(employerID: firstEmployer, time: formatter.date(from: "2026-04-21T13:00:00Z")!, isOn: false),
            AccessEnter(employerID: firstEmployer, time: formatter.date(from: "2026-04-22T09:30:00Z")!, isOn: true),
            AccessEnter(employerID: firstEmployer, time: formatter.date(from: "2026-04-22T18:00:00Z")!, isOn: false),
            AccessEnter(employerID: secondEmployer, time: formatter.date(from: "2026-04-21T08:45:00Z")!, isOn: true),
            AccessEnter(employerID: secondEmployer, time: formatter.date(from: "2026-04-21T12:15:00Z")!, isOn: false),
            AccessEnter(employerID: secondEmployer, time: formatter.date(from: "2026-04-21T13:00:00Z")!, isOn: true),
            AccessEnter(employerID: secondEmployer, time: formatter.date(from: "2026-04-21T17:30:00Z")!, isOn: false),
            AccessEnter(employerID: secondEmployer, time: formatter.date(from: "2026-04-22T10:00:00Z")!, isOn: true),
            AccessEnter(employerID: secondEmployer, time: formatter.date(from: "2026-04-22T14:00:00Z")!, isOn: false)
        ]

        let aggregator = AccessStatisticsAggregator()
        let averageTimes = aggregator.averageTimes(for: enters, now: formatter.date(from: "2026-04-23T00:00:00Z")!)

        let firstExpected = StatisticCalculator(
            enters: enters
                .filter { $0.employerID == firstEmployer }
                .map { EnterModel(isOn: $0.isOn, time: $0.time) }
        ).averageTime
        let secondExpected = StatisticCalculator(
            enters: enters
                .filter { $0.employerID == secondEmployer }
                .map { EnterModel(isOn: $0.isOn, time: $0.time) }
        ).averageTime

        XCTAssertEqual(averageTimes[firstEmployer] ?? -1, firstExpected, accuracy: 0.0001)
        XCTAssertEqual(averageTimes[secondEmployer] ?? -1, secondExpected, accuracy: 0.0001)
    }
}
