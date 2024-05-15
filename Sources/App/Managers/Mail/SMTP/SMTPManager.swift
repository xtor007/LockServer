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
        sendMessage("Hello, your code is \(code)", subject: "Password verify", email: email)
    }
    
    func sendPassword(_ password: String, to email: String) {
        sendMessage("Welcome to the team!!! Your password for lock app is \(password)", subject: "Password", email: email)
    }
    
    private func sendMessage(_ message: String, subject: String, email: String) {
        let user = Mail.User(email: email)
        let mail = Mail(from: admin, to: [user], subject: subject, text: message)
        smtp.send(mail) { error in
            guard let error else { return }
            print(error)
        }
    }
    
}
