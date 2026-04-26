import Foundation
import LockServerContracts

public struct SeedUser: Sendable {
    public let id: UUID
    public let email: String
    public let password: String
    public let isAdmin: Bool
    public let name: String
    public let surname: String
    public let department: String
    public let workNormMinutes: Int
    public let cardCode: String?
    public let fingerCode: Int?

    public init(
        id: UUID,
        email: String,
        password: String,
        isAdmin: Bool,
        name: String,
        surname: String,
        department: String,
        workNormMinutes: Int,
        cardCode: String? = nil,
        fingerCode: Int? = nil
    ) {
        self.id = id
        self.email = email
        self.password = password
        self.isAdmin = isAdmin
        self.name = name
        self.surname = surname
        self.department = department
        self.workNormMinutes = workNormMinutes
        self.cardCode = cardCode
        self.fingerCode = fingerCode
    }

    public var employerModel: EmployerModel {
        EmployerModel(
            id: id,
            isAdmin: isAdmin,
            name: name,
            surname: surname,
            department: department,
            email: email,
            workNormMinutes: workNormMinutes,
            hasCard: cardCode != nil,
            hasFinger: fingerCode != nil
        )
    }
}

public struct SeedAccessEntry: Sendable {
    public let employerID: UUID
    public let time: Date
    public let isOn: Bool

    public init(employerID: UUID, time: Date, isOn: Bool) {
        self.employerID = employerID
        self.time = time
        self.isOn = isOn
    }
}

public enum SeedUsers {
    public static let defaultWorkNormMinutes = 480
    public static let attendanceWarmupDays = [
        "2026-04-06",
        "2026-04-07",
        "2026-04-08"
    ]
    public static let materializedAttendanceDays = [
        "2026-04-09",
        "2026-04-10",
        "2026-04-13",
        "2026-04-14",
        "2026-04-15",
        "2026-04-16",
        "2026-04-17",
        "2026-04-20",
        "2026-04-21",
        "2026-04-22"
    ]
    public static let attendanceFixtureDays = attendanceWarmupDays + materializedAttendanceDays

    public static let admin = SeedUser(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        email: "admin@lock.local",
        password: "admin1234",
        isAdmin: true,
        name: "Admin",
        surname: "User",
        department: "Security",
        workNormMinutes: defaultWorkNormMinutes
    )

    public static let user = SeedUser(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        email: "user@lock.local",
        password: "user1234",
        isAdmin: false,
        name: "Test",
        surname: "Employee",
        department: "QA",
        workNormMinutes: defaultWorkNormMinutes,
        cardCode: "E28E892A",
        fingerCode: 1
    )

    public static let attendanceNormal = SeedUser(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        email: "attendance.normal@lock.local",
        password: "normal1234",
        isAdmin: false,
        name: "Alice",
        surname: "Normal",
        department: "Analytics",
        workNormMinutes: defaultWorkNormMinutes
    )

    public static let attendanceSplit = SeedUser(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        email: "attendance.split@lock.local",
        password: "split1234",
        isAdmin: false,
        name: "Bob",
        surname: "Split",
        department: "Operations",
        workNormMinutes: defaultWorkNormMinutes
    )

    public static let attendanceShort = SeedUser(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        email: "attendance.short@lock.local",
        password: "short1234",
        isAdmin: false,
        name: "Cara",
        surname: "Shortday",
        department: "Support",
        workNormMinutes: defaultWorkNormMinutes
    )

    public static let attendanceBroken = SeedUser(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        email: "attendance.broken@lock.local",
        password: "broken1234",
        isAdmin: false,
        name: "Dan",
        surname: "Broken",
        department: "Field",
        workNormMinutes: defaultWorkNormMinutes
    )

    public static let attendanceCrossMidnight = SeedUser(
        id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
        email: "attendance.night@lock.local",
        password: "night1234",
        isAdmin: false,
        name: "Eve",
        surname: "Night",
        department: "Operations",
        workNormMinutes: defaultWorkNormMinutes
    )

