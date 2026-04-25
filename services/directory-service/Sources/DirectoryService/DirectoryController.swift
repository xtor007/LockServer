import Fluent
import LockServerContracts
import LockServerCore
import Vapor

struct DirectoryController: RouteCollection {
    private let eventRecorder: DomainEventRecorder

    init(eventRecorder: DomainEventRecorder) {
        self.eventRecorder = eventRecorder
    }

    func boot(routes: RoutesBuilder) throws {
        let directory = routes.grouped("internal", "directory")
        directory.get("employers", use: getAll)
        directory.get("employers", ":id", use: getEmployer)
        directory.post("employers", use: upsertEmployer)
        directory.delete("employers", ":id", use: deleteEmployer)
        directory.get("cards", "lookup", use: lookupCard)
        directory.get("fingers", "lookup", use: lookupFinger)
    }

    private func getAll(req: Request) async throws -> DirectoryEmployersResponse {
        let employers = try await DirectoryEmployer.query(on: req.db).all()
        var response = [EmployerModel]()
        response.reserveCapacity(employers.count)
        for employer in employers {
            response.append(try await makeEmployerModel(from: employer, on: req.db))
        }
        return DirectoryEmployersResponse(employers: response)
    }

    private func getEmployer(req: Request) async throws -> EmployerModel {
        let id = try req.parameters.require("id", as: UUID.self)
        guard let employer = try await DirectoryEmployer.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Employer not found")
        }
        return try await makeEmployerModel(from: employer, on: req.db)
    }

    private func upsertEmployer(req: Request) async throws -> ValidServerResponse {
        let request = try req.content.decode(DirectoryEmployerUpsertRequest.self)
        guard let id = request.employer.id else {
            throw Abort(.badRequest, reason: "Employer id is required")
        }

        if let employer = try await DirectoryEmployer.find(id, on: req.db) {
            employer.name = request.employer.name
            employer.surname = request.employer.surname
            employer.department = request.employer.department
            employer.email = request.employer.email
            employer.isAdmin = request.employer.isAdmin
            employer.workNormMinutes = request.employer.workNormMinutes ?? employer.workNormMinutes ?? SeedUsers.defaultWorkNormMinutes
            try await employer.update(on: req.db)
        } else {
            let employer = DirectoryEmployer(
                id: id,
                name: request.employer.name,
                surname: request.employer.surname,
                department: request.employer.department,
                email: request.employer.email,
                isAdmin: request.employer.isAdmin,
                workNormMinutes: request.employer.workNormMinutes ?? SeedUsers.defaultWorkNormMinutes
            )
            try await employer.create(on: req.db)
            await eventRecorder.publish("employee.created", payload: [
                "id": id.uuidString,
                "email": request.employer.email ?? ""
            ])
        }

        return ValidServerResponse(isValid: true)
    }

    private func deleteEmployer(req: Request) async throws -> ValidServerResponse {
        let id = try req.parameters.require("id", as: UUID.self)
        guard let employer = try await DirectoryEmployer.find(id, on: req.db) else {
            return ValidServerResponse(isValid: true)
        }
        guard !employer.isAdmin else {
            throw Abort(.forbidden, reason: "Admin user cannot be deleted")
        }
        try await employer.delete(on: req.db)
        await eventRecorder.publish("employee.deleted", payload: ["id": id.uuidString])
        return ValidServerResponse(isValid: true)
    }

    private func lookupCard(req: Request) async throws -> CredentialLookupResponse {
        let code = try req.query.get(String.self, at: "code")
        let hash = CardCodeHasher.hash(code)
        let card = try await DirectoryCard.query(on: req.db)
            .filter(\.$hash == hash)
            .filter(\.$code == code)
            .first()
        return CredentialLookupResponse(employerID: try await employerID(from: card))
    }

    private func lookupFinger(req: Request) async throws -> CredentialLookupResponse {
        let code = try req.query.get(Int.self, at: "code")
        let finger = try await DirectoryFinger.query(on: req.db)
            .filter(\.$code == code)
            .first()
        return CredentialLookupResponse(employerID: try await employerID(from: finger))
    }
}

private extension DirectoryController {
    func makeEmployerModel(from employer: DirectoryEmployer, on database: Database) async throws -> EmployerModel {
        let hasCard = try await DirectoryCard.query(on: database)
            .filter(\.$employer.$id == employer.requireID())
            .first() != nil
        let hasFinger = try await DirectoryFinger.query(on: database)
            .filter(\.$employer.$id == employer.requireID())
            .first() != nil

        return EmployerModel(
            id: employer.id,
            isAdmin: employer.isAdmin,
            name: employer.name,
            surname: employer.surname,
            department: employer.department,
            email: employer.email,
            workNormMinutes: employer.workNormMinutes ?? SeedUsers.defaultWorkNormMinutes,
            hasCard: hasCard,
            hasFinger: hasFinger
        )
    }

    func employerID(from card: DirectoryCard?) async throws -> UUID? {
        guard let card else {
            return nil
        }
        return card.$employer.id
    }

    func employerID(from finger: DirectoryFinger?) async throws -> UUID? {
        guard let finger else {
            return nil
        }
        return finger.$employer.id
    }
}
