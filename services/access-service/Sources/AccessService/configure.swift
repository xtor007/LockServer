import LockServerContracts
import LockServerCore
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.hostname = try EnvironmentValue.string("LOCKSERVER_ACCESS_BIND_HOST", default: "127.0.0.1")
    app.http.server.configuration.port = try EnvironmentValue.int("LOCKSERVER_ACCESS_PORT", default: 8083)

    try DatabaseBootstrapper.configure(app, databaseName: "lockService")

    app.migrations.add(CreateAccessEnter())
    try await app.autoMigrate()
    try await AccessSeeder.seed(on: app.db)

    let directoryClient = DirectoryServiceClient(client: app.client, baseURL: try ServiceEndpoints.directoryBaseURL())
    let deviceClient = DeviceServiceClient(client: app.client, baseURL: try ServiceEndpoints.deviceBaseURL())
    let eventRecorder = DomainEventRecorder(source: "access-service")

    try app.register(collection: AccessController(directoryClient: directoryClient, deviceClient: deviceClient, eventRecorder: eventRecorder))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}
