//
//  ArduinoManager.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation

final class ArduinoManager {
    
    static let shared = ArduinoManager()
    
    private let network = NetworkManager()
    
    private var lastID = ""
    
    private init() {}
    
    func open() async throws -> Bool {
        let id = generateID()
        let request = try makeRequest(id: id)
        let response: ArduinoResponse = try await network.makeRequest(request)
        return !response.error
    }
    
    private func generateID() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        var id = lastID
        
        while id == lastID {
            id = ""
            for _ in 0..<4 {
                if let randomLetter = letters.randomElement() {
                    id.append(randomLetter)
                }
            }
        }
        
        lastID = id
        return id
    }
    
    private func makeRequest(id: String) throws -> URLRequest {
        guard let url = URL(string: ArduinoConstants.adress + "?id=\(id)") else {
            throw ArduinoError.failedAdress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }
    
}

enum ArduinoError: Error {
    case failedAdress
}
