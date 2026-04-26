import LockServerContracts
import LockServerCore
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.hostname = try EnvironmentValue.string("LOCKSERVER_ATTENDANCE_ANALYSIS_BIND_HOST", default: "127.0.0.1")
    app.http.server.configuration.port = try EnvironmentValue.int("LOCKSERVER_ATTENDANCE_ANALYSIS_PORT", default: 8085)

    try DatabaseBootstrapper.configure(app, databaseName: "lockService")

    app.migrations.add(CreateAttendanceDayObservation())
    app.migrations.add(CreateAttendanceAnalysisResult())
    app.migrations.add(AddAttendanceAnalysisResultCoreSignals())
    try await app.autoMigrate()

    let manager = AttendanceAnalysisManager(
        directoryClient: AttendanceDirectoryServiceClient(client: app.client, baseURL: try ServiceEndpoints.directoryBaseURL()),
        accessClient: AttendanceAccessServiceClient(client: app.client, baseURL: try ServiceEndpoints.accessBaseURL()),
        baselineWindowDays: try EnvironmentValue.int("LOCKSERVER_ATTENDANCE_ANALYSIS_BASELINE_WINDOW_DAYS", default: 3)
    )
    let authClient = AttendanceAuthServiceClient(client: app.client, baseURL: try ServiceEndpoints.authBaseURL())

    try app.register(collection: AttendanceAnalysisController(manager: manager, authClient: authClient))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}
