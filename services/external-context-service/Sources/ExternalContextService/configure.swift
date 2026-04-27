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
    let trafficFallbackMode = try EnvironmentValue.string("LOCKSERVER_EXTERNAL_CONTEXT_TRAFFIC_FALLBACK_MODE", default: "disabled")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let powerMode = try EnvironmentValue.string("LOCKSERVER_EXTERNAL_CONTEXT_POWER_MODE", default: "official_channel")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let weatherMode = try EnvironmentValue.string("LOCKSERVER_EXTERNAL_CONTEXT_WEATHER_MODE", default: "enabled")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let manager = ExternalContextManager(
        trafficProvider: trafficProvider.isEmpty
            ? nil
            : PTVTrafficProviderClient(client: app.client, apiKey: trafficProvider, configuration: .kyivDefault),
        powerProvider: powerMode == "disabled"
            ? nil
            : DTEKCityPowerProviderClient(client: app.client, configuration: .kyivDefault),
        weatherProvider: weatherMode == "disabled"
            ? nil
            : OpenMeteoWeatherProviderClient(client: app.client, configuration: .kyivDefault),
        trafficFallbackMode: trafficFallbackMode == "fixture_when_unavailable"
            ? .fixtureWhenUnavailable
            : .disabled
    )
    let authClient = AttendanceAuthServiceClient(client: app.client, baseURL: try ServiceEndpoints.authBaseURL())

    try app.register(collection: ExternalContextController(manager: manager, authClient: authClient))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}
