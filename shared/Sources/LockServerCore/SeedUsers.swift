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

    public static let accessEntries = [
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-23T09:00:00Z"), isOn: true),
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-23T13:00:00Z"), isOn: false),
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-24T10:00:00Z"), isOn: true),
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-24T14:00:00Z"), isOn: false),
        SeedAccessEntry(employerID: admin.id, time: makeDate("2026-04-24T08:30:00Z"), isOn: true),
        SeedAccessEntry(employerID: admin.id, time: makeDate("2026-04-24T12:30:00Z"), isOn: false),
        SeedAccessEntry(employerID: attendanceNormal.id, time: makeDate("2026-04-21T09:00:00Z"), isOn: true),
        SeedAccessEntry(employerID: attendanceNormal.id, time: makeDate("2026-04-21T17:30:00Z"), isOn: false),
        SeedAccessEntry(employerID: attendanceSplit.id, time: makeDate("2026-04-21T08:45:00Z"), isOn: true),
        SeedAccessEntry(employerID: attendanceSplit.id, time: makeDate("2026-04-21T12:00:00Z"), isOn: false),
        SeedAccessEntry(employerID: attendanceSplit.id, time: makeDate("2026-04-21T13:00:00Z"), isOn: true),
        SeedAccessEntry(employerID: attendanceSplit.id, time: makeDate("2026-04-21T18:00:00Z"), isOn: false),
        SeedAccessEntry(employerID: attendanceShort.id, time: makeDate("2026-04-22T10:00:00Z"), isOn: true),
        SeedAccessEntry(employerID: attendanceShort.id, time: makeDate("2026-04-22T15:30:00Z"), isOn: false),
        SeedAccessEntry(employerID: attendanceBroken.id, time: makeDate("2026-04-23T09:15:00Z"), isOn: true),
        SeedAccessEntry(employerID: attendanceCrossMidnight.id, time: makeDate("2026-04-24T22:30:00Z"), isOn: true),
        SeedAccessEntry(employerID: attendanceCrossMidnight.id, time: makeDate("2026-04-25T02:15:00Z"), isOn: false)
    ]

    private static func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
