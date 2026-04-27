import Foundation
import Vapor

struct AttendanceClusteringEngine {
    struct FeatureVector: Codable, Equatable {
        let zS: Double
        let zT: Double
        let f: Double

        var values: [Double] {
            [zS, zT, f]
        }

        var semanticValues: [Double] {
            [zS, abs(zT), f]
        }
    }

    struct TrainingPoint: Equatable {
        let resultId: UUID
        let userId: UUID
        let day: AttendanceDay
        let vector: FeatureVector
    }

    struct Normalization: Codable, Equatable {
        let means: [Double]
        let standardDeviations: [Double]
    }

    struct ClusterDefinition: Codable, Equatable {
        let behaviorKey: String
        let name: String
        let weight: Double
    }

    struct Cluster: Codable, Equatable {
        let behaviorKey: String
        let name: String
        let weight: Double
        let centroid: [Double]
        let trustRadius: Double
    }

    struct ModelSnapshot: Codable, Equatable {
        let version: Int
        let normalization: Normalization
        let clusters: [Cluster]
    }

    struct Assignment: Equatable {
        let status: AttendanceAnalysisStatus
        let clusteringStatus: AttendanceClusteringStatus
        let clusterName: String
        let clusterScore: Double?
        let clusterWeight: Double?
        let clusterDistance: Double
        let clusterModelVersion: Int
        let clusteringNotes: [String]?
    }

    private let epsilon = 0.0001
    private let minimumTrustRadius = 0.75
    private let maximumIterations = 50

    func train(points: [TrainingPoint], version: Int) throws -> ModelSnapshot {
        guard points.count >= AttendanceBehaviorCluster.allCases.count else {
            throw Abort(.failedDependency, reason: "At least four signal-ready attendance days are required to train the clustering model")
        }

        let normalization = makeNormalization(for: points.map(\.vector))
        let normalizedPoints = points.map { normalize($0.vector, using: normalization) }
        var centroids = makeInitialCentroids(points: points.map(\.vector), normalizedPoints: normalizedPoints)

        for _ in 0..<maximumIterations {
            let assignments = assignToNearestCentroids(points: normalizedPoints, centroids: centroids)
            let groups = grouped(points: normalizedPoints, assignments: assignments, centroidCount: centroids.count)

            var updatedCentroids = centroids
            var didMove = false

            for index in centroids.indices {
                if groups[index].isEmpty {
                    let replacementPoint = replacementCentroidPoint(
                        points: normalizedPoints,
                        assignments: assignments,
                        centroids: centroids
                    )
                    updatedCentroids[index] = replacementPoint
                    didMove = true
                    continue
                }

                let newCentroid = mean(groups[index])
                if distance(from: newCentroid, to: centroids[index]) > epsilon {
                    didMove = true
                }
                updatedCentroids[index] = newCentroid
            }

            centroids = updatedCentroids

            if didMove == false {
                break
            }
        }

        let assignments = assignToNearestCentroids(points: normalizedPoints, centroids: centroids)
        let radii = makeTrustRadii(points: normalizedPoints, assignments: assignments, centroids: centroids)
        let rawCentroids = centroids.map { denormalize($0, using: normalization) }
        let definitions = matchDefinitions(to: rawCentroids)

        let clusters = centroids.indices.map { index in
            let behavior = definitions[index]
            return Cluster(
                behaviorKey: behavior.rawValue,
                name: behavior.displayName,
                weight: round(behavior.severityWeight),
                centroid: round(centroids[index]),
                trustRadius: round(radii[index])
            )
        }

        return ModelSnapshot(version: version, normalization: normalization, clusters: clusters)
    }

