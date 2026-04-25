import LockServerContracts
import LockServerCore
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.hostname = try EnvironmentValue.string("LOCKSERVER_DIRECTORY_BIND_HOST", default: "127.0.0.1")
    app.http.server.configuration.port = try EnvironmentValue.int("LOCKSERVER_DIRECTORY_PORT", default: 8082)

    try DatabaseBootstrapper.configure(app, databaseName: "lockService")

    app.migrations.add(CreateDirectoryEmployer())
    app.migrations.add(AddDirectoryEmployerWorkNormMinutes())
    app.migrations.add(CreateDirectoryCard())
    app.migrations.add(CreateDirectoryFinger())
    try await app.autoMigrate()

    let eventRecorder = DomainEventRecorder(source: "directory-service")
    try await DirectorySeeder.seed(on: app.db)

    try app.register(collection: DirectoryController(eventRecorder: eventRecorder))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}
