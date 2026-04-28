import Foundation

public enum ServiceEndpoints {
    public static func authBaseURL() throws -> String {
        try baseURL(hostKey: "LOCKSERVER_AUTH_HOST", portKey: "LOCKSERVER_AUTH_PORT", defaultPort: 8081)
    }

    public static func directoryBaseURL() throws -> String {
        try baseURL(hostKey: "LOCKSERVER_DIRECTORY_HOST", portKey: "LOCKSERVER_DIRECTORY_PORT", defaultPort: 8082)
    }

    public static func accessBaseURL() throws -> String {
        try baseURL(hostKey: "LOCKSERVER_ACCESS_HOST", portKey: "LOCKSERVER_ACCESS_PORT", defaultPort: 8083)
    }

    public static func deviceBaseURL() throws -> String {
        try baseURL(hostKey: "LOCKSERVER_DEVICE_HOST", portKey: "LOCKSERVER_DEVICE_PORT", defaultPort: 8084)
    }

    public static func attendanceAnalysisBaseURL() throws -> String {
        try baseURL(hostKey: "LOCKSERVER_ATTENDANCE_ANALYSIS_HOST", portKey: "LOCKSERVER_ATTENDANCE_ANALYSIS_PORT", defaultPort: 8085)
    }

    public static func externalContextBaseURL() throws -> String {
        try baseURL(hostKey: "LOCKSERVER_EXTERNAL_CONTEXT_HOST", portKey: "LOCKSERVER_EXTERNAL_CONTEXT_PORT", defaultPort: 8086)
    }

    public static func mlpBaseURL() throws -> String {
        try baseURL(hostKey: "LOCKSERVER_MLP_HOST", portKey: "LOCKSERVER_MLP_PORT", defaultPort: 8087)
    }

    private static func baseURL(hostKey: String, portKey: String, defaultPort: Int) throws -> String {
        let host = try EnvironmentValue.string(hostKey, default: "127.0.0.1")
        let port = try EnvironmentValue.int(portKey, default: defaultPort)
        return "http://\(host):\(port)"
    }
}
