import Foundation
import LockServerContracts

public struct StatisticCalculator {
    private let enters: [EnterModel]
    private let calendar = Calendar(identifier: .gregorian)

    public init(enters: [EnterModel]) {
        self.enters = enters.sorted(by: { $0.time < $1.time })
    }

    public var averageTime: Double {
        var summaryTime = 0.0
        var daysCount = 0
        var thisDayTime = 0.0
        var previousDate = Date.distantPast
        var inputHasBeenProcessed = false

        for enter in enters {
            if enter.isOn {
                inputHasBeenProcessed = true
                if !calendar.isDate(enter.time, inSameDayAs: previousDate) {
                    summaryTime += thisDayTime
                    daysCount += 1
                    thisDayTime = 0
                }
                previousDate = enter.time
                continue
            }

            guard inputHasBeenProcessed else {
                continue
            }

            thisDayTime += enter.time.timeIntervalSince(previousDate) / 3600
        }

        if thisDayTime != 0 && !calendar.isDate(.now, inSameDayAs: previousDate) {
            summaryTime += thisDayTime
        }

        guard daysCount > 0 else {
            return 0
        }

        return summaryTime / Double(daysCount)
    }
}
