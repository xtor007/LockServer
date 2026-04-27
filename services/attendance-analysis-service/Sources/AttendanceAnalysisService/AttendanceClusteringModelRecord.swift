import Fluent
import Vapor

final class AttendanceClusteringModelRecord: Model, Content {
    static let schema = "attendance_clustering_models"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "model_version")
    var modelVersion: Int

    @Field(key: "normalization_json")
    var normalizationJson: String

    @Field(key: "centroids_json")
    var centroidsJson: String

    @Field(key: "trust_radii_json")
    var trustRadiiJson: String

    @Field(key: "cluster_definitions_json")
    var clusterDefinitionsJson: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() { }

    init(
        id: UUID? = nil,
        modelVersion: Int,
        normalizationJson: String,
        centroidsJson: String,
        trustRadiiJson: String,
        clusterDefinitionsJson: String
    ) {
        self.id = id ?? UUID()
        self.modelVersion = modelVersion
        self.normalizationJson = normalizationJson
        self.centroidsJson = centroidsJson
        self.trustRadiiJson = trustRadiiJson
        self.clusterDefinitionsJson = clusterDefinitionsJson
    }
}
