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
    app.migrations.add(AddAttendanceAnalysisResultClusteringFields())
    app.migrations.add(AddAttendanceAnalysisResultMLPFields())
    app.migrations.add(AddAttendanceAnalysisResultRiskFields())
    app.migrations.add(CreateAttendanceMLPFeedbackSample())
    app.migrations.add(CreateAttendanceClusteringModelRecord())
    try await app.autoMigrate()

    let manager = try makeAttendanceAnalysisManager(app)
    let authClient = AttendanceAuthServiceClient(client: app.client, baseURL: try ServiceEndpoints.authBaseURL())

    try app.register(collection: AttendanceAnalysisController(manager: manager, authClient: authClient))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}

func makeAttendanceAnalysisManager(_ app: Application) throws -> AttendanceAnalysisManager {
    let mlpClient = AttendanceMLPServiceClient(client: app.client, baseURL: try ServiceEndpoints.mlpBaseURL())
    let riskScoreService = AttendanceRiskScoreService(
        alpha: try attendanceRiskAlpha(),
        deficitWeight: try attendanceRiskDeficitWeight()
    )
    return AttendanceAnalysisManager(
        directoryClient: AttendanceDirectoryServiceClient(client: app.client, baseURL: try ServiceEndpoints.directoryBaseURL()),
        accessClient: AttendanceAccessServiceClient(client: app.client, baseURL: try ServiceEndpoints.accessBaseURL()),
        externalContextClient: AttendanceExternalContextServiceClient(client: app.client, baseURL: try ServiceEndpoints.externalContextBaseURL()),
        baselineWindowDays: try attendanceBaselineWindowDays(),
        clusteringService: AttendanceClusteringService(),
        mlpInferenceService: AttendanceMLPInferenceService(client: mlpClient, riskScoreService: riskScoreService),
        mlpFeedbackService: AttendanceMLPFeedbackService(client: mlpClient, riskScoreService: riskScoreService),
        riskScoreService: riskScoreService
    )
}

func makeAttendanceFixtureMaterializer(_ app: Application) throws -> AttendanceFixtureMaterializer {
    let riskScoreService = AttendanceRiskScoreService(
        alpha: try attendanceRiskAlpha(),
        deficitWeight: try attendanceRiskDeficitWeight()
    )
    return AttendanceFixtureMaterializer(
        externalContextClient: AttendanceExternalContextServiceClient(client: app.client, baseURL: try ServiceEndpoints.externalContextBaseURL()),
        baselineWindowDays: try attendanceBaselineWindowDays(),
        clusteringService: AttendanceClusteringService(),
        mlpInferenceService: AttendanceMLPInferenceService(
            client: AttendanceMLPServiceClient(client: app.client, baseURL: try ServiceEndpoints.mlpBaseURL()),
            riskScoreService: riskScoreService
        )
    )
}

func makeAttendancePipelineRebuilder(_ app: Application) throws -> AttendancePipelineRebuilder {
    let mlpClient = AttendanceMLPServiceClient(client: app.client, baseURL: try ServiceEndpoints.mlpBaseURL())
    let riskScoreService = AttendanceRiskScoreService(
        alpha: try attendanceRiskAlpha(),
        deficitWeight: try attendanceRiskDeficitWeight()
    )
    return AttendancePipelineRebuilder(
        clusteringService: AttendanceClusteringService(),
        mlpInferenceService: AttendanceMLPInferenceService(client: mlpClient, riskScoreService: riskScoreService),
        riskScoreService: riskScoreService
    )
}

func attendanceBaselineWindowDays() throws -> Int {
    try EnvironmentValue.int("LOCKSERVER_ATTENDANCE_ANALYSIS_BASELINE_WINDOW_DAYS", default: 3)
}

func attendanceRiskAlpha() throws -> Double {
    let alpha = try EnvironmentValue.double("LOCKSERVER_ATTENDANCE_ANALYSIS_RISK_ALPHA", default: 1)
    guard alpha.isFinite, alpha >= 0 else {
        throw Abort(.internalServerError, reason: "LOCKSERVER_ATTENDANCE_ANALYSIS_RISK_ALPHA must be a finite number greater than or equal to 0")
    }
    return alpha
}

func attendanceRiskDeficitWeight() throws -> Double {
    let deficitWeight = try EnvironmentValue.double("LOCKSERVER_ATTENDANCE_ANALYSIS_RISK_DEFICIT_WEIGHT", default: 2)
    guard deficitWeight.isFinite, deficitWeight >= 0 else {
        throw Abort(.internalServerError, reason: "LOCKSERVER_ATTENDANCE_ANALYSIS_RISK_DEFICIT_WEIGHT must be a finite number greater than or equal to 0")
    }
    return deficitWeight
}
