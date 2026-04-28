import Foundation
import Vapor

struct AttendanceMLPFeatureBuilder {
    static let featureOrder = [
        "z_s",
        "z_t",
        "f",
        "air_alert_minutes",
        "traffic_score",
        "power_score",
        "weather_score"
    ]

    func build(from row: ResultRow) throws -> FeatureVector {
        FeatureVector(
            zS: try require(row.zS, name: "z_s"),
            zT: try require(row.zT, name: "z_t"),
            f: try require(row.f, name: "f"),
            airAlertMinutes: Double(try require(row.details.airAlertMinutes, name: "air_alert_minutes")),
            trafficScore: try require(row.details.trafficScore, name: "traffic_score"),
            powerScore: try require(row.details.powerScore, name: "power_score"),
            weatherScore: try require(row.details.weatherScore, name: "weather_score")
        )
    }
}

extension AttendanceMLPFeatureBuilder {
    struct FeatureVector: Equatable {
        let zS: Double
        let zT: Double
        let f: Double
        let airAlertMinutes: Double
        let trafficScore: Double
        let powerScore: Double
        let weatherScore: Double

        var orderedValues: [Double] {
            [
                zS,
                zT,
                f,
                airAlertMinutes,
                trafficScore,
                powerScore,
                weatherScore
            ]
        }
    }

    struct ResultRow {
        let zS: Double?
        let zT: Double?
        let f: Double?
        let details: AttendanceAnalysisDebugDetails
    }
}

private extension AttendanceMLPFeatureBuilder {
    func require<T>(_ value: T?, name: String) throws -> T {
        guard let value else {
            throw Abort(.failedDependency, reason: "Attendance MLP feature is missing: \(name)")
        }
        return value
    }
}
