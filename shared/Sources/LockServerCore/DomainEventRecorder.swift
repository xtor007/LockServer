import Foundation
import LockServerContracts

public actor DomainEventRecorder {
    private let source: String
    private let fileURL: URL
    private let encoder = JSONEncoder()

    public init(source: String) {
        self.source = source
        let eventsDirectory = ProcessInfo.processInfo.environment["LOCKSERVER_EVENTS_DIR"]
            .map(URL.init(fileURLWithPath:))
            ?? URL(fileURLWithPath: "/tmp/lockserver-microservices/events")
        self.fileURL = eventsDirectory.appendingPathComponent("\(source).jsonl")
        encoder.dateEncodingStrategy = .iso8601
    }

    public func publish<Payload: Encodable>(_ name: String, payload: Payload) async {
        let event = VersionedDomainEvent(name: name, source: source, payload: payload)

        do {
            let data = try encoder.encode(event)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data([0x0A]))
        } catch {
            print("Failed to write event \(name): \(error)")
        }
    }
}
