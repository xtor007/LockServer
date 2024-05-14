import Vapor
import JWT

// configures your application
public func configure(_ app: Application) async throws {
    app.jwt.signers.use(.hs256(key: AuthConstants.jwtSecret))
    MySQLManager.shared.setup(app)
    try routes(app)
}
