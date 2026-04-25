import Foundation

public enum RandomStringGenerator {
    public static func lowercaseLetters(length: Int) -> String {
        random(length: length, alphabet: "abcdefghijklmnopqrstuvwxyz")
    }

    public static func alphanumeric(length: Int) -> String {
        random(length: length, alphabet: "0123456789abcdefghijklmnopqrstuvwxyz")
    }

    private static func random(length: Int, alphabet: String) -> String {
        String((0..<length).compactMap { _ in
            alphabet.randomElement()
        })
    }
}
