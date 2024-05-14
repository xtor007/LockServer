//
//  SMTPManager.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation
import SwiftSMTP

class SMTPManager: MailManager {
    
    static let shared = SMTPManager()
    
    let smtp = SMTP(
        hostname: SMTPConstants.host,
        email: SMTPConstants.email,
        password: SMTPConstants.password
    )
    let admin = Mail.User(name: "Lock admins", email: "lock@no-reply.com")
    
    private init() {}
    
    func sendCode(_ code: String, to email: String) {
        let user = Mail.User(email: email)
        let mail = Mail(from: admin, to: [user], subject: "Password verify", text: "Hello, your code is \(code)")
        smtp.send(mail) { error in
            guard let error else { return }
            print(error)
        }
    }
    
}
