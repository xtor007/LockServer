import Foundation
import Vapor

public struct ValidServerResponse: Content, Equatable {
    public let isValid: Bool

    public init(isValid: Bool) {
        self.isValid = isValid
    }
}

public struct AuthTokens: Content, Equatable {
    public let auth: String
    public let refresh: String
    public let expDate: Date

    public init(auth: String, refresh: String, expDate: Date) {
        self.auth = auth
        self.refresh = refresh
        self.expDate = expDate
    }
}

public struct ChangePasswordEmail: Content, Equatable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

public struct ChangePasswordCode: Content, Equatable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public struct PasswordContainer: Content, Equatable {
    public let password: String

    public init(password: String) {
        self.password = password
    }
}

public struct EmployerModel: Content, Equatable {
    public let id: UUID?
    public let isAdmin: Bool
    public let name: String?
    public let surname: String?
    public let department: String?
    public let email: String?
    public let workNormMinutes: Int?
    public var hasCard: Bool?
    public var hasFinger: Bool?

    public init(
        id: UUID?,
        isAdmin: Bool,
        name: String?,
        surname: String?,
        department: String?,
        email: String?,
        workNormMinutes: Int?,
        hasCard: Bool?,
        hasFinger: Bool?
    ) {
        self.id = id
        self.isAdmin = isAdmin
        self.name = name
        self.surname = surname
        self.department = department
        self.email = email
        self.workNormMinutes = workNormMinutes
        self.hasCard = hasCard
        self.hasFinger = hasFinger
    }
}

public struct Employers: Content, Equatable {
    public let employers: [EmployerWithStatistic]

    public init(employers: [EmployerWithStatistic]) {
        self.employers = employers
    }
}

public struct EmployerWithStatistic: Content, Equatable {
    public let employer: EmployerModel
    public let statistic: Statistic

    public init(employer: EmployerModel, statistic: Statistic) {
        self.employer = employer
        self.statistic = statistic
    }
}

public struct Logs: Content, Equatable {
    public let logs: [EnterModel]

    public init(logs: [EnterModel]) {
        self.logs = logs
    }
}

public struct EnterModel: Content, Equatable {
    public let isOn: Bool
    public let time: Date

    public init(isOn: Bool, time: Date) {
        self.isOn = isOn
        self.time = time
    }
}

public struct Statistic: Content, Equatable {
    public let averageTime: Double

    public init(averageTime: Double) {
        self.averageTime = averageTime
    }
}

public struct OpeningResult: Content, Equatable {
    public let isSuccess: Bool

    public init(isSuccess: Bool) {
        self.isSuccess = isSuccess
    }
}

public struct GetLogsRequest: Content, Equatable {
    public let valid: Bool?
    public let id: UUID?
    public let afterDate: Date?

    public init(valid: Bool?, id: UUID?, afterDate: Date?) {
        self.valid = valid
        self.id = id
        self.afterDate = afterDate
    }
}
