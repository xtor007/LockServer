import Fluent
import LockServerCore

enum AccessSeeder {
    static func seed(on database: Database) async throws {
        guard try await AccessEnter.query(on: database).count() == 0 else {
            return
        }

        for chunk in SeedUsers.accessEntries.chunked(into: 1_000) {
            try await chunk.map {
                AccessEnter(employerID: $0.employerID, time: $0.time, isOn: $0.isOn)
            }.create(on: database)
        }
    }
}
