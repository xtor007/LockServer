//
//  CreateEmployer.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Vapor
import Fluent

struct CreateEmployer: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(EmployerSQLValues.schema)
            .id()
            .field(EmployerSQLValues.name, .string)
            .field(EmployerSQLValues.surname, .string)
            .field(EmployerSQLValues.department, .string)
            .field(EmployerSQLValues.email, .string)
            .field(EmployerSQLValues.password, .string)
            .field(EmployerSQLValues.isAdmin, .bool, .required, .sql(raw: "0"))
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(EmployerSQLValues.schema).delete()
    }
}
