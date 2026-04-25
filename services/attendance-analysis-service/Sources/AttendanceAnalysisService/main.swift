import Logging
import Vapor

var environment = try Environment.detect()
try LoggingSystem.bootstrap(from: &environment)

let app = Application(environment)
defer { app.shutdown() }

do {
    try await configure(app)
} catch {
    app.logger.report(error: error)
    throw error
}

try await app.execute()
