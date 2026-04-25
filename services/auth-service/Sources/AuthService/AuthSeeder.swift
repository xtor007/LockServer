import Fluent
import LockServerCore

enum AuthSeeder {
    static func seed(on database: Database) async throws {
        for seedUser in SeedUsers.all {
            let existing = try await AuthUser.find(seedUser.id, on: database)
            if existing != nil {
                continue
            }

            let user = AuthUser(
                id: seedUser.id,
                email: seedUser.email,
                password: seedUser.password,
                isAdmin: seedUser.isAdmin
            )
            try await user.create(on: database)
        }
    }
}
