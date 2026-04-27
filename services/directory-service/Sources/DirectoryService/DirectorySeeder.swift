import Fluent
import LockServerCore

enum DirectorySeeder {
    static func seed(on database: Database) async throws {
        guard try await DirectoryEmployer.query(on: database).count() == 0 else {
            return
        }

        try await SeedUsers.all.map {
            DirectoryEmployer(
                id: $0.id,
                name: $0.name,
                surname: $0.surname,
                department: $0.department,
                email: $0.email,
                isAdmin: $0.isAdmin,
                workNormMinutes: $0.workNormMinutes
            )
        }.create(on: database)

        let cards = SeedUsers.all.compactMap { seedUser -> DirectoryCard? in
            guard let cardCode = seedUser.cardCode else {
                return nil
            }
            return DirectoryCard(hash: CardCodeHasher.hash(cardCode), code: cardCode, employerID: seedUser.id)
        }
        try await cards.create(on: database)

        let fingers = SeedUsers.all.compactMap { seedUser -> DirectoryFinger? in
            guard let fingerCode = seedUser.fingerCode else {
                return nil
            }
            return DirectoryFinger(code: fingerCode, employerID: seedUser.id)
        }
        try await fingers.create(on: database)
    }
}
