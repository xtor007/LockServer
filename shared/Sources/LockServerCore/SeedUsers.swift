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
    public static let admin = SeedUser(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        email: "admin@lock.local",
        password: "admin1234",
        isAdmin: true,
        name: "Admin",
        surname: "User",
        department: "Security"
    )

    public static let user = SeedUser(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        email: "user@lock.local",
        password: "user1234",
        isAdmin: false,
        name: "Test",
        surname: "Employee",
        department: "QA",
        cardCode: "E28E892A",
        fingerCode: 1
    )

    public static let all = [admin, user]

    public static let accessEntries = [
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-23T09:00:00Z"), isOn: true),
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-23T13:00:00Z"), isOn: false),
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-24T10:00:00Z"), isOn: true),
        SeedAccessEntry(employerID: user.id, time: makeDate("2026-04-24T14:00:00Z"), isOn: false),
        SeedAccessEntry(employerID: admin.id, time: makeDate("2026-04-24T08:30:00Z"), isOn: true),
        SeedAccessEntry(employerID: admin.id, time: makeDate("2026-04-24T12:30:00Z"), isOn: false)
    ]

    private static func makeDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