    public static let all = [
        admin,
        user,
        attendanceNormal,
        attendanceSplit,
        attendanceShort,
        attendanceBroken,
        attendanceCrossMidnight
    ]

    public static let accessEntries =
        userAccessEntries +
        adminAccessEntries +
        attendanceNormalEntries +
        attendanceSplitEntries +
        attendanceShortEntries +
        attendanceBrokenEntries +
        attendanceCrossMidnightEntries

    private static func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func makeEntries(employerID: UUID, events: [(String, Bool)]) -> [SeedAccessEntry] {
        events.map { SeedAccessEntry(employerID: employerID, time: makeDate($0.0), isOn: $0.1) }
    }

    private static func makeSingleSessionEntries(employerID: UUID, day: String, start: String, end: String) -> [SeedAccessEntry] {
        makeEntries(
            employerID: employerID,
            events: [
                (timestamp(day, start), true),
                (timestamp(day, end), false)
            ]
        )
    }

    private static func makeSplitSessionEntries(
        employerID: UUID,
        day: String,
        firstStart: String,
        firstEnd: String,
        secondStart: String,
        secondEnd: String
    ) -> [SeedAccessEntry] {
        makeEntries(
            employerID: employerID,
            events: [
                (timestamp(day, firstStart), true),
                (timestamp(day, firstEnd), false),
                (timestamp(day, secondStart), true),
                (timestamp(day, secondEnd), false)
            ]
        )
    }

    private static func makeCrossMidnightSessionEntries(
        employerID: UUID,
        startDay: String,
        startTime: String,
        endDay: String,
        endTime: String
    ) -> [SeedAccessEntry] {
        makeEntries(
            employerID: employerID,
            events: [
                (timestamp(startDay, startTime), true),
                (timestamp(endDay, endTime), false)
            ]
        )
    }

    private static func timestamp(_ day: String, _ time: String) -> String {
        "\(day)T\(time):00Z"
    }

