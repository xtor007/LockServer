import Fluent
import Vapor

final class AttendanceAnalysisResult: Model, Content {
    static let schema = "attendance_analysis_results"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "day")
    var day: Date

    @Field(key: "status")
    var status: String

    @OptionalField(key: "observation_id")
    var observationId: UUID?

    @OptionalField(key: "history_days_used")
    var historyDaysUsed: Int?

    @OptionalField(key: "average_start_minutes")
    var averageStartMinutes: Double?

    @OptionalField(key: "stddev_start_minutes")
    var stddevStartMinutes: Double?

    @OptionalField(key: "stddev_worked_minutes")
    var stddevWorkedMinutes: Double?

    @OptionalField(key: "work_norm_minutes")
    var workNormMinutes: Int?

    @OptionalField(key: "z_s")
    var zS: Double?

    @OptionalField(key: "z_t")
    var zT: Double?

    @OptionalField(key: "f")
    var f: Double?

    @OptionalField(key: "cluster_name")
    var clusterName: String?

    @OptionalField(key: "cluster_score")
    var clusterScore: Double?

    @OptionalField(key: "cluster_weight")
    var clusterWeight: Double?

    @OptionalField(key: "cluster_model_version")
    var clusterModelVersion: Int?

    @OptionalField(key: "cluster_distance")
    var clusterDistance: Double?

    @OptionalField(key: "clustering_status")
    var clusteringStatus: String?

    @OptionalField(key: "eta_nn")
    var etaNN: Double?

    @OptionalField(key: "mlp_model_version")
    var mlpModelVersion: String?

    @OptionalField(key: "mlp_status")
    var mlpStatus: String?

    @OptionalField(key: "risk_score")
    var riskScore: Double?

    @OptionalField(key: "risk_zone")
    var riskZone: String?

    @Field(key: "details_json")
    var detailsJson: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() { }

    init(
        id: UUID? = nil,
        userId: UUID,
        day: Date,
        status: String,
        observationId: UUID?,
        historyDaysUsed: Int?,
        averageStartMinutes: Double?,
        stddevStartMinutes: Double?,
        stddevWorkedMinutes: Double?,
        workNormMinutes: Int?,
        zS: Double?,
        zT: Double?,
        f: Double?,
        clusterName: String? = nil,
        clusterScore: Double? = nil,
        clusterWeight: Double? = nil,
        clusterModelVersion: Int? = nil,
        clusterDistance: Double? = nil,
        clusteringStatus: String? = nil,
        etaNN: Double? = nil,
        mlpModelVersion: String? = nil,
        mlpStatus: String? = nil,
        riskScore: Double? = nil,
        riskZone: String? = nil,
        detailsJson: String
    ) {
        self.id = id ?? UUID()
        self.userId = userId
        self.day = day
        self.status = status
        self.observationId = observationId
        self.historyDaysUsed = historyDaysUsed
        self.averageStartMinutes = averageStartMinutes
        self.stddevStartMinutes = stddevStartMinutes
        self.stddevWorkedMinutes = stddevWorkedMinutes
        self.workNormMinutes = workNormMinutes
        self.zS = zS
        self.zT = zT
        self.f = f
        self.clusterName = clusterName
        self.clusterScore = clusterScore
        self.clusterWeight = clusterWeight
        self.clusterModelVersion = clusterModelVersion
        self.clusterDistance = clusterDistance
        self.clusteringStatus = clusteringStatus
        self.etaNN = etaNN
        self.mlpModelVersion = mlpModelVersion
        self.mlpStatus = mlpStatus
        self.riskScore = riskScore
        self.riskZone = riskZone
        self.detailsJson = detailsJson
    }
}
