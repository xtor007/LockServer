//
//  OpenRoutes.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor

enum OpenRoutes: RoutesDescription {
    
    case open
    
    var route: PathComponent {
        switch self {
        case .open:
            "open"
        }
    }
    
}
