//
//  ArduinoAnswer.swift
//
//
//  Created by Anatoliy Khramchenko on 09.05.2024.
//

import Foundation

enum ArduinoAnswer {
    static func build(for isGood: Bool) -> ArduinoAnswer {
        isGood ? .good : .failed
    }
    
    case good, failed
    
    var message: String {
        switch self {
        case .good:
            "1"
        case .failed:
            "0"
        }
    }
}
