import Fluent
import LockServerCore

enum DirectorySeeder {
    static func seed(on database: Database) async throws {
        for seedUser in SeedUsers.all {
            let employer: DirectoryEmployer
            if let existing = try await DirectoryEmployer.find(seedUser.id, on: database) {
                employer = existing
            } else {
                let newEmployer = DirectoryEmployer(
                    id: seedUser.id,
                    name: seedUser.name,
                    surname: seedUser.surname,
                    department: seedUser.department,
                    email: seedUser.email,
                    isAdmin: seedUser.isAdmin
                )
                try await newEmployer.create(on: database)
                employer = newEmployer
            }

            if let cardCode = seedUser.cardCode {
                let existingCard = try await DirectoryCard.query(on: database)
                    .filter(\.$code == cardCode)
                    .first()
                if existingCard == nil, let employerID = employer.id {
                    let card = DirectoryCard(hash: CardCodeHasher.hash(cardCode), code: cardCode, employerID: employerID)
                    try await card.create(on: database)
                }
            }

            if let fingerCode = seedUser.fingerCode {
                let existingFinger = try await DirectoryFinger.query(on: database)
                    .filter(\.$code == fingerCode)
                    .first()
                if existingFinger == nil, let employerID = employer.id {
                    let finger = DirectoryFinger(code: fingerCode, employerID: employerID)
                    try await finger.create(on: database)
                }
            }
        }
    }
}
