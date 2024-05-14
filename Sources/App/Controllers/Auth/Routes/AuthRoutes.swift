//
//  AuthRoutes.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation
import Vapor

enum AuthRoutes: RoutesDescription {
    
    case getToken, refreshToken, sendEmailForChangePassword, changePassword
    
    var route: PathComponent {
        switch self {
        case .getToken:
            "getToken"
        case .refreshToken:
            "refresh"
        case .sendEmailForChangePassword:
            "changePasswordEmail"
        case .changePassword:
            "changePassword"
        }
    }
    
}
