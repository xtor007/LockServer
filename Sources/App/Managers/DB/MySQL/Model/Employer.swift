//
//  Employer.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Fluent
import Vapor

final class Employer: Model, Content, EmployerDBModel {
    static let schema = EmployerSQLValues.schema
    
    @ID(key: .id)
    var id: UUID?

    @Field(key: EmployerSQLValues.name)
    var name: String?

    @Field(key: EmployerSQLValues.surname)
    var surname: String?

    @Field(key: EmployerSQLValues.department)
    var department: String?

    @Field(key: EmployerSQLValues.email)
    var email: String?

    @Field(key: EmployerSQLValues.password)
    var password: String?

    @Field(key: EmployerSQLValues.isAdmin)
    var isAdmin: Bool

    init() { }

    init(name: String?, surname: String?, department: String?, email: String?, password: String?, isAdmin: Bool) {
        self.id = UUID()
        self.name = name
        self.surname = surname
        self.department = department
        self.email = email
        self.password = password
        self.isAdmin = isAdmin
    }
}

enum EmployerSQLValues {
    static let schema = "Employers"
    static let name: FieldKey = "name"
    static let surname: FieldKey = "surname"
    static let department: FieldKey = "department"
    static let email: FieldKey = "email"
    static let password: FieldKey = "password"
    static let isAdmin: FieldKey = "isAdmin"
}
