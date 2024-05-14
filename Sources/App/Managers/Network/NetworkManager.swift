//
//  NetworkManager.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Foundation

class NetworkManager {
    func makeRequest<T: Codable>(_ request: URLRequest) async throws -> T {
        let data: Data = try await makeRequest(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func makeRequest(_ request: URLRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            self?.fetchRequest(request, callback: { result in
                continuation.resume(with: result)
            })
        }
    }

    private func fetchRequest(_ request: URLRequest, callback: @escaping (Result<Data, Error>) -> Void) {
        print(request.url?.absoluteString ?? "")
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let response = response as? HTTPURLResponse, let data else {
                callback(.failure(error!))
                return
            }
            if 200 ... 299 ~= response.statusCode {
                callback(.success(data))
            } else {
                if let errorDes = String(data: data, encoding: .utf8) {
                    print(errorDes)
                }
                callback(.failure(NetworkError.responseStatusError))
            }
        }.resume()
    }
}

enum NetworkError: Error {
    case responseStatusError
}
