//
//  CommandRoutes.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

enum CommandRoutes: RoutesDescription {
    
    case delete, add
    
    var route: PathComponent {
        switch self {
        case .delete:
            "delete"
        case .add:
            "add"
        }
    }
    
}
