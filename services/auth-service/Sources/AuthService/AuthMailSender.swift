import Foundation
import LockServerCore
import SwiftSMTP

protocol AuthMailSender {
    func sendResetCode(_ code: String, to email: String)
    func sendWelcomePassword(_ password: String, to email: String)
}

enum AuthMailSenderFactory {
    static func make() throws -> AuthMailSender {
        let mode = try EnvironmentValue.string("LOCKSERVER_SMTP_MODE", default: "disabled")
        if mode == "smtp" {
            return try SMTPAuthMailSender()
        }
        return LoggerAuthMailSender()
    }
}

struct LoggerAuthMailSender: AuthMailSender {
    func sendResetCode(_ code: String, to email: String) {
        print("Password reset code for \(email): \(code)")
    }

    func sendWelcomePassword(_ password: String, to email: String) {
        print("Welcome password for \(email): \(password)")
    }
}

final class SMTPAuthMailSender: AuthMailSender {
    private let smtp: SMTP
    private let sender: Mail.User

    init() throws {
        let host = try EnvironmentValue.string("LOCKSERVER_SMTP_HOST")
        let email = try EnvironmentValue.string("LOCKSERVER_SMTP_EMAIL")
        let password = try EnvironmentValue.string("LOCKSERVER_SMTP_PASSWORD")
        let senderEmail = try EnvironmentValue.string("LOCKSERVER_SMTP_SENDER_EMAIL", default: "lock@no-reply.com")
        let senderName = try EnvironmentValue.string("LOCKSERVER_SMTP_SENDER_NAME", default: "Lock admins")

        smtp = SMTP(hostname: host, email: email, password: password)
        sender = Mail.User(name: senderName, email: senderEmail)
    }

    func sendResetCode(_ code: String, to email: String) {
        send(text: "Hello, your code is \(code)", subject: "Password verify", to: email)
    }

    func sendWelcomePassword(_ password: String, to email: String) {
        send(text: "Welcome to the team!!! Your password for lock app is \(password)", subject: "Password", to: email)
    }

    private func send(text: String, subject: String, to email: String) {
        let receiver = Mail.User(email: email)
        let message = Mail(from: sender, to: [receiver], subject: subject, text: text)
        smtp.send(message) { error in
            if let error {
                print(error)
            }
        }
    }
}
