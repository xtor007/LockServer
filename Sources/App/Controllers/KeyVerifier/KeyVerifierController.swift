//
//  KeyVerifierController.swift
//
//
//  Created by Anatoliy Khramchenko on 30.04.2024.
//

import Foundation
import Vapor

struct KeyVerifierController: RouteCollection {
    
    private let controllerPath: PathComponent = "verifier"
    
    func boot(routes: any RoutesBuilder) throws {
        let verifierRoutes = routes.grouped(controllerPath)
        verifierRoutes.post(
            KeyVerifierControllerRoutes.verifyCard.route,
            use: verifyCard
        )
    }
    
    @Sendable func verifyCard(req: Request) async throws -> Bool {
        do {
            let cardCode = try req.content.decode(CardCode.self)
            return cardCode.code == "33f22f11" // hardcode
        } catch {
            throw Abort(.badRequest)
        }
    }
    
}
