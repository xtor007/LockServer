import Foundation
import LockServerCore

protocol DoorOpener {
    func open() async throws -> Bool
}

enum DoorOpenerFactory {
    static func make() throws -> DoorOpener {
        let mode = try EnvironmentValue.string("LOCKSERVER_DEVICE_MODE", default: EnvironmentValue.bool("LOCKSERVER_MOCK_ARDUINO") ? "mock" : "live")
        if mode == "mock" {
            return MockDoorOpener()
        }
        return try ArduinoDoorOpener()
    }
}

struct MockDoorOpener: DoorOpener {
    func open() async throws -> Bool {
        true
    }
}

final class ArduinoDoorOpener: DoorOpener {
    private let address: String
    private var lastID = ""

    init() throws {
        address = try EnvironmentValue.string("LOCKSERVER_ARDUINO_URL")
    }

    func open() async throws -> Bool {
        let id = makeUniqueID()
        guard let url = URL(string: "\(address)?id=\(id)") else {
            throw DoorOpenerError.invalidAddress
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw DoorOpenerError.invalidResponse
        }

        let payload = try JSONDecoder().decode(ArduinoResponse.self, from: data)
        return !payload.error
    }

    private func makeUniqueID() -> String {
        var newID = lastID
        while newID == lastID {
            newID = RandomStringGenerator.lowercaseLetters(length: 4)
        }
        lastID = newID
        return newID
    }
}

private struct ArduinoResponse: Decodable {
    let error: Bool
}

enum DoorOpenerError: Error {
    case invalidAddress
    case invalidResponse
}
