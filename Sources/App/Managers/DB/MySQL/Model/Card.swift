//
//  Card.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Vapor
import Fluent

final class Card: Model, Content, CardDBModel {
    static let schema = CardSQLValues.schema
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: CardSQLValues.hash)
    var hash: Int
    
    @Field(key: CardSQLValues.code)
    var code: String
    
    @OptionalParent(key: CardSQLValues.employer)
    var employer: Employer?

    init() { }

    init(id: UUID? = nil, hash: Int, code: String, employerID: Employer.IDValue?) {
        self.id = id
        self.hash = hash
        self.code = code
        if let employerID = employerID {
            self.$employer.id = employerID
        }
    }
    
    var employerID: UUID? {
        employer?.id
    }
}

enum CardSQLValues {
    static let schema = "Cards"
    static let hash: FieldKey = "hash"
    static let code: FieldKey = "code"
    static let employer: FieldKey = "employer"
}
