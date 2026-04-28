import Fluent
import Vapor

final class AttendanceMLPFeedbackSample: Model, Content {
    static let schema = "attendance_mlp_feedback_samples"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userId: UUID

    @Field(key: "day")
    var day: Date

    @Field(key: "z_s")
    var zS: Double

    @Field(key: "z_t")
    var zT: Double

    @Field(key: "f")
    var f: Double

    @Field(key: "air_alert_minutes")
    var airAlertMinutes: Int

    @Field(key: "traffic_score")
    var trafficScore: Double

    @Field(key: "power_score")
    var powerScore: Double

    @Field(key: "weather_score")
    var weatherScore: Double

    @Field(key: "eta_nn_target")
    var etaNNTarget: Double

    @Field(key: "source_model_version")
    var sourceModelVersion: String

    @OptionalField(key: "consumed_model_version")
    var consumedModelVersion: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() { }

    init(
        id: UUID? = nil,
        userId: UUID,
        day: Date,
        zS: Double,
        zT: Double,
        f: Double,
        airAlertMinutes: Int,
        trafficScore: Double,
        powerScore: Double,
        weatherScore: Double,
        etaNNTarget: Double,
        sourceModelVersion: String,
        consumedModelVersion: String? = nil
    ) {
        self.id = id ?? UUID()
        self.userId = userId
        self.day = day
        self.zS = zS
        self.zT = zT
        self.f = f
        self.airAlertMinutes = airAlertMinutes
        self.trafficScore = trafficScore
        self.powerScore = powerScore
        self.weatherScore = weatherScore
        self.etaNNTarget = etaNNTarget
        self.sourceModelVersion = sourceModelVersion
        self.consumedModelVersion = consumedModelVersion
    }
}
