import Foundation
import LockServerContracts

struct TrafficSourceAggregate: Codable, Equatable {
    let providerMode: String
    let representativeRouteCount: Int
    let averageTravelTimeMinutes: Double
    let averageTrafficDelayMinutes: Double
    let averageEffectiveSpeedKph: Double
}

enum TrafficContextAggregator {
    static func makeSourceAggregate(providerMode: String, routes: [PTVTrafficRouteSnapshot]) -> TrafficSourceAggregate {
        let travelTimeMinutes = routes.map { $0.travelTimeSeconds / 60 }
        let trafficDelayMinutes = routes.map { $0.trafficDelaySeconds / 60 }
        let effectiveSpeedKph = routes.map(makeEffectiveSpeedKph)

        return TrafficSourceAggregate(
            providerMode: providerMode,
            representativeRouteCount: routes.count,
            averageTravelTimeMinutes: round4(average(of: travelTimeMinutes)),
            averageTrafficDelayMinutes: round4(average(of: trafficDelayMinutes)),
            averageEffectiveSpeedKph: round4(average(of: effectiveSpeedKph))
        )
    }

    static func makeResolvedValue(sourceAggregate: TrafficSourceAggregate) -> TrafficContextResolvedValue {
        TrafficContextResolvedValue(
            trafficScore: round1(
                congestionScore(
                    averageEffectiveSpeedKph: sourceAggregate.averageEffectiveSpeedKph,
                    averageTrafficDelayMinutes: sourceAggregate.averageTrafficDelayMinutes
                )
            )
        )
    }
}

private extension TrafficContextAggregator {
    static func makeEffectiveSpeedKph(_ route: PTVTrafficRouteSnapshot) -> Double {
        let distanceKilometers = route.distanceMeters / 1_000
        let travelTimeMinutes = route.travelTimeSeconds / 60
        return travelTimeMinutes > 0 ? distanceKilometers / (travelTimeMinutes / 60) : 0
    }

    static func average(of values: [Double]) -> Double {
        guard values.isEmpty == false else {
            return 0
        }
        return values.reduce(0, +) / Double(values.count)
    }

    static func congestionScore(averageEffectiveSpeedKph: Double, averageTrafficDelayMinutes: Double) -> Double {
        let speedScore = clamp((45 - averageEffectiveSpeedKph) / 3.5)
        let delayScore = clamp(averageTrafficDelayMinutes / 2)
        return max(speedScore, delayScore)
    }

    static func round4(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 10)
    }
}