    func assign(_ vector: FeatureVector, using model: ModelSnapshot) -> Assignment {
        let normalized = normalize(vector, using: model.normalization)
        let distances = model.clusters.map { distance(from: normalized, to: $0.centroid) }
        let trustedIndices = distances.indices.filter { distances[$0] <= model.clusters[$0].trustRadius }
        let nearestDistance = round(distances.min() ?? 0)

        guard let assignedIndex = trustedIndices.min(by: { distances[$0] < distances[$1] }) else {
            return Assignment(
                status: .clusteringTechnicalOutlier,
                clusteringStatus: .technicalOutlier,
                clusterName: AttendanceBehaviorCluster.technicalOutlierName,
                clusterScore: nil,
                clusterWeight: nil,
                clusterDistance: nearestDistance,
                clusterModelVersion: model.version,
                clusteringNotes: ["outside_all_cluster_trust_radii"]
            )
        }

        let cluster = model.clusters[assignedIndex]
        let behavior = AttendanceBehaviorCluster(rawValue: cluster.behaviorKey) ?? .systematicAnomaly

        return Assignment(
            status: behavior.pipelineStatus,
            clusteringStatus: behavior.clusteringStatus,
            clusterName: cluster.name,
            clusterScore: round(cluster.weight),
            clusterWeight: round(cluster.weight),
            clusterDistance: round(distances[assignedIndex]),
            clusterModelVersion: model.version,
            clusteringNotes: nil
        )
    }
}

private extension AttendanceClusteringEngine {
    func makeNormalization(for vectors: [FeatureVector]) -> Normalization {
        let rawVectors = vectors.map(\.values)
        let means = (0..<3).map { index in
            rawVectors.map { $0[index] }.reduce(0, +) / Double(rawVectors.count)
        }
        let standardDeviations = (0..<3).map { index -> Double in
            let values = rawVectors.map { $0[index] }
            let variance = values.reduce(0) { partialResult, value in
                partialResult + pow(value - means[index], 2)
            } / Double(values.count)
            let stddev = sqrt(variance)
            return stddev > 0 ? stddev : 1
        }

        return Normalization(
            means: round(means),
            standardDeviations: round(standardDeviations)
        )
    }

    func normalize(_ vector: FeatureVector, using normalization: Normalization) -> [Double] {
        zip(vector.values.indices, vector.values).map { index, value in
            (value - normalization.means[index]) / normalization.standardDeviations[index]
        }
    }

    func denormalize(_ values: [Double], using normalization: Normalization) -> FeatureVector {
        FeatureVector(
            zS: values[0] * normalization.standardDeviations[0] + normalization.means[0],
            zT: values[1] * normalization.standardDeviations[1] + normalization.means[1],
            f: values[2] * normalization.standardDeviations[2] + normalization.means[2]
        )
    }

    func makeInitialCentroids(points: [FeatureVector], normalizedPoints: [[Double]]) -> [[Double]] {
        var usedIndices = Set<Int>()
        var centroids = [[Double]]()

        for behavior in AttendanceBehaviorCluster.allCases {
            let rankedIndices = points.indices.sorted { lhs, rhs in
                semanticDistance(from: points[lhs].semanticValues, to: behavior.semanticAnchor) < semanticDistance(from: points[rhs].semanticValues, to: behavior.semanticAnchor)
            }
            let selectedIndex = rankedIndices.first(where: { usedIndices.contains($0) == false }) ?? rankedIndices.first ?? 0
            usedIndices.insert(selectedIndex)
            centroids.append(normalizedPoints[selectedIndex])
        }

        return centroids
    }

    func assignToNearestCentroids(points: [[Double]], centroids: [[Double]]) -> [Int] {
        points.map { point in
            centroids.indices.min(by: { distance(from: point, to: centroids[$0]) < distance(from: point, to: centroids[$1]) }) ?? 0
        }
    }

    func grouped(points: [[Double]], assignments: [Int], centroidCount: Int) -> [[[Double]]] {
        var result = Array(repeating: [[Double]](), count: centroidCount)

        for (index, assignment) in assignments.enumerated() where result.indices.contains(assignment) {
            result[assignment].append(points[index])
        }

        return result
    }

