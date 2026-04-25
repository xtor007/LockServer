import LockServerContracts
import LockServerCore
import Vapor

struct DeviceController: RouteCollection {
    private let opener: DoorOpener
    private let eventRecorder: DomainEventRecorder

    init(opener: DoorOpener, eventRecorder: DomainEventRecorder) {
        self.opener = opener
        self.eventRecorder = eventRecorder
    }

    func boot(routes: RoutesBuilder) throws {
        let device = routes.grouped("internal", "device")
        device.post("open", use: open)
    }

    private func open(req: Request) async throws -> OpeningResult {
        do {
            let isSuccess = try await opener.open()
            await eventRecorder.publish(isSuccess ? "device.online" : "device.offline", payload: ["openResult": isSuccess ? "success" : "failure"])
            return OpeningResult(isSuccess: isSuccess)
        } catch {
            await eventRecorder.publish("device.offline", payload: ["error": "\(error)"])
            throw error
        }
    }
}
