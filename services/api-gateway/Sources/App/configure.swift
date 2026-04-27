import LockServerContracts
import LockServerCore
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.hostname = try EnvironmentValue.string("LOCKSERVER_GATEWAY_BIND_HOST", default: "127.0.0.1")
    app.http.server.configuration.port = try EnvironmentValue.int("LOCKSERVER_GATEWAY_PORT", default: 8080)

    let controller = try GatewayController(
        authBaseURL: ServiceEndpoints.authBaseURL(),
        directoryBaseURL: ServiceEndpoints.directoryBaseURL(),
        accessBaseURL: ServiceEndpoints.accessBaseURL(),
        attendanceAnalysisBaseURL: ServiceEndpoints.attendanceAnalysisBaseURL(),
        externalContextBaseURL: ServiceEndpoints.externalContextBaseURL()
    )

    try app.register(collection: controller)
}
