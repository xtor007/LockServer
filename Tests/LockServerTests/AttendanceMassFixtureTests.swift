import XCTest
@testable import AttendanceAnalysisService
import LockServerCore
import LockServerContracts

final class AttendanceMassFixtureTests: XCTestCase {
    private let builder = AttendanceObservationBuilder()

    func testMassFixtureMeetsPopulationAndHistoryMinimums() throws {
        XCTAssertEqual(SeedUsers.all.filter(\.isAdmin).count, 1)
        XCTAssertGreaterThanOrEqual(SeedUsers.regularUsers.count, 1_000)
        XCTAssertGreaterThanOrEqual(SeedUsers.materializedAttendanceDays.count, 200)

        let daysByUser = Dictionary(grouping: SeedUsers.accessEntries, by: \.employerID).mapValues { entries in
            Set(entries.filter(\.isOn).map { dayString(from: $0.time) }).count
        }

        for user in SeedUsers.regularUsers {
            XCTAssertGreaterThanOrEqual(daysByUser[user.id] ?? 0, 200, "Expected at least 200 attendance days for \(user.email)")
        }
    }

    func testMassFixtureCoversAllWorkNormsAndBehaviorTypes() throws {
        let norms = Set(SeedUsers.regularUsers.map(\.workNormMinutes))
        XCTAssertEqual(norms, [240, 360, 480])

        let groupedLogs = Dictionary(grouping: SeedUsers.accessEntries, by: \.employerID).mapValues {
            $0.sorted { $0.time < $1.time }.map { EnterModel(isOn: $0.isOn, time: $0.time) }
        }

        let splitUserLogs = groupedLogs[SeedUsers.attendanceSplit.id] ?? []
        let splitHasBreakDay = try SeedUsers.attendanceFixtureDays.contains { day in
            let outcome = builder.build(for: try AttendanceDay(day), logs: splitUserLogs, workNormMinutes: SeedUsers.attendanceSplit.workNormMinutes)
            return (outcome.observation?.sessionsCount ?? 0) > 1 && (outcome.observation?.breakMinutes ?? 0) > 0
        }
        XCTAssertTrue(splitHasBreakDay)

        let nightUserEntries = SeedUsers.accessEntries
            .filter { $0.employerID == SeedUsers.attendanceCrossMidnight.id }
            .sorted { $0.time < $1.time }
        let hasCrossMidnightPair = zip(nightUserEntries, nightUserEntries.dropFirst()).contains { current, next in
            current.isOn && next.isOn == false && dayString(from: current.time) != dayString(from: next.time)
        }
        XCTAssertTrue(hasCrossMidnightPair)
    }
}

private extension AttendanceMassFixtureTests {
    func dayString(from date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
