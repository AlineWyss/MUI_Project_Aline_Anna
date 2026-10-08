//
//  GeometryTools.swift
//  BloodCellJourney
//
//  Paths, smooth curves, tube meshes and mesh sampling.
//

import Foundation
import RealityKit
import simd

// MARK: - Sampled path

/// A polyline with pre-computed lengths, so points can be looked up by progress (0...1).
struct SampledPath {
    let points: [SIMD3<Float>]
    let cumulative: [Float]

    var length: Float { cumulative.last ?? 0 }

    init(_ points: [SIMD3<Float>]) {
        let safePoints = points.isEmpty ? [SIMD3<Float>(0, 0, 0)] : points
        var lengths: [Float] = [0]
        if safePoints.count > 1 {
            for index in 1..<safePoints.count {
                lengths.append(lengths[index - 1] + simd_distance(safePoints[index - 1], safePoints[index]))
            }
        }
        self.points = safePoints
        self.cumulative = lengths
    }

    /// Point at a normalised progress along the path.
    func point(at progress: Float) -> SIMD3<Float> {
        guard points.count > 1, length > 0 else { return points[0] }
        let distance = min(max(progress, 0), 1) * length
        var low = 0
        var high = cumulative.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulative[middle] < distance { low = middle } else { high = middle }
        }
        let segment = cumulative[high] - cumulative[low]
        let t = segment > 0 ? (distance - cumulative[low]) / segment : 0
        return simd_mix(points[low], points[high], SIMD3<Float>(repeating: t))
    }

    /// Point at a distance (metres) from the start, plus the index of the segment it lies on.
    func locate(distance: Float) -> (segment: Int, point: SIMD3<Float>) {
        guard points.count > 1, length > 0 else { return (0, points[0]) }
        let d = min(max(distance, 0), length)
        var low = 0
        var high = cumulative.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulative[middle] < d { low = middle } else { high = middle }
        }
        let segment = cumulative[high] - cumulative[low]
        let t = segment > 0 ? (d - cumulative[low]) / segment : 0
        return (low, simd_mix(points[low], points[high], SIMD3<Float>(repeating: t)))
    }

    /// Closest point on the path and its distance from the start of the path (in metres).
    func closest(to position: SIMD3<Float>) -> (along: Float, point: SIMD3<Float>) {
        guard points.count > 1 else { return (0, points[0]) }
        var bestDistance = Float.greatestFiniteMagnitude
        var bestAlong: Float = 0
        var bestPoint = points[0]
        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            var t: Float = 0
            if lengthSquared > 0 {
                t = simd_dot(position - a, ab) / lengthSquared
                t = min(max(t, 0), 1)
            }
            let candidate = a + ab * t
            let distance = simd_distance_squared(position, candidate)
            if distance < bestDistance {
                bestDistance = distance
                bestAlong = cumulative[index] + sqrt(lengthSquared) * t
                bestPoint = candidate
            }
        }
        return (bestAlong, bestPoint)
    }
}

// MARK: - Curves

enum Curves {
    /// Smooth Catmull-Rom curve through the given points.
    static func catmullRom(_ points: [SIMD3<Float>], samplesPerSegment: Int) -> [SIMD3<Float>] {
        guard points.count > 2, samplesPerSegment > 1 else { return points }
        var result: [SIMD3<Float>] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            for sample in 0..<samplesPerSegment {
                let t = Float(sample) / Float(samplesPerSegment)
                let t2 = t * t
                let t3 = t2 * t
                let a: SIMD3<Float> = p1 * 2
                let b: SIMD3<Float> = (p2 - p0) * t
                var c: SIMD3<Float> = p0 * 2
                c -= p1 * 5
                c += p2 * 4
                c -= p3
                c *= t2
                var d: SIMD3<Float> = p1 * 3
                d -= p0
                d -= p2 * 3
                d += p3
                d *= t3
                let sum: SIMD3<Float> = a + b + c + d
                result.append(sum * 0.5)
            }
        }
        if let last = points.last { result.append(last) }
        return result
    }

    /// Smooth closed loop through the points (the last returned point equals the first).
    static func closedCatmullRom(_ points: [SIMD3<Float>], samplesPerSegment: Int) -> [SIMD3<Float>] {
        guard points.count > 2 else { return points + (points.first.map { [$0] } ?? []) }
        let count = points.count
        var result: [SIMD3<Float>] = []
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            for sample in 0..<samplesPerSegment {
                let t = Float(sample) / Float(samplesPerSegment)
                let t2 = t * t
                let t3 = t2 * t
                let a: SIMD3<Float> = p1 * 2
                let b: SIMD3<Float> = (p2 - p0) * t
                var c: SIMD3<Float> = p0 * 2
                c -= p1 * 5
                c += p2 * 4
                c -= p3
                c *= t2
                var d: SIMD3<Float> = p1 * 3
                d -= p0
                d -= p2 * 3
                d += p3
                d *= t3
                let sum: SIMD3<Float> = a + b + c + d
                result.append(sum * 0.5)
            }
        }
        result.append(result[0])
        return result
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 != edge0 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Tube mesh

