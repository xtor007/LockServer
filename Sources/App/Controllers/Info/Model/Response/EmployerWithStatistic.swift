//
//  EmployerWithStatistic.swift
//
//
//  Created by Anatoliy Khramchenko on 15.05.2024.
//

import Vapor

struct Employers: Content {
    let employers: [EmployerWithStatistic]
}

struct EmployerWithStatistic: Content {
    let employer: EmployerModel
    let statistic: Statistic
}
