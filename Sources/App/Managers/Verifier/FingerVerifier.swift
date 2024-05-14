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
        // TODO: hardcode
        return true
    }
    
}
