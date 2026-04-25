import Foundation
import LockServerContracts
import Vapor

public enum ServiceClientError: Error {
    case invalidURL(String)
    case invalidResponseBody
}

public struct ServiceClient {
    public let client: Client
    public let baseURL: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(client: Client, baseURL: String) {
        self.client = client
        self.baseURL = baseURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func get<Response: Decodable>(
        _ path: String,
        headers: HTTPHeaders = [:],
        query: [String: String] = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let response = try await send(method: .GET, path: path, headers: headers, query: query)
        return try decode(Response.self, from: response)
    }

    public func getString(
        _ path: String,
        headers: HTTPHeaders = [:],
        query: [String: String] = [:]
    ) async throws -> String {
        let response = try await send(method: .GET, path: path, headers: headers, query: query)
        guard let body = response.body,
              let string = body.getString(at: body.readerIndex, length: body.readableBytes) else {
            throw ServiceClientError.invalidResponseBody
        }
        return string
    }

    public func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        headers: HTTPHeaders = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let response = try await send(method: .POST, path: path, headers: headers, body: body)
        return try decode(Response.self, from: response)
    }

    public func delete<Response: Decodable>(
        _ path: String,
        headers: HTTPHeaders = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let response = try await send(method: .DELETE, path: path, headers: headers)
        return try decode(Response.self, from: response)
    }

    public func send(
        method: HTTPMethod,
        path: String,
        headers: HTTPHeaders = [:],
        query: [String: String] = [:]
    ) async throws -> ClientResponse {
        let uri = try makeURI(path: path, query: query)
        return try await client.send(method, headers: headers, to: uri)
    }

    public func send<Body: Encodable>(
        method: HTTPMethod,
        path: String,
        headers: HTTPHeaders = [:],
        query: [String: String] = [:],
        body: Body
    ) async throws -> ClientResponse {
        let uri = try makeURI(path: path, query: query)
        var requestHeaders = headers
        requestHeaders.replaceOrAdd(name: .contentType, value: HTTPMediaType.json.serialize())
        let encodedBody = try encoder.encode(body)
        return try await client.send(method, headers: requestHeaders, to: uri) { request in
            request.body = ByteBuffer(data: encodedBody)
        }
    }

    private func makeURI(path: String, query: [String: String]) throws -> URI {
        guard var components = URLComponents(string: baseURL + path) else {
            throw ServiceClientError.invalidURL(baseURL + path)
        }
        if !query.isEmpty {
            components.queryItems = query.map(URLQueryItem.init)
        }
        guard let urlString = components.url?.absoluteString else {
            throw ServiceClientError.invalidURL(baseURL + path)
        }
        return URI(string: urlString)
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from response: ClientResponse) throws -> Response {
        guard let body = response.body else {
            throw ServiceClientError.invalidResponseBody
        }
        return try decoder.decode(Response.self, from: Data(buffer: body))
    }
}
