//
//  MailManager.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation

protocol MailManager {
    func sendCode(_ code: String, to email: String)
}
