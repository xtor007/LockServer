//
//  Finger.swift
//
//
//  Created by Anatoliy Khramchenko on 27.05.2024.
//

import Vapor
import Fluent

final class Finger: Model, Content, FingerDBModel {
    static let schema = FingerSQLValues.schema
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: FingerSQLValues.code)
    var code: Int
    
    @Parent(key: FingerSQLValues.employer)
    var employer: Employer

    init() { }

    init(code: Int, employerID: Employer.IDValue?) {
        self.id = UUID()
        self.code = code
        if let employerID = employerID {
            self.$employer.id = employerID
        }
    }
    
    var employerID: UUID? {
        employer.id
    }
}

enum FingerSQLValues {
    static let schema = "Fingers"
    static let code: FieldKey = "code"
    static let employer: FieldKey = "employer"
}
