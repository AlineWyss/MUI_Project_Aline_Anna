//
//  CellMesh.swift
//  BloodCellJourney
//
//  A small, low-poly red blood cell (biconcave disc) for the blood stream on the anatomy model.
//  Shape after Evans & Fung: half-thickness h(ρ) = ½·R·√(1−ρ²)·(0.207 + 2.003ρ² − 1.123ρ⁴).
//  The disc lies in the x-y plane, thickness along z. About 500 triangles.
//

import Foundation
import RealityKit
import simd

enum CellMesh {
    static func redBloodCell(diameter: Float, rings: Int = 8, segments: Int = 16) throws -> MeshResource {
        let radius = diameter / 2

        func halfThickness(_ rho: Float) -> Float {
            let r2: Float = rho * rho
            let profile: Float = 0.207 + 2.003 * r2 - 1.123 * r2 * r2
            let envelope: Float = sqrt(max(1 - r2, 0))
            return 0.5 * radius * envelope * profile
        }
        func slope(_ rho: Float) -> Float {
            // d h / d r (numerical), r = rho * radius
            let step: Float = 0.01
            let a = max(rho - step, 0)
            let b = min(rho + step, 1)
            return (halfThickness(b) - halfThickness(a)) / ((b - a) * radius)
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Ring radii from the centre to just inside the rim; the last ring sits on the rim.
        var rhos: [Float] = []
        for ring in 0...rings {
            rhos.append(Float(ring) / Float(rings) * 0.985)
        }
        rhos.append(1)

        for surface in [Float(1), Float(-1)] {          // top, bottom
            let base = UInt32(positions.count)
            for rho in rhos {
                let h = halfThickness(rho) * surface
                let dh = slope(min(rho, 0.985))
                for segment in 0..<segments {
                    let angle = Float(segment) / Float(segments) * 2 * Float.pi
                    let c = cos(angle)
                    let s = sin(angle)
                    positions.append(SIMD3<Float>(c * rho * radius, s * rho * radius, h))
                    var normal: SIMD3<Float>
                    if rho >= 1 {
                        normal = SIMD3<Float>(c, s, 0)
                    } else {
                        normal = SIMD3<Float>(-dh * c, -dh * s, surface)
                    }
                    normals.append(simd_normalize(normal))
                }
            }
            let count = UInt32(segments)
            for ring in 0..<UInt32(rhos.count - 1) {
                for segment in 0..<count {
                    let next = (segment + 1) % count
                    let a = base + ring * count + segment
                    let b = base + ring * count + next
                    let c = base + (ring + 1) * count + segment
                    let d = base + (ring + 1) * count + next
                    if surface > 0 {
                        indices.append(contentsOf: [a, c, d, a, d, b])   // counter-clockwise seen from +z
                    } else {
                        indices.append(contentsOf: [a, d, c, a, b, d])   // counter-clockwise seen from −z
                    }
                }
            }
        }

        var descriptor = MeshDescriptor(name: "miniRedBloodCell")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
