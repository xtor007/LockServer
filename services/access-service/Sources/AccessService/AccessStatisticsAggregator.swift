import Foundation

struct AccessStatisticsAggregator {
    private let calendar = Calendar(identifier: .gregorian)

    func averageTimes(for enters: [AccessEnter], now: Date = .now) -> [UUID: Double] {
        var stateByEmployer = [UUID: EmployerStatisticState]()
        stateByEmployer.reserveCapacity(enters.count / 100)

        for enter in enters {
            var state = stateByEmployer[enter.employerID, default: EmployerStatisticState()]

            if enter.isOn {
                state.inputHasBeenProcessed = true

                if !calendar.isDate(enter.time, inSameDayAs: state.previousDate) {
                    state.summaryTime += state.thisDayTime
                    state.daysCount += 1
                    state.thisDayTime = 0
                }

                state.previousDate = enter.time
            } else if state.inputHasBeenProcessed {
                state.thisDayTime += enter.time.timeIntervalSince(state.previousDate) / 3600
            }

            stateByEmployer[enter.employerID] = state
        }

        return stateByEmployer.mapValues { state in
            var finalizedState = state
            if finalizedState.thisDayTime != 0 && !calendar.isDate(now, inSameDayAs: finalizedState.previousDate) {
                finalizedState.summaryTime += finalizedState.thisDayTime
            }

            guard finalizedState.daysCount > 0 else {
                return 0
            }

            return finalizedState.summaryTime / Double(finalizedState.daysCount)
        }
    }
}

private struct EmployerStatisticState {
    var summaryTime = 0.0
    var daysCount = 0
    var thisDayTime = 0.0
    var previousDate = Date.distantPast
    var inputHasBeenProcessed = false
}
