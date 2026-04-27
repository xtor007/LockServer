import Foundation

enum AttendanceSeedFixtureGenerator {
    private enum AttendanceProfile: String {
        case stableOffice
        case flexOffice
        case splitSchedule
        case slightDeficit
        case earlyShift
        case nightSupport
    }

    private struct WorkSession {
        let startMinute: Int
        let endMinute: Int
    }

    static let fixtureDayStrings = makeBusinessDayStrings(from: "2025-06-02", through: "2026-04-24")

    static func makeGeneratedUsers(count: Int) -> [SeedUser] {
        guard count > 0 else {
            return []
        }

        return (1...count).map { index in
            let firstName = firstNames[(index - 1) % firstNames.count]
            let surname = surnames[((index - 1) / firstNames.count) % surnames.count]
            let department = departments[(index * 7) % departments.count]
            let workNormMinutes = workNormMinutes(for: index)
            let emailSlug = "\(slug(firstName)).\(slug(surname)).\(String(format: "%04d", index))"

            return SeedUser(
                id: stableUUID(for: index),
                email: "\(emailSlug)@lock.local",
                password: String(format: "staff%04dpass", index),
                isAdmin: false,
                name: firstName,
                surname: surname,
                department: department,
                workNormMinutes: workNormMinutes
            )
        }
    }

    static func makeAccessEntries(for users: [SeedUser]) -> [SeedAccessEntry] {
        users
            .flatMap(makeAccessEntries)
            .sorted {
                if $0.employerID == $1.employerID {
                    return $0.time < $1.time
                }
                return $0.employerID.uuidString < $1.employerID.uuidString
            }
    }
}

private extension AttendanceSeedFixtureGenerator {
    static let firstNames = [
        "Andrii", "Bohdan", "Danylo", "Daria", "Ihor", "Iryna", "Kateryna", "Khrystyna",
        "Mariia", "Marta", "Maksym", "Mykhailo", "Nataliia", "Oksana", "Oleksandr", "Olena",
        "Roman", "Sofiia", "Taras", "Tetiana", "Viktoriia", "Volodymyr", "Yaroslav", "Yuliia"
    ]

    static let surnames = [
        "Bondar", "Boiko", "Danylchuk", "Havryliuk", "Hnatiuk", "Holub", "Hrytsenko", "Koval",
        "Kovalenko", "Kravchenko", "Marchenko", "Melnyk", "Moroz", "Novak", "Petrenko", "Romanenko",
        "Savchuk", "Shevchenko", "Tkachenko", "Tymoshenko", "Vasylenko", "Yaremchuk", "Zakharchenko", "Zinchenko"
    ]

    static let departments = [
        "Analytics",
        "Customer Success",
        "Facilities",
        "Field Services",
        "Finance",
        "HR",
        "Operations",
        "Product",
        "Security Operations",
        "Support"
    ]

    static let utcTimeZone = TimeZone(secondsFromGMT: 0) ?? .current

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = utcCalendar
        formatter.timeZone = utcTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let fixtureDayStartsByString: [String: Date] = {
        Dictionary(uniqueKeysWithValues: fixtureDayStrings.map { day in
            (day, dayFormatter.date(from: day)!)
        })
    }()

    static let materializedDayStrings = Array(fixtureDayStrings.dropFirst(3))

    static func makeBusinessDayStrings(from start: String, through end: String) -> [String] {
        guard let startDate = dayFormatter.date(from: start),
              let endDate = dayFormatter.date(from: end)
        else {
            return []
        }

        var result = [String]()
        var cursor = startDate

        while cursor <= endDate {
            let weekday = utcCalendar.component(.weekday, from: cursor)
            if weekday != 1 && weekday != 7 {
                result.append(dayFormatter.string(from: cursor))
            }
            cursor = utcCalendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(24 * 60 * 60)
        }

        return result
    }

    static func makeAccessEntries(for user: SeedUser) -> [SeedAccessEntry] {
        let profile = profile(for: user)
        let leaveDays = leaveDaySet(for: user, profile: profile)

        return fixtureDayStrings.flatMap { day -> [SeedAccessEntry] in
            guard leaveDays.contains(day) == false else {
                return []
            }
            return makeAccessEntries(for: user, day: day, profile: profile)
        }
    }

