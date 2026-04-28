import Foundation

public enum EnvironmentValueError: Error {
    case missing(String)
    case invalidInt(String, String)
    case invalidDouble(String, String)
}

public enum EnvironmentValue {
    public static func string(_ key: String, default defaultValue: String? = nil) throws -> String {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        if let defaultValue {
            return defaultValue
        }
        throw EnvironmentValueError.missing(key)
    }

    public static func int(_ key: String, default defaultValue: Int? = nil) throws -> Int {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            guard let intValue = Int(value) else {
                throw EnvironmentValueError.invalidInt(key, value)
            }
            return intValue
        }
        if let defaultValue {
            return defaultValue
        }
        throw EnvironmentValueError.missing(key)
    }

    public static func double(_ key: String, default defaultValue: Double? = nil) throws -> Double {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            guard let doubleValue = Double(value) else {
                throw EnvironmentValueError.invalidDouble(key, value)
            }
            return doubleValue
        }
        if let defaultValue {
            return defaultValue
        }
        throw EnvironmentValueError.missing(key)
    }

    public static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let value = ProcessInfo.processInfo.environment[key]?.lowercased() else {
            return defaultValue
        }
        return ["1", "true", "yes", "on"].contains(value)
    }
}
