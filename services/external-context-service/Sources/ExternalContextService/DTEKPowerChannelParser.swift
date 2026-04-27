import Foundation

struct DTEKPowerCitySignal: Codable, Equatable {
    let publishedAt: Date
    let text: String
}

enum DTEKPowerChannelParser {
    static func parseSignals(from html: String) -> [DTEKPowerCitySignal] {
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return messageRegex.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard
                let textRange = Range(match.range(at: 1), in: html),
                let datetimeRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }

            let text = normalizeText(html[textRange])
            let publishedAt = parseDate(String(html[datetimeRange]))

            guard text.isEmpty == false, let publishedAt else {
                return nil
            }

            return DTEKPowerCitySignal(publishedAt: publishedAt, text: text)
        }
    }
}

private extension DTEKPowerChannelParser {
    static let messageRegex = try! NSRegularExpression(
        pattern: #"<div class="tgme_widget_message_text js-message_text" dir="auto">(.*?)</div>.*?<time datetime="([^"]+)""#,
        options: [.dotMatchesLineSeparators]
    )

    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func normalizeText(_ htmlFragment: Substring) -> String {
        let withBreaks = htmlFragment
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")

        let withoutTags = withBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        let decoded = decodeEntities(withoutTags)
        return decoded
            .replacingOccurrences(of: "[\\t\\r ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#33;", with: "!")
    }
}