    private static func makeAccessEntries(for user: SeedUser, day: String, profile: AttendanceProfile) -> [SeedAccessEntry] {
        var generator = DeterministicSeededGenerator(seed: DeterministicSeededGenerator.stableSeed(for: "\(user.id.uuidString)|\(day)|\(profile.rawValue)"))
        let startMinute = adjustedStartMinute(for: day, profile: profile, using: &generator)
        let workedMinutes = workedMinutes(for: user.workNormMinutes, profile: profile, using: &generator)
        let sessionCount = sessionCount(for: profile, using: &generator)
        let breakDurations = breakDurations(for: profile, sessionCount: sessionCount, using: &generator)
        let sessions = makeSessions(
            startMinute: startMinute,
            workedMinutes: workedMinutes,
            breakDurations: breakDurations,
            profile: profile,
            using: &generator
        )

        return sessions.flatMap { session in
            let start = timestamp(day: day, minuteOfDay: session.startMinute)
            let end = timestamp(day: day, minuteOfDay: session.endMinute)
            return [
                SeedAccessEntry(employerID: user.id, time: start, isOn: true),
                SeedAccessEntry(employerID: user.id, time: end, isOn: false)
            ]
        }
    }

    private static func profile(for user: SeedUser) -> AttendanceProfile {
        switch user.email {
        case "user@lock.local":
            return .flexOffice
        case "attendance.normal@lock.local":
            return .stableOffice
        case "attendance.split@lock.local":
            return .splitSchedule
        case "attendance.short@lock.local":
            return .slightDeficit
        case "attendance.broken@lock.local":
            return .earlyShift
        case "attendance.night@lock.local":
            return .nightSupport
        default:
            let seed = DeterministicSeededGenerator.stableSeed(for: user.id.uuidString)
            switch user.workNormMinutes {
            case SeedUsers.fourHourWorkNormMinutes:
                return seed.isMultiple(of: 3) ? .earlyShift : .slightDeficit
            case SeedUsers.sixHourWorkNormMinutes:
                switch seed % 3 {
                case 0:
                    return .splitSchedule
                case 1:
                    return .slightDeficit
                default:
                    return .flexOffice
                }
            default:
                switch seed % 5 {
                case 0:
                    return .stableOffice
                case 1:
                    return .flexOffice
                case 2:
                    return .splitSchedule
                case 3:
                    return .slightDeficit
                default:
                    return .nightSupport
                }
            }
        }
    }

    private static func workNormMinutes(for index: Int) -> Int {
        switch index % 10 {
        case 0, 1:
            return SeedUsers.fourHourWorkNormMinutes
        case 2, 3, 4:
            return SeedUsers.sixHourWorkNormMinutes
        default:
            return SeedUsers.eightHourWorkNormMinutes
        }
    }

    private static func leaveDaySet(for user: SeedUser, profile: AttendanceProfile) -> Set<String> {
        var generator = DeterministicSeededGenerator(seed: DeterministicSeededGenerator.stableSeed(for: "leave|\(user.id.uuidString)|\(profile.rawValue)"))
        let absenceCount = absenceCount(for: profile, using: &generator)
        guard absenceCount > 0 else {
            return []
        }

        var leaveDays = Set<String>()
        let candidates = Array(materializedDayStrings.dropFirst(5))

        while leaveDays.count < absenceCount && leaveDays.count < candidates.count {
            let startIndex = Int.random(in: 0..<candidates.count, using: &generator)
            let blockLength = Int.random(in: 1...4, using: &generator)

            for offset in 0..<blockLength {
                guard leaveDays.count < absenceCount else {
                    break
                }
                let candidateIndex = startIndex + offset
                guard candidates.indices.contains(candidateIndex) else {
                    break
                }
                leaveDays.insert(candidates[candidateIndex])
            }
        }

        return leaveDays
    }

    private static func absenceCount(for profile: AttendanceProfile, using generator: inout DeterministicSeededGenerator) -> Int {
        switch profile {
        case .stableOffice:
            return Int.random(in: 7...11, using: &generator)
        case .flexOffice:
            return Int.random(in: 9...14, using: &generator)
        case .splitSchedule:
            return Int.random(in: 8...13, using: &generator)
        case .slightDeficit:
            return Int.random(in: 6...10, using: &generator)
        case .earlyShift:
            return Int.random(in: 5...9, using: &generator)
        case .nightSupport:
            return Int.random(in: 8...12, using: &generator)
        }
    }

