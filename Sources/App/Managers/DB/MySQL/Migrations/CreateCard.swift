//
//  CreateCard.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Foundation
import Fluent

struct CreateCard: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(CardSQLValues.schema)
            .id()
            .field(CardSQLValues.hash, .int, .required)
            .field(CardSQLValues.code, .string, .required)
            .field(CardSQLValues.employer, .uuid, .references(EmployerSQLValues.schema, "id"))
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(CardSQLValues.schema).delete()
    }
}
