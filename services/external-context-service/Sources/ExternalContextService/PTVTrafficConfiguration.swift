import Foundation

struct PTVTrafficConfiguration {
    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double
    }

    struct RepresentativeRoute: Codable, Equatable {
        let label: String
        let from: Coordinate
        let to: Coordinate
    }

    let city: String
    let sourceName: String
    let sourceURL: String
    let profile: String
    let representativeRoutes: [RepresentativeRoute]

    static let kyivDefault = PTVTrafficConfiguration(
        city: "Kyiv",
        sourceName: "ptv-developer-routing",
        sourceURL: "https://api.myptv.com/routing/v1/routes",
        profile: "EUR_CAR",
        representativeRoutes: [
            RepresentativeRoute(
                label: "north_to_center",
                from: Coordinate(latitude: 50.5206, longitude: 30.4990),
                to: Coordinate(latitude: 50.4501, longitude: 30.5234)
            ),
            RepresentativeRoute(
                label: "west_to_center",
                from: Coordinate(latitude: 50.4547, longitude: 30.3922),
                to: Coordinate(latitude: 50.4501, longitude: 30.5234)
            ),
            RepresentativeRoute(
                label: "east_to_center",
                from: Coordinate(latitude: 50.4526, longitude: 30.6644),
                to: Coordinate(latitude: 50.4501, longitude: 30.5234)
            ),
            RepresentativeRoute(
                label: "south_to_center",
                from: Coordinate(latitude: 50.3689, longitude: 30.6046),
                to: Coordinate(latitude: 50.4501, longitude: 30.5234)
            )
        ]
    )
}
