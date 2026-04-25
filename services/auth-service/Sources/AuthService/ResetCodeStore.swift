import Foundation
import LockServerCore

actor ResetCodeStore {
    private var entries = [String: (email: String, expiresAt: Date)]()

    func makeCode(for email: String) -> String {
        purgeExpired()

        var code = RandomStringGenerator.lowercaseLetters(length: 8)
        while entries[code] != nil {
            code = RandomStringGenerator.lowercaseLetters(length: 8)
        }

        entries[code] = (email, .now.addingTimeInterval(180))
        return code
    }

    func consumeEmail(for code: String) -> String? {
        purgeExpired()
        guard let entry = entries.removeValue(forKey: code), entry.expiresAt > .now else {
            return nil
        }
        return entry.email
    }

    private func purgeExpired() {
        let now = Date()
        entries = entries.filter { $0.value.expiresAt > now }
    }
}
