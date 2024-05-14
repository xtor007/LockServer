//
//  ChangePasswordManager.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation

class ChangePasswordManager {
    
    static let shared = ChangePasswordManager()
    
    private var codeStorage = [String:String]()
    private var codesThatWillDelete = [String]()

    private let letters = "abcdefghijklmnopqrstuvwxyz"
    
    private init() {}
    
    func makeCode(for email: String) -> String {
        let code = generateCode()
        codeStorage[code] = email
        deleteCode(code, after: 180)
        return code
    }
    
    func email(for code: String) -> String? {
        let email = codeStorage[code]
        codesThatWillDelete.append(code)
        codeStorage[code] = nil
        return email
    }
    
}

// MARK: - Generate Code

extension ChangePasswordManager {
    
    private var randomCode: String {
        var code = ""
        for _ in 0..<8 {
            if let randomLetter = letters.randomElement() {
                code.append(randomLetter)
            }
        }
        return code
    }
    
    private func generateCode() -> String {
        var code = randomCode
        while codeStorage[code] != nil && !codesThatWillDelete.contains(where: { $0 == code }) {
            code = randomCode
        }
        return code
    }
    
    private func deleteCode(_ code: String, after interval: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            codeStorage[code] = nil
            codesThatWillDelete.removeAll(where: { $0 == code })
        }
    }
    
}
