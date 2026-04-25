import XCTest
import XCTVapor
@testable import DeviceService

final class DeviceServiceTests: XCTestCase {
    func testOpenEndpointWorksInMockMode() async throws {
        setenv("LOCKSERVER_DEVICE_MODE", "mock", 1)
        setenv("LOCKSERVER_DEVICE_BIND_HOST", "127.0.0.1", 1)
        setenv("LOCKSERVER_DEVICE_PORT", "18084", 1)

        let app = Application(.testing)
        defer { app.shutdown() }

        try await configure(app)

        try app.test(.POST, "/internal/device/open") { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertEqual(response.body.string, #"{"isSuccess":true}"#)
        }
    }
}
