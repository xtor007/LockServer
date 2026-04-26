import Foundation
import Vapor

enum AttendanceAnalysisStatus: String, Codable {
    case observationBuilt = "observation_built"
    case signalsReady = "signals_ready"
    case technicalAnomaly = "technical_anomaly"
    case insufficientHistory = "insufficient_history"
    case notReady = "not_ready"
}

struct AttendanceObservationCommandRequest: Content {
    let userId: UUID
    let day: String
}

struct AttendanceObservationBatchCommandRequest: Content {
    let day: String
}

struct AttendanceObservationRunResponse: Content {
    let status: String
    let observation: AttendanceDayObservationResponse?
    let result: AttendanceAnalysisResultResponse
    let wasRebuilt: Bool
}

struct AttendanceObservationBatchResponse: Content {
    let day: String
    let processedCount: Int
    let wasRebuilt: Bool
    let items: [AttendanceObservationRunResponse]
}

struct AttendanceDayObservationsResponse: Content {
    let observations: [AttendanceDayObservationResponse]
}

struct AttendanceDayObservationResponse: Content {
    let id: UUID?
    let userId: UUID
    let day: String
    let firstEntryTime: Date?
    let workedMinutes: Int
    let breakMinutes: Int
    let sessionsCount: Int
    let isTechnicalAnomaly: Bool
    let anomalyReason: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct AttendanceAnalysisResultsResponse: Content {
    let results: [AttendanceAnalysisResultResponse]
}

struct AttendanceAnalysisResultResponse: Content {
    let id: UUID?
    let userId: UUID
    let day: String
    let status: String
    let observationId: UUID?
    let historyDaysUsed: Int
    let averageStartMinutes: Double?
    let stddevStartMinutes: Double?
    let stddevWorkedMinutes: Double?
    let workNormMinutes: Int
    let zS: Double?
    let zT: Double?
    let f: Double?
    let detailsJson: AttendanceAnalysisDebugDetails
    let createdAt: Date?
    let updatedAt: Date?
}

struct AttendanceAnalysisDebugDetails: Content, Codable, Equatable {
    let workNormMinutes: Int
    let rawEventCount: Int
    let rawEvents: [AttendanceDebugEvent]
    let sessionStartsCount: Int
    let completedSessionsCount: Int
    let sessionRanges: [AttendanceDebugSession]
    let anomalyReasons: [String]
    let note: String?
    let baselineWindowDays: Int?
    let historyDaysUsed: Int?
    let baselineHistoryDays: [AttendanceBaselineHistoryDebugDay]?
    let deficitHistoryDaysCount: Int?
    let averageStartMinutes: Double?
    let stddevStartMinutes: Double?
    let stddevWorkedMinutes: Double?
    let zS: Double?
    let zT: Double?
    let f: Double?
    let calculationNotes: [String]?
}

struct AttendanceDebugEvent: Content, Codable, Equatable {
    let type: String
    let time: Date
}

struct AttendanceDebugSession: Content, Codable, Equatable {
    let start: Date
    let end: Date
    let workedMinutes: Int
}

struct AttendanceBaselineHistoryDebugDay: Content, Codable, Equatable {
    let day: String
    let firstEntryTime: Date
    let startMinutes: Int
    let workedMinutes: Int
    let isDeficit: Bool
}

struct AttendanceObservationDraft {
    let userId: UUID
    let day: AttendanceDay
    let firstEntryTime: Date?
    let workedMinutes: Int
    let breakMinutes: Int
    let sessionsCount: Int
    let isTechnicalAnomaly: Bool
    let anomalyReason: String?
}

struct AttendanceObservationBuildOutcome {
    let status: AttendanceAnalysisStatus
    let observation: AttendanceObservationDraft?
    let details: AttendanceAnalysisDebugDetails
}

struct AttendanceAnalysisResultDraft {
    let status: AttendanceAnalysisStatus
    let observationId: UUID?
    let historyDaysUsed: Int
    let averageStartMinutes: Double?
    let stddevStartMinutes: Double?
    let stddevWorkedMinutes: Double?
    let workNormMinutes: Int
    let zS: Double?
    let zT: Double?
    let f: Double?
    let details: AttendanceAnalysisDebugDetails
}
