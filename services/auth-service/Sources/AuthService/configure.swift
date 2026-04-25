import JWT
import LockServerContracts
import LockServerCore
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.hostname = try EnvironmentValue.string("LOCKSERVER_AUTH_BIND_HOST", default: "127.0.0.1")
    app.http.server.configuration.port = try EnvironmentValue.int("LOCKSERVER_AUTH_PORT", default: 8081)

    try DatabaseBootstrapper.configure(app, databaseName: "lockService")

    let jwtSecret = try EnvironmentValue.string("LOCKSERVER_JWT_SECRET")
    app.jwt.signers.use(.hs256(key: jwtSecret))

    app.migrations.add(CreateAuthUser())
    try await app.autoMigrate()

    let mailSender = try AuthMailSenderFactory.make()
    let codeStore = ResetCodeStore()

    try await AuthSeeder.seed(on: app.db)

    try app.register(collection: AuthController(mailSender: mailSender, codeStore: codeStore))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}
