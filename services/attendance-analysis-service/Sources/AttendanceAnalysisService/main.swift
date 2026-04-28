import Logging
import Vapor

let isFixtureMaterializationCommand = ProcessInfo.processInfo.arguments.dropFirst().first == "materialize-fixture"
let environmentArguments = isFixtureMaterializationCommand
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
} else {
    try await app.execute()
}
