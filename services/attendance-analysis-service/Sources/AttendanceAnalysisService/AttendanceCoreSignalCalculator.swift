import Foundation

struct AttendanceCoreSignalCalculator {
    struct ObservationInput {
        let day: AttendanceDay
        let firstEntryTime: Date
        let workedMinutes: Int

        var startMinutes: Int {
            let components = AttendanceCoreSignalCalculator.calendar.dateComponents([.hour, .minute], from: firstEntryTime)
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    struct Snapshot {
        let historyDaysUsed: Int
        let averageStartMinutes: Double?
        let stddevStartMinutes: Double?
        let stddevWorkedMinutes: Double?
        let workNormMinutes: Int
        let zS: Double?
        let zT: Double?
        let f: Double?
    }

    struct Debug {
        let baselineWindowDays: Int
        let historyDays: [AttendanceBaselineHistoryDebugDay]
        let deficitHistoryDaysCount: Int
        let calculationNotes: [String]
    }

    struct Output {
        let status: AttendanceAnalysisStatus
        let snapshot: Snapshot
        let debug: Debug
    }

    private let baselineWindowDays: Int
    private let zeroVarianceZScoreMagnitude = 8.0

    init(baselineWindowDays: Int) {
        self.baselineWindowDays = max(baselineWindowDays, 1)
    }

    func calculate(target: ObservationInput, history: [ObservationInput], workNormMinutes: Int) -> Output {
        let recentHistory = Array(
            history
                .sorted { $0.day > $1.day }
                .prefix(baselineWindowDays)
                .sorted { $0.day < $1.day }
        )
        let deficitHistoryDaysCount = recentHistory.filter { $0.workedMinutes < workNormMinutes }.count
        let historyDays = recentHistory.map {
            AttendanceBaselineHistoryDebugDay(
                day: $0.day.stringValue,
                firstEntryTime: $0.firstEntryTime,
                startMinutes: $0.startMinutes,
                workedMinutes: $0.workedMinutes,
                isDeficit: $0.workedMinutes < workNormMinutes
            )
        }

        guard recentHistory.count >= baselineWindowDays else {
            return Output(
                status: .insufficientHistory,
                snapshot: Snapshot(
                    historyDaysUsed: recentHistory.count,
                    averageStartMinutes: nil,
                    stddevStartMinutes: nil,
                    stddevWorkedMinutes: nil,
                    workNormMinutes: workNormMinutes,
                    zS: nil,
                    zT: nil,
                    f: nil
                ),
                debug: Debug(
                    baselineWindowDays: baselineWindowDays,
                    historyDays: historyDays,
                    deficitHistoryDaysCount: deficitHistoryDaysCount,
                    calculationNotes: [
                        "insufficient_history:expected_\(baselineWindowDays):found_\(recentHistory.count)"
                    ]
                )
            )
        }

        let startMinutes = recentHistory.map { Double($0.startMinutes) }
        let workedMinutes = recentHistory.map { Double($0.workedMinutes) }
        let averageStartMinutes = round(mean(startMinutes))
        let stddevStartMinutes = round(populationStandardDeviation(startMinutes))
        let stddevWorkedMinutes = round(populationStandardDeviation(workedMinutes))

        var calculationNotes = [String]()
        let zS = round(
            zScore(
                value: Double(target.workedMinutes),
                reference: Double(workNormMinutes),
                stddev: stddevWorkedMinutes,
                label: "z_s",
                notes: &calculationNotes
            )
        )
        let zT = round(
            zScore(
                value: Double(target.startMinutes),
                reference: averageStartMinutes,
                stddev: stddevStartMinutes,
                label: "z_t",
                notes: &calculationNotes
            )
        )
        let f = round(Double(deficitHistoryDaysCount) / Double(recentHistory.count))

        return Output(
            status: .signalsReady,
            snapshot: Snapshot(
                historyDaysUsed: recentHistory.count,
                averageStartMinutes: averageStartMinutes,
                stddevStartMinutes: stddevStartMinutes,
                stddevWorkedMinutes: stddevWorkedMinutes,
                workNormMinutes: workNormMinutes,
                zS: zS,
                zT: zT,
                f: f
            ),
            debug: Debug(
                baselineWindowDays: baselineWindowDays,
                historyDays: historyDays,
                deficitHistoryDaysCount: deficitHistoryDaysCount,
                calculationNotes: calculationNotes
            )
        )
    }
}

private extension AttendanceCoreSignalCalculator {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(abbreviation: "UTC")!
        return calendar
    }()

    func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    func populationStandardDeviation(_ values: [Double]) -> Double {
        let meanValue = mean(values)
        let variance = values.reduce(0) { partialResult, value in
            partialResult + pow(value - meanValue, 2)
        } / Double(values.count)
        return sqrt(variance)
    }

    func zScore(
        value: Double,
        reference: Double,
        stddev: Double,
        label: String,
        notes: inout [String]
    ) -> Double {
        let delta = value - reference
        guard stddev > 0 else {
            guard delta != 0 else {
                return 0
            }

            notes.append("\(label)_used_zero_variance_cap")
            return delta > 0 ? zeroVarianceZScoreMagnitude : -zeroVarianceZScoreMagnitude
        }

        return delta / stddev
    }

    func round(_ value: Double, scale: Double = 10_000) -> Double {
        (value * scale).rounded() / scale
    }
}