    private static func adjustedStartMinute(for day: String, profile: AttendanceProfile, using generator: inout DeterministicSeededGenerator) -> Int {
        let weekdayBias = weekdayBias(for: day, profile: profile)
        let baseStart = baseStartMinute(for: profile, using: &generator) + weekdayBias
        let roll = Int.random(in: 0..<100, using: &generator)

        let adjustedStart: Int
        switch profile {
        case .stableOffice:
            if roll < 10 {
                adjustedStart = baseStart + Int.random(in: 25...70, using: &generator)
            } else if roll < 18 {
                adjustedStart = baseStart - Int.random(in: 20...45, using: &generator)
            } else {
                adjustedStart = baseStart
            }
        case .flexOffice, .splitSchedule:
            if roll < 18 {
                adjustedStart = baseStart + Int.random(in: 30...95, using: &generator)
            } else if roll < 28 {
                adjustedStart = baseStart - Int.random(in: 20...60, using: &generator)
            } else {
                adjustedStart = baseStart
            }
        case .slightDeficit:
            if roll < 22 {
                adjustedStart = baseStart + Int.random(in: 20...80, using: &generator)
            } else {
                adjustedStart = baseStart
            }
        case .earlyShift:
            if roll < 14 {
                adjustedStart = baseStart + Int.random(in: 10...35, using: &generator)
            } else {
                adjustedStart = baseStart
            }
        case .nightSupport:
            if roll < 20 {
                adjustedStart = baseStart + Int.random(in: 15...70, using: &generator)
            } else if roll < 30 {
                adjustedStart = baseStart - Int.random(in: 20...40, using: &generator)
            } else {
                adjustedStart = baseStart
            }
        }

        return max(adjustedStart, 0)
    }

    private static func baseStartMinute(for profile: AttendanceProfile, using generator: inout DeterministicSeededGenerator) -> Int {
        switch profile {
        case .stableOffice:
            return Int.random(in: 8 * 60 + 35...9 * 60 + 10, using: &generator)
        case .flexOffice:
            return Int.random(in: 8 * 60 + 10...10 * 60 + 5, using: &generator)
        case .splitSchedule:
            return Int.random(in: 7 * 60 + 45...10 * 60 + 20, using: &generator)
        case .slightDeficit:
            return Int.random(in: 8 * 60 + 50...10 * 60 + 30, using: &generator)
        case .earlyShift:
            return Int.random(in: 5 * 60 + 50...7 * 60 + 10, using: &generator)
        case .nightSupport:
            return Int.random(in: 17 * 60 + 20...20 * 60 + 15, using: &generator)
        }
    }

    private static func weekdayBias(for day: String, profile: AttendanceProfile) -> Int {
        guard let dayDate = fixtureDayStartsByString[day] else {
            return 0
        }

        switch utcCalendar.component(.weekday, from: dayDate) {
        case 2:
            return profile == .nightSupport ? 20 : 12
        case 6:
            return profile == .nightSupport ? -10 : -8
        default:
            return 0
        }
    }

    private static func workedMinutes(for workNormMinutes: Int, profile: AttendanceProfile, using generator: inout DeterministicSeededGenerator) -> Int {
        let roll = Int.random(in: 0..<100, using: &generator)
        let delta: Int

        switch profile {
        case .stableOffice:
            switch roll {
            case 0..<68:
                delta = Int.random(in: -10...35, using: &generator)
            case 68..<86:
                delta = Int.random(in: 35...90, using: &generator)
            default:
                delta = -Int.random(in: 20...75, using: &generator)
            }
        case .flexOffice:
            switch roll {
            case 0..<55:
                delta = Int.random(in: -20...30, using: &generator)
            case 55..<78:
                delta = -Int.random(in: 25...80, using: &generator)
            default:
                delta = Int.random(in: 35...100, using: &generator)
            }
        case .splitSchedule:
            switch roll {
            case 0..<48:
                delta = Int.random(in: -20...35, using: &generator)
            case 48..<75:
                delta = -Int.random(in: 20...70, using: &generator)
            default:
                delta = Int.random(in: 40...110, using: &generator)
            }
        case .slightDeficit:
            switch roll {
            case 0..<58:
                delta = -Int.random(in: 15...70, using: &generator)
            case 58..<82:
                delta = Int.random(in: -10...20, using: &generator)
            case 82..<92:
                delta = -Int.random(in: 70...120, using: &generator)
            default:
                delta = Int.random(in: 25...75, using: &generator)
            }
        case .earlyShift:
            switch roll {
            case 0..<64:
                delta = Int.random(in: -5...25, using: &generator)
            case 64..<84:
                delta = -Int.random(in: 10...45, using: &generator)
            default:
                delta = Int.random(in: 25...85, using: &generator)
            }
        case .nightSupport:
            switch roll {
            case 0..<52:
                delta = Int.random(in: -15...45, using: &generator)
            case 52..<78:
                delta = Int.random(in: 45...130, using: &generator)
            default:
                delta = -Int.random(in: 20...80, using: &generator)
            }
        }

        return max(workNormMinutes + delta, max(workNormMinutes / 2, 120))
    }

