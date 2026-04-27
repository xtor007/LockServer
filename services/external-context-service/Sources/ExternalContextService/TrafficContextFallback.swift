import Foundation

enum TrafficContextFallback {
    static func makeSourceAggregate(for arrivalTime: Date) -> TrafficSourceAggregate {
        let hour = Calendar(identifier: .gregorian).component(.hour, from: arrivalTime)
        let profile = profile(for: hour)
        let travelTimeMinutes = (referenceDistanceKilometers / profile.averageEffectiveSpeedKph) * 60

        return TrafficSourceAggregate(
            providerMode: "FALLBACK_FIXTURE",
            representativeRouteCount: 4,
            averageTravelTimeMinutes: round4(travelTimeMinutes),
            averageTrafficDelayMinutes: round4(profile.averageTrafficDelayMinutes),
            averageEffectiveSpeedKph: round4(profile.averageEffectiveSpeedKph)
        )
    }
}

private extension TrafficContextFallback {
    static let referenceDistanceKilometers = 13.5

    struct Profile {
        let averageEffectiveSpeedKph: Double
        let averageTrafficDelayMinutes: Double
    }

    static func profile(for hour: Int) -> Profile {
        switch hour {
        case 6:
            return Profile(averageEffectiveSpeedKph: 35, averageTrafficDelayMinutes: 0.5)
        case 7:
            return Profile(averageEffectiveSpeedKph: 31, averageTrafficDelayMinutes: 1.5)
        case 8:
            return Profile(averageEffectiveSpeedKph: 27, averageTrafficDelayMinutes: 2)
        case 9:
            return Profile(averageEffectiveSpeedKph: 24.5, averageTrafficDelayMinutes: 3)
        case 10:
            return Profile(averageEffectiveSpeedKph: 29, averageTrafficDelayMinutes: 1.5)
        case 22:
            return Profile(averageEffectiveSpeedKph: 41, averageTrafficDelayMinutes: 0)
        default:
            return Profile(averageEffectiveSpeedKph: 33, averageTrafficDelayMinutes: 1)
        }
    }

    static func round4(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