    func replacementCentroidPoint(points: [[Double]], assignments: [Int], centroids: [[Double]]) -> [Double] {
        guard let farthestIndex = points.indices.max(by: {
            distance(from: points[$0], to: centroids[assignments[$0]]) < distance(from: points[$1], to: centroids[assignments[$1]])
        }) else {
            return centroids.first ?? [0, 0, 0]
        }

        return points[farthestIndex]
    }

    func makeTrustRadii(points: [[Double]], assignments: [Int], centroids: [[Double]]) -> [Double] {
        let groupedDistances = centroids.indices.map { index in
            points.indices.compactMap { pointIndex -> Double? in
                guard assignments[pointIndex] == index else {
                    return nil
                }
                return distance(from: points[pointIndex], to: centroids[index])
            }
        }

        return groupedDistances.map { distances in
            guard distances.isEmpty == false else {
                return minimumTrustRadius
            }

            let sorted = distances.sorted()
            let percentileIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
            let percentile = sorted[percentileIndex]
            let meanDistance = sorted.reduce(0, +) / Double(sorted.count)
            let variance = sorted.reduce(0) { partialResult, value in
                partialResult + pow(value - meanDistance, 2)
            } / Double(sorted.count)
            let stddev = sqrt(variance)

            return max(percentile, meanDistance + (2 * stddev), minimumTrustRadius)
        }
    }

    func matchDefinitions(to rawCentroids: [FeatureVector]) -> [AttendanceBehaviorCluster] {
        let clusters = AttendanceBehaviorCluster.allCases
        let centroidIndices = Array(rawCentroids.indices)
        let permutations = permutations(of: Array(clusters.indices))

        let bestPermutation = permutations.min { lhs, rhs in
            totalMatchingCost(centroidIndices: centroidIndices, behaviorIndices: lhs, rawCentroids: rawCentroids, behaviors: clusters) <
                totalMatchingCost(centroidIndices: centroidIndices, behaviorIndices: rhs, rawCentroids: rawCentroids, behaviors: clusters)
        } ?? Array(clusters.indices)

        return bestPermutation.map { clusters[$0] }
    }

    func totalMatchingCost(
        centroidIndices: [Int],
        behaviorIndices: [Int],
        rawCentroids: [FeatureVector],
        behaviors: [AttendanceBehaviorCluster]
    ) -> Double {
        zip(centroidIndices, behaviorIndices).reduce(0) { partialResult, pair in
            partialResult + semanticDistance(from: rawCentroids[pair.0].semanticValues, to: behaviors[pair.1].semanticAnchor)
        }
    }

    func permutations(of values: [Int]) -> [[Int]] {
        guard values.count > 1 else {
            return [values]
        }

        var result = [[Int]]()

        for (index, value) in values.enumerated() {
            var remaining = values
            remaining.remove(at: index)
            for tail in permutations(of: remaining) {
                result.append([value] + tail)
            }
        }

        return result
    }

    func semanticDistance(from lhs: [Double], to rhs: [Double]) -> Double {
        let weights = [1.4, 1.0, 1.8]
        let squared = zip(zip(lhs, rhs), weights).reduce(0) { partialResult, tuple in
            let values = tuple.0
            let weight = tuple.1
            return partialResult + pow(values.0 - values.1, 2) * weight
        }
        return sqrt(squared)
    }

    func mean(_ points: [[Double]]) -> [Double] {
        guard let first = points.first else {
            return [0, 0, 0]
        }

        return first.indices.map { index in
            points.map { $0[index] }.reduce(0, +) / Double(points.count)
        }
    }

    func distance(from lhs: [Double], to rhs: [Double]) -> Double {
        sqrt(zip(lhs, rhs).reduce(0) { partialResult, values in
            partialResult + pow(values.0 - values.1, 2)
        })
    }

    func round(_ value: Double, scale: Double = 10_000) -> Double {
        (value * scale).rounded() / scale
    }

    func round(_ values: [Double], scale: Double = 10_000) -> [Double] {
        values.map { round($0, scale: scale) }
    }
}
