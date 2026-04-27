import XCTest
@testable import ExternalContextService

final class TrafficContextAggregatorTests: XCTestCase {
    func testBuildsMinimalTrafficScoreFromRepresentativeRoutes() {
        let sourceAggregate = TrafficContextAggregator.makeSourceAggregate(
            providerMode: "AVERAGE",
            routes: [
                PTVTrafficRouteSnapshot(label: "north_to_center", distanceMeters: 12_000, travelTimeSeconds: 1_800, trafficDelaySeconds: 0),
                PTVTrafficRouteSnapshot(label: "west_to_center", distanceMeters: 10_000, travelTimeSeconds: 1_500, trafficDelaySeconds: 0),
                PTVTrafficRouteSnapshot(label: "east_to_center", distanceMeters: 14_000, travelTimeSeconds: 2_520, trafficDelaySeconds: 0),
                PTVTrafficRouteSnapshot(label: "south_to_center", distanceMeters: 11_000, travelTimeSeconds: 2_160, trafficDelaySeconds: 0)
            ]
        )
        let resolvedValue = TrafficContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.providerMode, "AVERAGE")
        XCTAssertEqual(sourceAggregate.representativeRouteCount, 4)
        XCTAssertEqual(sourceAggregate.averageTravelTimeMinutes, 33.25)
        XCTAssertEqual(sourceAggregate.averageEffectiveSpeedKph, 21.5833)
        XCTAssertEqual(sourceAggregate.averageTrafficDelayMinutes, 0)
        XCTAssertEqual(resolvedValue.trafficScore, 6.7)
    }

    func testCapsTrafficScoreAtTenForVerySlowTraffic() {
        let sourceAggregate = TrafficContextAggregator.makeSourceAggregate(
            providerMode: "REALISTIC",
            routes: [
                PTVTrafficRouteSnapshot(label: "a", distanceMeters: 8_000, travelTimeSeconds: 2_700, trafficDelaySeconds: 1_200),
                PTVTrafficRouteSnapshot(label: "b", distanceMeters: 7_500, travelTimeSeconds: 2_880, trafficDelaySeconds: 1_500)
            ]
        )
        let resolvedValue = TrafficContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.averageTrafficDelayMinutes, 22.5)
        XCTAssertEqual(resolvedValue.trafficScore, 10)
    }
}
