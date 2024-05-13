import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    MySQLManager.shared.setup(app)
    try routes(app)
}
