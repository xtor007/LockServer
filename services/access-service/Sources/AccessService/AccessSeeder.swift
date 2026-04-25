import Fluent
import LockServerCore

enum AccessSeeder {
    static func seed(on database: Database) async throws {
        for entry in SeedUsers.accessEntries {
            let existingEntry = try await AccessEnter.query(on: database)
                .filter(\.$employerID == entry.employerID)
                .filter(\.$time == entry.time)
                .filter(\.$isOn == entry.isOn)
                .first()

            guard existingEntry == nil else {
                continue
            }

            let accessEntry = AccessEnter(employerID: entry.employerID, time: entry.time, isOn: entry.isOn)
            try await accessEntry.create(on: database)
        }
    }
}
