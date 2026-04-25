//
//  ArduinoConstants.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation

enum ArduinoConstants {
    static let adress = ProcessInfo.processInfo.environment["LOCKSERVER_ARDUINO_URL"] ?? "http://192.168.1.203"
    static let shouldMock = ProcessInfo.processInfo.environment["LOCKSERVER_MOCK_ARDUINO"] == "1"
}
