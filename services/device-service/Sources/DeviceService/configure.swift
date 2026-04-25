import LockServerContracts
import LockServerCore
import Vapor

func configure(_ app: Application) async throws {
    app.http.server.configuration.hostname = try EnvironmentValue.string("LOCKSERVER_DEVICE_BIND_HOST", default: "127.0.0.1")
    app.http.server.configuration.port = try EnvironmentValue.int("LOCKSERVER_DEVICE_PORT", default: 8084)

    let opener = try DoorOpenerFactory.make()
    let eventRecorder = DomainEventRecorder(source: "device-service")

    try app.register(collection: DeviceController(opener: opener, eventRecorder: eventRecorder))
    app.get("validate") { _ in
        ValidServerResponse(isValid: true)
    }
}
