//
//  CreateFinger.swift
//
//
//  Created by Anatoliy Khramchenko on 27.05.2024.
//

import Foundation
import Fluent

struct CreateFinger: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(FingerSQLValues.schema)
            .id()
            .field(FingerSQLValues.code, .int64, .required)
            .field(FingerSQLValues.employer, .uuid, .references(FingerSQLValues.schema, "id"))
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(FingerSQLValues.schema).delete()
    }
}
