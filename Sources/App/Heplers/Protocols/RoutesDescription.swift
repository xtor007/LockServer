//
//  RoutesDescription.swift
//
//
//  Created by Anatoliy Khramchenko on 30.04.2024.
//

import Foundation
import Vapor

protocol RoutesDescription {
    var route: PathComponent { get }
}
