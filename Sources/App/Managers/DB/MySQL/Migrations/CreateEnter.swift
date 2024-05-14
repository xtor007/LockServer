//
//  CreateEnter.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation
import Fluent

struct CreateEnter: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(EnterSQLValues.schema)
            .id()
            .field(EnterSQLValues.employer, .uuid, .required, .references(EmployerSQLValues.schema, "id", onDelete: .cascade))
            .field(EnterSQLValues.time, .datetime)
            .field(EnterSQLValues.isOn, .bool)
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(EnterSQLValues.schema).delete()
    }
}
