//
//  EnterModel.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

struct Logs: Content {
    let logs: [EnterModel]
}

struct EnterModel: Content {
    let isOn: Bool
    let time: Date
}
