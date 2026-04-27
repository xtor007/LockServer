import Foundation
import Vapor

struct DTEKPowerProviderFetchOutput: Equatable {
    let signals: [DTEKPowerCitySignal]
}

struct DTEKCityPowerProviderClient {
    private let client: Client
    private let configuration: DTEKCityPowerConfiguration

    init(client: Client, configuration: DTEKCityPowerConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    func fetchKyivSignals() async throws -> DTEKPowerProviderFetchOutput {
        let response = try await client.send(.GET, to: makeURI())
        guard response.status == .ok, let body = response.body else {
            let reason = response.body.flatMap {
                $0.getString(at: $0.readerIndex, length: $0.readableBytes)
            } ?? "DTEK power source request failed"
            throw Abort(.badGateway, reason: reason)
        }

        let html = Data(buffer: body)
        guard let htmlString = String(data: html, encoding: .utf8) else {
            throw Abort(.badGateway, reason: "DTEK power source returned unreadable content")
        }

        return DTEKPowerProviderFetchOutput(signals: DTEKPowerChannelParser.parseSignals(from: htmlString))
    }
}

private extension DTEKCityPowerProviderClient {
    func makeURI() -> URI {
        var components = URLComponents(string: configuration.sourceURL)
        components?.queryItems = [
            URLQueryItem(name: "q", value: configuration.searchQuery)
        ]
        return URI(string: components?.url?.absoluteString ?? configuration.sourceURL)
    }
}
