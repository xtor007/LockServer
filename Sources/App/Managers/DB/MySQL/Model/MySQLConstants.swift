//
//  MySQLConstants.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Foundation

enum MySQLConstants {
    static let host = ProcessInfo.processInfo.environment["LOCKSERVER_DB_HOST"] ?? "127.0.0.1"
    static let user = ProcessInfo.processInfo.environment["LOCKSERVER_DB_USER"] ?? "root"
    static let password = ProcessInfo.processInfo.environment["LOCKSERVER_DB_PASSWORD"] ?? "qazwsx123"
    static let scheme = ProcessInfo.processInfo.environment["LOCKSERVER_DB_NAME"] ?? "lockService"
}
