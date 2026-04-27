import Foundation

struct DTEKCityPowerConfiguration {
    let city: String
    let sourceName: String
    let sourceURL: String
    let searchQuery: String
    let maxSignalAgeHours: Int

    static let kyivDefault = DTEKCityPowerConfiguration(
        city: "Kyiv",
        sourceName: "dtek-official-telegram-kyiv-outages",
        sourceURL: "https://t.me/s/dtek_ua",
        searchQuery: "Київ графіки відключень",
        maxSignalAgeHours: 24
    )
}
