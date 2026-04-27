import Foundation
import XCTest
@testable import ExternalContextService

final class PowerContextAggregatorTests: XCTestCase {
    func testParsesTelegramSignalWithTimestamp() {
        let html = """
        <div class="tgme_widget_message_text js-message_text" dir="auto">Київ: за командою Укренерго застосовано екстрені відключення</div>
        <time datetime="2026-04-03T08:53:24+00:00"></time>
        """

        let signals = DTEKPowerChannelParser.parseSignals(from: html)

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.text, "Київ: за командою Укренерго застосовано екстрені відключення")
        XCTAssertEqual(signals.first?.publishedAt, isoDate("2026-04-03T08:53:24Z"))
    }

    func testMapsEmergencyKyivSignalToScoreTen() {
        let signals = [
            DTEKPowerCitySignal(
                publishedAt: isoDate("2026-04-03T08:53:24Z"),
                text: "Київ: за командою Укренерго застосовано екстрені відключення"
            )
        ]

        let sourceAggregate = PowerContextAggregator.makeSourceAggregate(
            arrivalTime: isoDate("2026-04-03T09:00:00Z"),
            maxSignalAgeHours: 24,
            signals: signals
        )
        let resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.signalType, "emergency_outage")
        XCTAssertEqual(resolvedValue.powerScore, 10)
    }

    func testReturnsZeroWhenNoApplicableOutageSignalExists() {
        let signals = [
            DTEKPowerCitySignal(
                publishedAt: isoDate("2026-04-25T05:00:00Z"),
                text: "Київ: за командою Укренерго застосовано екстрені відключення"
            )
        ]

        let sourceAggregate = PowerContextAggregator.makeSourceAggregate(
            arrivalTime: isoDate("2026-04-27T09:00:00Z"),
            maxSignalAgeHours: 24,
            signals: signals
        )
        let resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.signalType, "stable")
        XCTAssertEqual(resolvedValue.powerScore, 0)
    }

    func testMapsScheduledOutageSignalToScoreSeven() {
        let signals = [
            DTEKPowerCitySignal(
                publishedAt: isoDate("2026-04-02T17:14:13Z"),
                text: "Київ: за командою Укренерго 3 квітня застосовуються графіки відключень"
            )
        ]

        let sourceAggregate = PowerContextAggregator.makeSourceAggregate(
            arrivalTime: isoDate("2026-04-03T08:00:00Z"),
            maxSignalAgeHours: 24,
            signals: signals
        )
        let resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.signalType, "scheduled_outage")
        XCTAssertEqual(resolvedValue.powerScore, 7)
    }

    func testPrefersSameDayEmergencyOverPreviousDayScheduledOutage() {
        let signals = [
            DTEKPowerCitySignal(
                publishedAt: isoDate("2026-04-02T17:14:13Z"),
                text: "Київ: за командою Укренерго 3 квітня застосовуються графіки відключень"
            ),
            DTEKPowerCitySignal(
                publishedAt: isoDate("2026-04-03T08:53:24Z"),
                text: "Київ: за командою Укренерго застосовано екстрені відключення"
            )
        ]

        let sourceAggregate = PowerContextAggregator.makeSourceAggregate(
            arrivalTime: isoDate("2026-04-03T09:00:00Z"),
            maxSignalAgeHours: 24,
            signals: signals
        )
        let resolvedValue = PowerContextAggregator.makeResolvedValue(sourceAggregate: sourceAggregate)

        XCTAssertEqual(sourceAggregate.signalType, "emergency_outage")
        XCTAssertEqual(resolvedValue.powerScore, 10)
    }
}

private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}
