//
//  CardCodeVerifier.swift
//
//
//  Created by Anatoliy Khramchenko on 13.05.2024.
//

import Foundation

class CardCodeVerifier {
    
    let db: DBManager
    
    init(db: DBManager) {
        self.db = db
    }
    
    func verify(_ code: String) async throws -> Bool {
        let hash = calculateHash(for: code)
        let cards = try await db.getCards(forHash: hash)
        guard let card = cards.first(where: { $0.code == code && $0.employerID != nil }),
              let employerID = card.employerID else {
            return false
        }
        addEnter(for: employerID)
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
    
    private func calculateHash(for code: String) -> Int {
        code.reduce(0, { $0 + hashNumber(for: $1) })
    }
    
    private func hashNumber(for symbol: Character) -> Int {
        switch symbol {
        case "0": 0
        case "1": 1
        case "2": 2
        case "3": 3
        case "4": 4
        case "5": 5
        case "6": 6
        case "7": 7
        case "8": 8
        case "9": 9
        case "A": 10
        case "B": 11
        case "C": 12
        case "D": 13
        case "E": 14
        case "F": 15
        default: 0
        }
    }
    
}
