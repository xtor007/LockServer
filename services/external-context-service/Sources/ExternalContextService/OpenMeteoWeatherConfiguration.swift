import Foundation

struct OpenMeteoWeatherConfiguration {
    let city: String
    let sourceName: String
    let forecastSourceURL: String
    let historicalSourceURL: String
    let latitude: Double
    let longitude: Double
    let queryTimeZone: String
    let hourlyFields: [String]
}

extension OpenMeteoWeatherConfiguration {
    static let kyivDefault = OpenMeteoWeatherConfiguration(
        city: "kyiv",
        sourceName: "open-meteo",
        forecastSourceURL: "https://api.open-meteo.com/v1/forecast",
        historicalSourceURL: "https://archive-api.open-meteo.com/v1/archive",
        latitude: 50.4501,
        longitude: 30.5234,
        queryTimeZone: "GMT",
        hourlyFields: [
            "weather_code",
            "precipitation",
            "temperature_2m",
            "visibility"
        ]
    )
}
