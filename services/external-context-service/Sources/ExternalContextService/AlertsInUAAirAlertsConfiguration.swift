import Foundation

struct AlertsInUAAirAlertsConfiguration {
    let city: String
    let regionUID: String
    let historyPeriod: String
    let sourceName: String
    let sourceURL: String
    let currentDayRefreshIntervalMinutes: Int

    static let kyivDefault = AlertsInUAAirAlertsConfiguration(
        city: "Kyiv",
        regionUID: "31",
        historyPeriod: "month_ago",
        sourceName: "alerts-in-ua-history",
        sourceURL: "https://api.alerts.in.ua/v1/regions/31/alerts/month_ago.json",
        currentDayRefreshIntervalMinutes: 10
    )
}
