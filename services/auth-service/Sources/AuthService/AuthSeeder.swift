import Fluent
import LockServerCore

enum AuthSeeder {
    static func seed(on database: Database) async throws {
        guard try await AuthUser.query(on: database).count() == 0 else {
            return
        }

        try await SeedUsers.all.map {
            AuthUser(id: $0.id, email: $0.email, password: $0.password, isAdmin: $0.isAdmin)
        }.create(on: database)
    }
}
