import Foundation
import LockServerContracts
import Vapor

enum AttendanceAnalysisStatus: String, Codable {
    case observationBuilt = "observation_built"
    case signalsReady = "signals_ready"
    case technicalAnomaly = "technical_anomaly"
    case insufficientHistory = "insufficient_history"
    case notReady = "not_ready"
    case clusteringTerminalStableNormal = "clustering_terminal_stable_normal"
    case clusteringTechnicalOutlier = "clustering_technical_outlier"
    case readyForNextStage = "ready_for_next_stage"
}

enum AttendanceClusteringStatus: String, Codable {
    case notStarted = "not_started"
    case notApplicable = "not_applicable"
    case stableNormalTerminal = "stable_normal_terminal"
    case readyForNextStage = "ready_for_next_stage"
    case technicalOutlier = "technical_outlier"
}

enum AttendanceMLPStatus: String, Codable {
    case notReady = "not_ready"
    case failed = "failed"
    case ready = "ready"
    case manuallyCorrected = "manually_corrected"
}

struct AttendanceObservationCommandRequest: Content {
    let userId: UUID
    let day: String
}

struct AttendanceObservationBatchCommandRequest: Content {
    let day: String
}

struct AttendanceClusteringCommandRequest: Content {
    let day: String
    let userId: UUID?
}

struct AttendanceMLPCommandRequest: Content {
    let day: String
    let userId: UUID?
}

struct AttendanceMLPFeedbackRequest: Content {
    let userId: UUID
    let day: String
    let etaNn: Double
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

struct AttendanceClusteringRunResponse: Content {
    let day: String
    let userId: UUID?
    let processedCount: Int
    let clusteredCount: Int
    let skippedCount: Int
    let wasRebuilt: Bool
    let modelVersion: Int?
    let items: [AttendanceClusteringRunItemResponse]
}

struct AttendanceClusteringRunItemResponse: Content {
    let userId: UUID
    let day: String
    let status: String
    let clusteringStatus: String?
    let wasClustered: Bool
    let result: AttendanceAnalysisResultResponse
}

struct AttendanceMLPRunResponse: Content {
    let day: String
    let userId: UUID?
    let processedCount: Int
    let inferredCount: Int
    let failedCount: Int
    let skippedCount: Int
    let wasRebuilt: Bool
    let modelVersion: String?
    let items: [AttendanceMLPRunItemResponse]
}

struct AttendanceMLPRunItemResponse: Content {
    let userId: UUID
    let day: String
    let status: String
    let mlpStatus: String?
    let wasInferred: Bool
    let etaNN: Double?
    let mlpModelVersion: String?
    let result: AttendanceAnalysisResultResponse
}

struct AttendanceMLPFeedbackResponse: Content {
    let feedbackSampleId: UUID
    let pendingFeedbackCount: Int
    let retrainingTriggered: Bool
    let retrainedModelVersion: String?
    let retrainingError: String?
    let result: AttendanceAnalysisResultResponse
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
    let clusterName: String?
    let clusterScore: Double?
    let clusterWeight: Double?
    let clusterModelVersion: Int?
    let clusterDistance: Double?
    let clusteringStatus: String?
    let etaNN: Double?
    let mlpModelVersion: String?
    let mlpStatus: String?
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
    let airAlertIntervals: [AirAlertInterval]?
    let airAlertMinutes: Int?
    let trafficScore: Double?
    let powerScore: Double?
    let weatherScore: Double?
    let weatherContext: WeatherContextResolvedValue?
    let externalContextNotes: [String]?
    let clusterName: String?
    let clusterScore: Double?
    let clusterWeight: Double?
    let clusterModelVersion: Int?
    let clusterDistance: Double?
    let clusteringStatus: String?
    let clusteringNotes: [String]?

    init(
        workNormMinutes: Int,
        rawEventCount: Int,
        rawEvents: [AttendanceDebugEvent],
        sessionStartsCount: Int,
        completedSessionsCount: Int,
        sessionRanges: [AttendanceDebugSession],
        anomalyReasons: [String],
        note: String?,
        baselineWindowDays: Int?,
        historyDaysUsed: Int?,
        baselineHistoryDays: [AttendanceBaselineHistoryDebugDay]?,
        deficitHistoryDaysCount: Int?,
        averageStartMinutes: Double?,
        stddevStartMinutes: Double?,
        stddevWorkedMinutes: Double?,
        zS: Double?,
        zT: Double?,
        f: Double?,
        calculationNotes: [String]?,
        airAlertIntervals: [AirAlertInterval]? = nil,
        airAlertMinutes: Int? = nil,
        trafficScore: Double? = nil,
        powerScore: Double? = nil,
        weatherScore: Double? = nil,
        weatherContext: WeatherContextResolvedValue? = nil,
        externalContextNotes: [String]? = nil,
        clusterName: String? = nil,
        clusterScore: Double? = nil,
        clusterWeight: Double? = nil,
        clusterModelVersion: Int? = nil,
        clusterDistance: Double? = nil,
        clusteringStatus: String? = nil,
        clusteringNotes: [String]? = nil
    ) {
        self.workNormMinutes = workNormMinutes
        self.rawEventCount = rawEventCount
        self.rawEvents = rawEvents
        self.sessionStartsCount = sessionStartsCount
        self.completedSessionsCount = completedSessionsCount
        self.sessionRanges = sessionRanges
        self.anomalyReasons = anomalyReasons
        self.note = note
        self.baselineWindowDays = baselineWindowDays
        self.historyDaysUsed = historyDaysUsed
        self.baselineHistoryDays = baselineHistoryDays
        self.deficitHistoryDaysCount = deficitHistoryDaysCount
        self.averageStartMinutes = averageStartMinutes
        self.stddevStartMinutes = stddevStartMinutes
        self.stddevWorkedMinutes = stddevWorkedMinutes
        self.zS = zS
        self.zT = zT
        self.f = f
        self.calculationNotes = calculationNotes
        self.airAlertIntervals = airAlertIntervals
        self.airAlertMinutes = airAlertMinutes
        self.trafficScore = trafficScore
        self.powerScore = powerScore
        self.weatherScore = weatherScore
        self.weatherContext = weatherContext
        self.externalContextNotes = externalContextNotes
        self.clusterName = clusterName
        self.clusterScore = clusterScore
        self.clusterWeight = clusterWeight
        self.clusterModelVersion = clusterModelVersion
        self.clusterDistance = clusterDistance
        self.clusteringStatus = clusteringStatus
        self.clusteringNotes = clusteringNotes
    }
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
    let clusterName: String?
    let clusterScore: Double?
    let clusterWeight: Double?
    let clusterModelVersion: Int?
    let clusterDistance: Double?
    let clusteringStatus: AttendanceClusteringStatus
    let etaNN: Double?
    let mlpModelVersion: String?
    let mlpStatus: AttendanceMLPStatus
    let details: AttendanceAnalysisDebugDetails
}
