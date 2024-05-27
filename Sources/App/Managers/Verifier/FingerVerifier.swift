//
//  FingerVerifier.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation

class FingerVerifier {
    
    private let db: DBManager
    
    init(db: DBManager) {
        self.db = db
    }
    
    func verify(_ code: String) async throws -> Bool {
        guard let code = Int(code) else { throw FingerVerifierError.failedCode }
        guard let finger = try await db.getFinger(forCode: code) else { throw FingerVerifierError.failedCode }
        guard let id = finger.employerID else { throw FingerVerifierError.failedID }
        addEnter(for: id)
        return true
    }
    
    private func addEnter(for id: UUID) {
        Task {
            do {
                try await db.addEnter(for: id)
            } catch {
                print(error)
            }
        }
    }
    
}

enum FingerVerifierError: Error {
    case failedCode, failedID
}
