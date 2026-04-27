import Foundation

struct MockAirAlertsConfiguration {
    let city: String
    let sourceName: String
    let sourceURL: String
    let minimumIntervalsPerDay: Int
    let maximumIntervalsPerDay: Int
    let minimumDurationMinutes: Int
    let maximumDurationMinutes: Int
    let minimumGapMinutes: Int
    let maximumGapMinutes: Int

    static let kyivDefault = MockAirAlertsConfiguration(
        city: "Kyiv",
        sourceName: "mock-air-alerts-randomized",
        sourceURL: "mock://kyiv/air-alerts",
        minimumIntervalsPerDay: 1,
        maximumIntervalsPerDay: 4,
        minimumDurationMinutes: 25,
        maximumDurationMinutes: 140,
        minimumGapMinutes: 45,
        maximumGapMinutes: 240
    )
}
