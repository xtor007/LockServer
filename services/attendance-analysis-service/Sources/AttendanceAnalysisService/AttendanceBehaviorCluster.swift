import Foundation

enum AttendanceBehaviorCluster: String, CaseIterable, Codable {
    case stableNormal = "stable_normal"
    case flexibleNormal = "flexible_normal"
    case episodicDeficit = "episodic_deficit"
    case systematicAnomaly = "systematic_anomaly"

    static let technicalOutlierName = "Technical Outlier"

    var displayName: String {
        switch self {
        case .stableNormal:
            return "Stable Normal"
        case .flexibleNormal:
            return "Flexible Normal"
        case .episodicDeficit:
            return "Episodic Deficit"
        case .systematicAnomaly:
            return "Systematic Anomaly"
        }
    }

    var severityWeight: Double {
        switch self {
        case .stableNormal:
            return 0.0
        case .flexibleNormal:
            return 0.2
        case .episodicDeficit:
            return 0.5
        case .systematicAnomaly:
            return 0.8
        }
    }

    var semanticAnchor: [Double] {
        switch self {
        case .stableNormal:
            return [0.0, 0.0, 0.0]
        case .flexibleNormal:
            return [0.5, 0.45, 0.02]
        case .episodicDeficit:
            return [1.4, 0.45, 0.09]
        case .systematicAnomaly:
            return [2.6, 0.8, 0.58]
        }
    }

    var pipelineStatus: AttendanceAnalysisStatus {
        switch self {
        case .stableNormal:
            return .clusteringTerminalStableNormal
        case .flexibleNormal, .episodicDeficit, .systematicAnomaly:
            return .readyForNextStage
        }
    }

    var clusteringStatus: AttendanceClusteringStatus {
        switch self {
        case .stableNormal:
            return .stableNormalTerminal
        case .flexibleNormal, .episodicDeficit, .systematicAnomaly:
            return .readyForNextStage
        }
    }
}