    private static func sessionCount(for profile: AttendanceProfile, using generator: inout DeterministicSeededGenerator) -> Int {
        let roll = Int.random(in: 0..<100, using: &generator)

        switch profile {
        case .stableOffice:
            return roll < 12 ? 2 : 1
        case .flexOffice:
            if roll < 26 {
                return 2
            }
            return 1
        case .splitSchedule:
            if roll < 55 {
                return 2
            }
            if roll < 68 {
                return 3
            }
            return 1
        case .slightDeficit:
            if roll < 32 {
                return 2
            }
            return 1
        case .earlyShift:
            if roll < 24 {
                return 2
            }
            return 1
        case .nightSupport:
            if roll < 18 {
                return 2
            }
            if roll < 24 {
                return 3
            }
            return 1
        }
    }

    private static func breakDurations(for profile: AttendanceProfile, sessionCount: Int, using generator: inout DeterministicSeededGenerator) -> [Int] {
        guard sessionCount > 1 else {
            return []
        }

        return (0..<(sessionCount - 1)).map { _ in
            switch profile {
            case .stableOffice, .flexOffice:
                return Int.random(in: 25...55, using: &generator)
            case .splitSchedule:
                return Int.random(in: 25...80, using: &generator)
            case .slightDeficit:
                return Int.random(in: 20...50, using: &generator)
            case .earlyShift:
                return Int.random(in: 15...35, using: &generator)
            case .nightSupport:
                return Int.random(in: 15...45, using: &generator)
            }
        }
    }

    private static func makeSessions(
        startMinute: Int,
        workedMinutes: Int,
        breakDurations: [Int],
        profile: AttendanceProfile,
        using generator: inout DeterministicSeededGenerator
    ) -> [WorkSession] {
        let sessionCount = max(breakDurations.count + 1, 1)
        let durations = workedDurations(totalWorkedMinutes: workedMinutes, sessionCount: sessionCount, profile: profile, using: &generator)

        var sessions = [WorkSession]()
        sessions.reserveCapacity(sessionCount)

        var cursor = startMinute
        for index in 0..<sessionCount {
            let duration = durations[index]
            sessions.append(WorkSession(startMinute: cursor, endMinute: cursor + duration))
            cursor += duration
            if index < breakDurations.count {
                cursor += breakDurations[index]
            }
        }

        return sessions
    }

    private static func workedDurations(
        totalWorkedMinutes: Int,
        sessionCount: Int,
        profile: AttendanceProfile,
        using generator: inout DeterministicSeededGenerator
    ) -> [Int] {
        guard sessionCount > 1 else {
            return [totalWorkedMinutes]
        }

        var shares: [Double]
        switch (profile, sessionCount) {
        case (.splitSchedule, 2):
            shares = [Double.random(in: 0.43...0.58, using: &generator), 0]
        case (.splitSchedule, 3):
            let first = Double.random(in: 0.34...0.45, using: &generator)
            let second = Double.random(in: 0.18...0.30, using: &generator)
            shares = [first, second, 0]
        case (.nightSupport, 2):
            shares = [Double.random(in: 0.48...0.60, using: &generator), 0]
        case (.nightSupport, 3):
            let first = Double.random(in: 0.38...0.48, using: &generator)
            let second = Double.random(in: 0.18...0.26, using: &generator)
            shares = [first, second, 0]
        default:
            if sessionCount == 2 {
                shares = [Double.random(in: 0.46...0.62, using: &generator), 0]
            } else {
                let first = Double.random(in: 0.36...0.48, using: &generator)
                let second = Double.random(in: 0.18...0.28, using: &generator)
                shares = [first, second, 0]
            }
        }

        if sessionCount == 2 {
            let firstDuration = max(Int((Double(totalWorkedMinutes) * shares[0]).rounded()), 60)
            return [firstDuration, max(totalWorkedMinutes - firstDuration, 45)]
        }

        let firstDuration = max(Int((Double(totalWorkedMinutes) * shares[0]).rounded()), 50)
        let secondDuration = max(Int((Double(totalWorkedMinutes) * shares[1]).rounded()), 35)
        let thirdDuration = max(totalWorkedMinutes - firstDuration - secondDuration, 35)
        return [firstDuration, secondDuration, thirdDuration]
    }

    private static func timestamp(day: String, minuteOfDay: Int) -> Date {
        let dayStart = fixtureDayStartsByString[day] ?? Date()
        return dayStart.addingTimeInterval(TimeInterval(minuteOfDay * 60))
    }

    private static func stableUUID(for index: Int) -> UUID {
        UUID(uuidString: String(format: "90000000-0000-0000-0000-%012llx", UInt64(index)))!
    }

    private static func slug(_ value: String) -> String {
        value.lowercased()
    }
}