    private static let userAccessEntries =
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-06", start: "09:55", end: "18:00") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-07", start: "10:05", end: "18:10") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-08", start: "10:00", end: "18:05") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-09", start: "09:50", end: "17:55") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-10", start: "10:10", end: "18:15") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-13", start: "10:00", end: "18:00") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-14", start: "09:55", end: "18:00") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-15", start: "10:05", end: "18:10") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-16", start: "10:00", end: "18:05") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-17", start: "09:50", end: "17:55") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-20", start: "10:10", end: "18:15") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-21", start: "10:00", end: "18:00") +
        makeSingleSessionEntries(employerID: user.id, day: "2026-04-22", start: "09:55", end: "18:00")

    private static let adminAccessEntries =
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-06", start: "08:35", end: "16:40") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-07", start: "08:30", end: "16:35") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-08", start: "08:40", end: "16:45") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-09", start: "08:35", end: "16:40") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-10", start: "08:30", end: "16:35") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-13", start: "08:40", end: "16:45") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-14", start: "08:35", end: "16:40") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-15", start: "08:30", end: "16:35") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-16", start: "08:40", end: "16:45") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-17", start: "08:35", end: "16:40") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-20", start: "08:30", end: "16:35") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-21", start: "08:40", end: "16:45") +
        makeSingleSessionEntries(employerID: admin.id, day: "2026-04-22", start: "08:35", end: "16:40")

    private static let attendanceNormalEntries =
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-06", start: "09:00", end: "17:02") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-07", start: "09:01", end: "17:03") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-08", start: "08:59", end: "17:01") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-09", start: "09:02", end: "17:04") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-10", start: "08:58", end: "17:00") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-13", start: "09:00", end: "17:02") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-14", start: "09:01", end: "17:03") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-15", start: "08:59", end: "17:01") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-16", start: "09:02", end: "17:04") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-17", start: "08:58", end: "17:00") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-20", start: "09:00", end: "17:02") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-21", start: "09:01", end: "17:03") +
        makeSingleSessionEntries(employerID: attendanceNormal.id, day: "2026-04-22", start: "09:00", end: "17:30")

    private static let attendanceSplitEntries =
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-06", start: "07:50", end: "16:05") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-07", start: "08:20", end: "16:35") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-08", start: "09:00", end: "17:10") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-09", start: "09:40", end: "17:45") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-10", start: "10:05", end: "18:10") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-13", start: "08:10", end: "16:20") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-14", start: "09:15", end: "17:20") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-15", start: "10:10", end: "18:15") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-16", start: "07:45", end: "16:00") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-17", start: "09:30", end: "17:35") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-20", start: "08:55", end: "17:00") +
        makeSingleSessionEntries(employerID: attendanceSplit.id, day: "2026-04-21", start: "09:45", end: "17:50") +
        makeSplitSessionEntries(employerID: attendanceSplit.id, day: "2026-04-22", firstStart: "08:45", firstEnd: "12:00", secondStart: "13:00", secondEnd: "18:00")

    private static let attendanceShortEntries =
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-06", start: "09:00", end: "17:00") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-07", start: "09:05", end: "16:05") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-08", start: "09:10", end: "17:10") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-09", start: "09:00", end: "17:00") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-10", start: "09:05", end: "16:05") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-13", start: "09:10", end: "17:10") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-14", start: "09:00", end: "17:00") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-15", start: "09:20", end: "15:20") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-16", start: "09:05", end: "17:05") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-17", start: "09:10", end: "16:10") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-20", start: "09:25", end: "15:25") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-21", start: "09:00", end: "17:00") +
        makeSingleSessionEntries(employerID: attendanceShort.id, day: "2026-04-22", start: "10:00", end: "15:30")

    private static let attendanceBrokenEntries =
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-06", start: "07:30", end: "15:35") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-07", start: "07:25", end: "15:30") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-08", start: "07:35", end: "15:40") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-09", start: "07:30", end: "15:35") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-10", start: "07:25", end: "15:30") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-13", start: "07:35", end: "15:40") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-14", start: "07:30", end: "15:35") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-15", start: "07:25", end: "15:30") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-16", start: "07:35", end: "15:40") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-17", start: "07:30", end: "15:35") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-20", start: "07:25", end: "15:30") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-21", start: "07:35", end: "15:40") +
        makeSingleSessionEntries(employerID: attendanceBroken.id, day: "2026-04-22", start: "07:30", end: "15:35")

    private static let attendanceCrossMidnightEntries =
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-06", startTime: "22:10", endDay: "2026-04-07", endTime: "06:10") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-07", startTime: "22:20", endDay: "2026-04-08", endTime: "06:20") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-08", startTime: "22:15", endDay: "2026-04-09", endTime: "06:15") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-09", startTime: "22:25", endDay: "2026-04-10", endTime: "06:25") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-10", startTime: "22:30", endDay: "2026-04-11", endTime: "06:30") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-13", startTime: "22:10", endDay: "2026-04-14", endTime: "06:10") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-14", startTime: "22:15", endDay: "2026-04-15", endTime: "06:15") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-15", startTime: "22:20", endDay: "2026-04-16", endTime: "06:20") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-16", startTime: "22:25", endDay: "2026-04-17", endTime: "06:25") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-17", startTime: "22:30", endDay: "2026-04-18", endTime: "06:30") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-20", startTime: "22:10", endDay: "2026-04-21", endTime: "06:10") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-21", startTime: "22:15", endDay: "2026-04-22", endTime: "06:15") +
        makeCrossMidnightSessionEntries(employerID: attendanceCrossMidnight.id, startDay: "2026-04-22", startTime: "22:30", endDay: "2026-04-23", endTime: "02:15")
}
