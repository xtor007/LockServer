import LockServerContracts
import LockServerCore
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.hostname = try EnvironmentValue.string("LOCKSERVER_EXTERNAL_CONTEXT_BIND_HOST", default: "127.0.0.1")
    app.http.server.configuration.port = try EnvironmentValue.int("LOCKSERVER_EXTERNAL_CONTEXT_PORT", default: 8086)

    try DatabaseBootstrapper.configure(app, databaseName: "lockService")

    app.migrations.add(CreateExternalContextCache())
    try await app.autoMigrate()

    let trafficProvider = try EnvironmentValue.string("LOCKSERVER_EXTERNAL_CONTEXT_PTV_API_KEY", default: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let manager = ExternalContextManager(
        trafficProvider: trafficProvider.isEmpty
            ? nil
            : PTVTrafficProviderClient(client: app.client, apiKey: trafficProvider, configuration: .kyivDefault)
    )
    let authClient = AttendanceAuthServiceClient(client: app.client, baseURL: try ServiceEndpoints.authBaseURL())

    try app.register(collection: ExternalContextController(manager: manager, authClient: authClient))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}