enum TubeMesh {
    /// Builds a closed tube around a path (used for the blood vessels on the physical model).
    static func generate(along path: [SIMD3<Float>], radius: Float, sides: Int = 8) throws -> MeshResource {
        guard path.count >= 2 else { throw TubeError.notEnoughPoints }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(path.count * sides)
        normals.reserveCapacity(path.count * sides)

        var normal = perpendicular(to: tangent(of: path, at: 0))
        for index in 0..<path.count {
            let tangentHere = tangent(of: path, at: index)
            // Parallel transport keeps the rings from twisting.
            var projected = normal - tangentHere * simd_dot(normal, tangentHere)
            if simd_length(projected) < 0.0001 { projected = perpendicular(to: tangentHere) }
            normal = simd_normalize(projected)
            let binormal = simd_cross(tangentHere, normal)
            for side in 0..<sides {
                let angle = Float(side) / Float(sides) * 2 * Float.pi
                let direction = normal * cos(angle) + binormal * sin(angle)
                positions.append(path[index] + direction * radius)
                normals.append(direction)
            }
        }

        let ringSize = UInt32(sides)
        for ring in 0..<UInt32(path.count - 1) {
            for side in 0..<ringSize {
                let next = (side + 1) % ringSize
                let a = ring * ringSize + side
                let b = ring * ringSize + next
                let c = (ring + 1) * ringSize + side
                let d = (ring + 1) * ringSize + next
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }

        var descriptor = MeshDescriptor(name: "vessel")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    enum TubeError: Error { case notEnoughPoints }

    private static func tangent(of path: [SIMD3<Float>], at index: Int) -> SIMD3<Float> {
        let previous = path[max(index - 1, 0)]
        let next = path[min(index + 1, path.count - 1)]
        let direction = next - previous
        return simd_length(direction) > 0 ? simd_normalize(direction) : SIMD3<Float>(0, 1, 0)
    }

    private static func perpendicular(to vector: SIMD3<Float>) -> SIMD3<Float> {
        let helper: SIMD3<Float> = abs(vector.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        return simd_normalize(simd_cross(vector, helper))
    }
}

// MARK: - Mesh sampling

enum MeshSampling {
    /// All vertex positions of the models below `root`, expressed in the space of `reference`.
    static func vertexPositions(of root: Entity, in reference: Entity) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        collect(root, reference: reference, into: &result)
        return result
    }

    private static func collect(_ entity: Entity, reference: Entity, into result: inout [SIMD3<Float>]) {
        if let model = entity.components[ModelComponent.self] {
            let toReference = entity.transformMatrix(relativeTo: reference)
            var modelsByID: [String: MeshResource.Model] = [:]
            for meshModel in model.mesh.contents.models {
                modelsByID[meshModel.id] = meshModel
            }
            for instance in model.mesh.contents.instances {
                guard let meshModel = modelsByID[instance.model] else { continue }
                let matrix = toReference * instance.transform
                for part in meshModel.parts {
                    for position in part.positions.elements {
                        let transformed = matrix * SIMD4<Float>(position.x, position.y, position.z, 1)
                        result.append(SIMD3<Float>(transformed.x, transformed.y, transformed.z))
                    }
                }
            }
        }
        for child in entity.children {
            collect(child, reference: reference, into: &result)
        }
    }

    /// Centre line of a tube-like model that lies along the x axis of `reference`.
    static func centerline(of root: Entity, in reference: Entity, bins: Int = 18) -> [SIMD3<Float>] {
        let positions = vertexPositions(of: root, in: reference)
        guard let minX = positions.map(\.x).min(),
              let maxX = positions.map(\.x).max(),
              maxX > minX else { return [] }
        var sums = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: bins)
        var counts = [Int](repeating: 0, count: bins)
        for position in positions {
            let bin = min(bins - 1, Int((position.x - minX) / (maxX - minX) * Float(bins)))
            sums[bin] += position
            counts[bin] += 1
        }
        var line: [SIMD3<Float>] = []
        for bin in 0..<bins where counts[bin] > 0 {
            line.append(sums[bin] / Float(counts[bin]))
        }
        guard line.count >= 2 else { return [] }
        // Stretch the ends to the real openings of the tube.
        line[0].x = minX
        line[line.count - 1].x = maxX
        return line
    }
}
