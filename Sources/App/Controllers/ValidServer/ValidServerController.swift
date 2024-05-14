//
//  ValidServerController.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

struct ValidServerController: RouteCollection {
    
    private let controllerPath: PathComponent = "validate"
    
    func boot(routes: any RoutesBuilder) throws {
        let validRoutes = routes.grouped(controllerPath)
        validRoutes.get("", use: validate)
    }
    
    @Sendable func validate(req: Request) async throws -> ValidServerResponse {
        ValidServerResponse(isValid: true)
    }
    
}
