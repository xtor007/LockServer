//
//  KeyVerifierControllerRoutes.swift
//
//
//  Created by Anatoliy Khramchenko on 30.04.2024.
//

import Foundation
import Vapor

enum KeyVerifierControllerRoutes: RoutesDescription {
    
    case verifyCard, verifyFinger
    
    var route: PathComponent {
        switch self {
        case .verifyCard:
            "verifyCard"
        case .verifyFinger:
            "verifyFinger"
        }
    }
    
}
