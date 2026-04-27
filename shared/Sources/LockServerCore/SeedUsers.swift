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
    public static let fourHourWorkNormMinutes = 240
    public static let sixHourWorkNormMinutes = 360
    public static let eightHourWorkNormMinutes = 480
    public static let generatedRegularUserCount = 1000

    public static let attendanceWarmupDays = Array(AttendanceSeedFixtureGenerator.fixtureDayStrings.prefix(3))
    public static let materializedAttendanceDays = Array(AttendanceSeedFixtureGenerator.fixtureDayStrings.dropFirst(attendanceWarmupDays.count))
    public static let attendanceFixtureDays = AttendanceSeedFixtureGenerator.fixtureDayStrings

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
        name: "Taras",
        surname: "Savchuk",
        department: "Operations",
        workNormMinutes: eightHourWorkNormMinutes,
        cardCode: "E28E892A",
        fingerCode: 1
    )

    public static let attendanceNormal = SeedUser(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        email: "attendance.normal@lock.local",
        password: "normal1234",
        isAdmin: false,
        name: "Olena",
        surname: "Kovalenko",
        department: "Analytics",
        workNormMinutes: eightHourWorkNormMinutes
    )

    public static let attendanceSplit = SeedUser(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        email: "attendance.split@lock.local",
        password: "split1234",
        isAdmin: false,
        name: "Maksym",
        surname: "Hrytsenko",
        department: "Customer Success",
        workNormMinutes: eightHourWorkNormMinutes
    )

    public static let attendanceShort = SeedUser(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        email: "attendance.short@lock.local",
        password: "short1234",
        isAdmin: false,
        name: "Iryna",
        surname: "Melnyk",
        department: "Support",
        workNormMinutes: sixHourWorkNormMinutes
    )

    public static let attendanceBroken = SeedUser(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        email: "attendance.broken@lock.local",
        password: "broken1234",
        isAdmin: false,
        name: "Dmytro",
        surname: "Bondar",
        department: "Field Services",
        workNormMinutes: fourHourWorkNormMinutes
    )

    public static let attendanceCrossMidnight = SeedUser(
        id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
        email: "attendance.night@lock.local",
        password: "night1234",
        isAdmin: false,
        name: "Kateryna",
        surname: "Shevchenko",
        department: "Security Operations",
        workNormMinutes: eightHourWorkNormMinutes
    )

    public static let all = [
        admin,
        user,
        attendanceNormal,
        attendanceSplit,
        attendanceShort,
        attendanceBroken,
        attendanceCrossMidnight
    ] + AttendanceSeedFixtureGenerator.makeGeneratedUsers(count: generatedRegularUserCount)

    public static let regularUsers = all.filter { !$0.isAdmin }

    public static let manualInspectionUsers = [
        attendanceNormal,
        attendanceShort,
        attendanceCrossMidnight
    ]

    public static let accessEntries = AttendanceSeedFixtureGenerator.makeAccessEntries(for: regularUsers)
}
