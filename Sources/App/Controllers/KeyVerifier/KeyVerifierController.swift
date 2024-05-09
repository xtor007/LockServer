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
    
    private let queryCodeParameterName = "code"
    
    func boot(routes: any RoutesBuilder) throws {
        let verifierRoutes = routes.grouped(controllerPath)
        verifierRoutes.get(
            KeyVerifierControllerRoutes.verifyCard.route,
            use: verifyCard
        )
        verifierRoutes.get(
            KeyVerifierControllerRoutes.verifyFinger.route,
            use: verifyFinger
        )
    }
    
    @Sendable func verifyCard(req: Request) async throws -> String {
        guard let cardCode = try? req.query.get(String.self, at: queryCodeParameterName) else {
            return ArduinoAnswer.failed.message
        }
        print("code is \(cardCode)")
        return  ArduinoAnswer.build(for: cardCode == "33F22F11").message // hardcode
    }
    
    @Sendable func verifyFinger(req: Request) async throws -> String {
        guard let fingerCode = try? req.query.get(String.self, at: queryCodeParameterName) else {
            return ArduinoAnswer.failed.message
        }
        print("code is \(fingerCode)")
        return  ArduinoAnswer.good.message // hardcode
    }
    
}
