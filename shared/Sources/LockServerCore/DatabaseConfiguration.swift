import Fluent
import FluentMySQLDriver
import Foundation
import NIOSSL
import Vapor

public struct DatabaseConfiguration {
    public let host: String
    public let port: Int
    public let user: String
    public let password: String
    public let databaseName: String

    public init(databaseName: String) throws {
        host = try EnvironmentValue.string("LOCKSERVER_DB_HOST", default: "127.0.0.1")
        port = try EnvironmentValue.int("LOCKSERVER_DB_PORT", default: 3306)
        user = try EnvironmentValue.string("LOCKSERVER_DB_USER", default: "root")
        password = try EnvironmentValue.string("LOCKSERVER_DB_PASSWORD")
        self.databaseName = databaseName
    }
}

public enum DatabaseBootstrapper {
    public static func configure(_ app: Application, databaseName: String) throws {
        let configuration = try DatabaseConfiguration(databaseName: databaseName)
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .none

        app.databases.use(
            .mysql(
                hostname: configuration.host,
                port: configuration.port,
                username: configuration.user,
                password: configuration.password,
                database: configuration.databaseName,
                tlsConfiguration: tls
            ),
            as: .mysql
        )
    }
}
