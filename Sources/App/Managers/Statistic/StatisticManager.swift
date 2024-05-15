//
//  StatisticManager.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Foundation

class StatisticManager {
    
    private let enters: [EnterDBModel]
    
    private var summaryTime = 0.0
    private var daysCount = 0
    
    private var thisDayTime = 0.0
    private var prevDate = Date.distantPast
    private var inputHasBeenProcessed = false
    
    private let calendar = Calendar.current
    
    init(enters: [EnterDBModel]) {
        self.enters = enters.sorted(by: { $0.time < $1.time })
    }
    
    var averageTime: Double {
        resetValues()
        enters.forEach({ handleEnter($0) })
        if thisDayTime != 0 && !calendar.isDate(.now, inSameDayAs: prevDate) {
            summaryTime += thisDayTime
            thisDayTime = 0
        }
        if daysCount == 0 {
            return 0
        }
        return summaryTime / Double(daysCount)
    }
    
    private func resetValues() {
        summaryTime = 0.0
        daysCount = 0
        thisDayTime = 0.0
        prevDate = Date.distantPast
        inputHasBeenProcessed = false
    }
    
    private func handleEnter(_ enter: EnterDBModel) {
        if enter.isOn {
            inputHasBeenProcessed = true
            handleOnEnter(enter.time)
        } else {
            guard inputHasBeenProcessed else { return }
            handleOffEnter(enter.time)
        }
    }
    
    private func handleOnEnter(_ date: Date) {
        if !calendar.isDate(date, inSameDayAs: prevDate) {
            summaryTime += thisDayTime
            daysCount += 1
            thisDayTime = 0
        }
        prevDate = date
    }
    
    private func handleOffEnter(_ date: Date) {
        let interval = date.timeIntervalSince(prevDate)
        let differenceInHours = Double(interval) / 3600
        thisDayTime += differenceInHours
    }
    
}
