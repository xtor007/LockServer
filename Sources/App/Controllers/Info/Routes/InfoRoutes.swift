//
//  InfoRoutes.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

enum InfoRoutes: RoutesDescription {
    
    case getInfo, getLogs, getStatistic, allUsers
    
    var route: PathComponent {
        switch self {
        case .getInfo:
            ""
        case .getLogs:
            "logs"
        case .getStatistic:
            "statistic"
        case .allUsers:
            "all"
        }
    }
    
}
