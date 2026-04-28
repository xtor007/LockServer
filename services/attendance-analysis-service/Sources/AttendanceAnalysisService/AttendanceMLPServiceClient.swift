import Foundation
import LockServerCore
import Vapor

struct AttendanceMLPServiceClient {
    private let serviceClient: ServiceClient
    private let decoder: JSONDecoder

    init(client: Client, baseURL: String) {
        self.serviceClient = ServiceClient(client: client, baseURL: baseURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func infer(items: [InferenceItem]) async throws -> InferenceResponse {
        let response = try await serviceClient.send(
            method: .POST,
            path: "/internal/mlp/infer",
            headers: internalHeaders,
            body: InferenceRequest(items: items)
        )

        guard response.status == .ok, let body = response.body else {
            throw Abort(
                .failedDependency,
                reason: "Attendance MLP inference failed: \(responseReason(from: response))"
            )
        }

        return try decoder.decode(InferenceResponse.self, from: Data(buffer: body))
    }
}

extension AttendanceMLPServiceClient {
    struct InferenceItem: Encodable {
        let requestId: String
        let features: [Double]

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case features
        }
    }

    struct InferenceRequest: Encodable {
        let items: [InferenceItem]
    }

    struct InferenceResponse: Decodable {
        let modelVersion: String
        let artifactId: String
        let featureOrder: [String]
        let results: [InferenceResult]

        enum CodingKeys: String, CodingKey {
            case modelVersion = "model_version"
            case artifactId = "artifact_id"
            case featureOrder = "feature_order"
            case results
        }
    }

    struct InferenceResult: Decodable {
        let requestId: String
        let etaNN: Double
        let modelVersion: String
        let diagnostics: InferenceDiagnostics

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case etaNN = "eta_nn"
            case modelVersion = "model_version"
            case diagnostics
        }
    }

    struct InferenceDiagnostics: Decodable {
        let artifactId: String
        let featureOrder: [String]
        let inputFeatures: [Double]
        let normalizedFeatures: [Double]
        let inferenceTimestamp: Date

        enum CodingKeys: String, CodingKey {
            case artifactId = "artifact_id"
            case featureOrder = "feature_order"
            case inputFeatures = "input_features"
            case normalizedFeatures = "normalized_features"
            case inferenceTimestamp = "inference_timestamp"
        }
    }
}

private extension AttendanceMLPServiceClient {
    var internalHeaders: HTTPHeaders {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: "X-LockServer-Internal-Service", value: "attendance-analysis")
        return headers
    }

    func responseReason(from response: ClientResponse) -> String {
        response.body.flatMap { buffer in
            buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes)
        } ?? HTTPResponseStatus(statusCode: Int(response.status.code)).reasonPhrase
    }
}
