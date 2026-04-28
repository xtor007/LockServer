import Logging
import Vapor

let serviceCommand = ProcessInfo.processInfo.arguments.dropFirst().first
let isFixtureMaterializationCommand = serviceCommand == "materialize-fixture"
let isPipelineRebuildCommand = serviceCommand == "rebuild-all-pipeline"
let environmentArguments = (isFixtureMaterializationCommand || isPipelineRebuildCommand)
    ? [ProcessInfo.processInfo.arguments[0]] + Array(ProcessInfo.processInfo.arguments.dropFirst(2))
    : ProcessInfo.processInfo.arguments

var environment = try Environment.detect(arguments: environmentArguments)
try LoggingSystem.bootstrap(from: &environment)

let app = Application(environment)
defer { app.shutdown() }

do {
    try await configure(app)
} catch {
    app.logger.report(error: error)
    throw error
}

if isFixtureMaterializationCommand {
    let summary = try await makeAttendanceFixtureMaterializer(app).materialize(on: app.db)
    print("Attendance fixture materialized for \(summary.regularUserCount) regular users across \(summary.fixtureDayCount) fixture days.")
    print("Observations: \(summary.observationCount), results: \(summary.resultCount), signals_ready: \(summary.signalReadyCount), clustered: \(summary.clusteredCount), technical_outliers: \(summary.technicalOutlierCount), clustering_model_version: \(summary.clusteringModelVersion ?? 0), mlp_ready: \(summary.mlpReadyCount), mlp_failed: \(summary.mlpFailedCount), mlp_model_version: \(summary.mlpModelVersion ?? "n/a"), external-context days: \(summary.contextDayCount).")
} else if isPipelineRebuildCommand {
    let summary = try await makeAttendancePipelineRebuilder(app).rebuildAll(on: app.db)
    print("Attendance pipeline rebuilt for all eligible rows.")
    print("Clustering model version: \(summary.clusteringModelVersion ?? 0), clustered: \(summary.clusteredCount), technical_outliers: \(summary.technicalOutlierCount), mlp_model_version: \(summary.mlpModelVersion ?? "n/a"), mlp_ready: \(summary.inferredCount), mlp_failed: \(summary.mlpFailedCount), risk_calculated: \(summary.riskCalculatedCount).")
} else {
    try await app.execute()
}
