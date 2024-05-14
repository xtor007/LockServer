//
//  Enter.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Fluent
import Vapor

final class Enter: Model, Content {
    static let schema = EnterSQLValues.schema
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: EnterSQLValues.employer)
    var employer: Employer
    
    @Field(key: EnterSQLValues.time)
    var time: Date?
    
    @Field(key: EnterSQLValues.isOn)
    var isOn: Bool?

    init() { }

    init(employerID: UUID, time: Date = .now, isOn: Bool? = nil) {
        self.id = UUID()
        self.$employer.id = employerID
        self.time = time
        self.isOn = isOn
    }
}

enum EnterSQLValues {
    static let schema = "Enters"
    static let employer: FieldKey = "employer"
    static let time: FieldKey = "time"
    static let isOn: FieldKey = "isOn"
}
