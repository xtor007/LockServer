import Fluent
import LockServerCore

enum AccessSeeder {
    static func seed(on database: Database) async throws {
        let existingCount = try await AccessEnter.query(on: database).count()
        guard existingCount == 0 else {
            return
        }

        for entry in SeedUsers.accessEntries {
            let accessEntry = AccessEnter(employerID: entry.employerID, time: entry.time, isOn: entry.isOn)
            try await accessEntry.create(on: database)
        }
    }
}
