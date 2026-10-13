//
//  Disintegrate.swift
//  BloodCellJourney
//
//  Created by Anna Graf on 13.10.2026.
//
//
//  Dissolve effect for the old red blood cell (like Blender's particle "dissolve" tutorials):
//  a ragged front sweeps from the bottom of the cell to the top. Behind it the surface breaks into
//  its own small pieces (every triangle of the mesh is a piece, with the cell's material), which
//  come loose, tumble, drift upwards like ash, shrink and vanish. Fine dust in the cell's colour
//  rises from the front.
//
//  The mesh is copied once into a LowLevelMesh; DisintegrateSystem moves the pieces every frame.
//  Tune it in Config.swift (dissolveDuration, dissolveRise).
//

import Foundation
import Metal
import RealityKit
import UIKit

/// One vertex of the crumbling mesh.
struct DisintegrateVertex {
    var position: SIMD3<Float> = .zero
    var normal: SIMD3<Float> = .zero
    var uv: SIMD2<Float> = .zero
}

struct DisintegrateComponent: Component {
    let mesh: LowLevelMesh
    /// The untouched vertices, three per piece (written back every frame with the new positions).
    let base: [DisintegrateVertex]
    /// Per piece: centre, when it comes loose (seconds), sideways drift (mesh units per second),
    /// tumble axis and tumble speed (radians per second).
    let centers: [SIMD3<Float>]
    let starts: [Float]
    let drifts: [SIMD3<Float>]
    let axes: [SIMD3<Float>]
    let spins: [Float]
    /// World "up" in the mesh's own space, and the upward acceleration (mesh units per second²).
    let up: SIMD3<Float>
    let rise: Float
    /// Seconds a piece flies before it has shrunk away.
    let flight: Float
    var time: Float = 0
}

@MainActor
enum Disintegrate {
    /// Share of the total duration the front needs from bottom to top; the rest is the last pieces' flight.
    static let sweepShare: Float = 0.6

    /// Starts crumbling every visible model below `root`. Returns false if nothing could be split
    /// (then the caller should fall back to a simple fade).
    @discardableResult
    static func start(on root: Entity, duration: Float) -> Bool {
        var started = false
        root.forEachModelEntity { entity in
            guard entity.isEnabledInHierarchy,
                  var model = entity.components[ModelComponent.self],
                  let crumble = try? makeCrumble(for: entity, from: model.mesh, duration: duration) else { return }
            // A blend-shape animation (squeeze) would no longer match the new mesh.
            entity.components.remove(BlendShapeWeightsComponent.self)
            model.mesh = crumble.resource
            entity.components.set(model)
            entity.components.set(crumble.component)
            started = true
        }
        return started
    }

    /// Fine dust in `color` that rises from the dissolving front, from the bottom of `item` to its top.
    static func addDust(for item: StageItem, in parent: Entity, color: UIColor, duration: Float) {
        let bounds = item.container.visualBounds(relativeTo: parent)
        let sweep = duration * sweepShare

        let emitter = Entity()
        emitter.name = "DissolveDust"
        emitter.position = SIMD3<Float>(bounds.center.x, bounds.min.y, bounds.center.z)

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .box
        particles.emitterShapeSize = SIMD3<Float>(bounds.extents.x, 0.004, max(bounds.extents.z, 0.01))
        particles.emissionDirection = SIMD3<Float>(0, 1, 0)
        particles.speed = 0.02
        particles.speedVariation = 0.01
        particles.mainEmitter.birthRate = 900
        particles.mainEmitter.lifeSpan = 1.2
        particles.mainEmitter.size = 0.0025
        particles.mainEmitter.acceleration = SIMD3<Float>(0, 0.04, 0)
        particles.mainEmitter.color = .evolving(start: .single(color),
                                                end: .single(color.withAlphaComponent(0)))
        particles.isEmitting = true
        emitter.components.set(particles)
        parent.addChild(emitter)

        // The dust follows the front upwards.
        var top = emitter.transform
        top.translation.y = bounds.max.y
        emitter.move(to: top, relativeTo: parent, duration: TimeInterval(sweep), timingFunction: .linear)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(sweep)))
            if var component = emitter.components[ParticleEmitterComponent.self] {
                component.isEmitting = false
                emitter.components.set(component)
            }
            try? await Task.sleep(for: .seconds(1.5))
            emitter.removeFromParent()
        }
    }

    // MARK: - Splitting the mesh into pieces

    private enum CrumbleError: Error { case unsupportedMesh }

    private static func makeCrumble(for entity: Entity, from source: MeshResource,
                                    duration: Float) throws -> (resource: MeshResource, component: DisintegrateComponent) {
        // 1. Every triangle becomes its own piece (three vertices that belong to it alone).
        var vertices: [DisintegrateVertex] = []
        var materialIndex: Int?
        for instance in source.contents.instances {
            guard let model = source.contents.models[instance.model] else { continue }
            let transform = instance.transform
            for part in model.parts {
                guard let triangles = part.triangleIndices?.elements else { continue }
                // One material for the whole mesh (true for the cell); anything else keeps its mesh.
                if let materialIndex, materialIndex != part.materialIndex { throw CrumbleError.unsupportedMesh }
                materialIndex = part.materialIndex

                let positions = part.positions.elements
                let normals = part.normals?.elements
                let uvs = part.textureCoordinates?.elements
                for index in triangles {
                    let i = Int(index)
                    guard i < positions.count else { throw CrumbleError.unsupportedMesh }
                    let p = transform * SIMD4<Float>(positions[i], 1)
                    var normal = SIMD3<Float>(0, 0, 1)
                    if let normals, i < normals.count {
                        let n = transform * SIMD4<Float>(normals[i], 0)
                        let n3 = SIMD3<Float>(n.x, n.y, n.z)
                        if simd_length(n3) > 1e-6 { normal = simd_normalize(n3) }
                    }
                    let uv = (uvs != nil && i < uvs!.count) ? uvs![i] : .zero
                    vertices.append(DisintegrateVertex(position: SIMD3<Float>(p.x, p.y, p.z), normal: normal, uv: uv))
                }
            }
        }
        let pieceCount = vertices.count / 3
        guard pieceCount > 0 else { throw CrumbleError.unsupportedMesh }

        // 2. World directions and distances, expressed in the mesh's own space.
        let upLocal = entity.convert(direction: SIMD3<Float>(0, 1, 0), from: nil)
        let unitsPerMetre = max(simd_length(upLocal), 1e-6)
        let up = upLocal / unitsPerMetre

        let sweep = duration * sweepShare
        let flight = duration * (1 - sweepShare)
        // Rise so a piece is Config.dissolveRise metres higher when it vanishes: d = ½·a·t².
        let rise = 2 * Config.dissolveRise / (flight * flight) * unitsPerMetre

        // 3. Per piece: where the front reaches it, and how it flies off.
        var centers: [SIMD3<Float>] = []
        centers.reserveCapacity(pieceCount)
        for piece in 0..<pieceCount {
            let a = vertices[piece * 3].position, b = vertices[piece * 3 + 1].position, c = vertices[piece * 3 + 2].position
            centers.append((a + b + c) / 3)
        }
        let heights = centers.map { simd_dot($0, up) }
        let lowest = heights.min() ?? 0, highest = heights.max() ?? 1
        let span = max(highest - lowest, 1e-6)
        let middle = centers.reduce(SIMD3<Float>.zero, +) / Float(pieceCount)

        var starts: [Float] = [], drifts: [SIMD3<Float>] = [], axes: [SIMD3<Float>] = [], spins: [Float] = []
        for piece in 0..<pieceCount {
            let center = centers[piece]
            let height = (heights[piece] - lowest) / span                      // 0 = bottom … 1 = top
            // A ragged front: a gentle wave across the cell plus a little randomness per piece.
            let across = (center - middle) / span
            let ragged = 0.06 * sin(across.x * 11 + across.z * 7) * cos(across.y * 5 + across.x * 3)
            let start = min(max(height * 0.92 + ragged + Float.random(in: 0...0.06), 0), 1) * sweep
            starts.append(start)

            // Drift: a little sideways and out of the surface; the climb comes from `rise`.
            var sideways = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
            sideways -= up * simd_dot(sideways, up)
            if simd_length(sideways) > 1e-4 { sideways = simd_normalize(sideways) }
            let outward = vertices[piece * 3].normal
            let drift = (sideways * Float.random(in: 0.004...0.018) + outward * 0.008) * unitsPerMetre
            drifts.append(drift)

            var axis = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
            axis = simd_length(axis) > 1e-4 ? simd_normalize(axis) : up
            axes.append(axis)
            spins.append(Float.random(in: 1.5...6) * (Bool.random() ? 1 : -1))
        }

        // 4. The LowLevelMesh (same layout as DisintegrateVertex).
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<DisintegrateVertex>.offset(of: \.position)!),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<DisintegrateVertex>.offset(of: \.normal)!),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<DisintegrateVertex>.offset(of: \.uv)!)
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<DisintegrateVertex>.stride)]
        descriptor.vertexCapacity = vertices.count
        descriptor.indexCapacity = vertices.count
        descriptor.indexType = .uint32

        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let buffer = raw.bindMemory(to: DisintegrateVertex.self)
            for i in vertices.indices { buffer[i] = vertices[i] }
        }
        mesh.withUnsafeMutableIndices { raw in
            let buffer = raw.bindMemory(to: UInt32.self)
            for i in vertices.indices { buffer[i] = UInt32(i) }
        }

        // Bounds that include where the pieces fly to.
        var low = vertices[0].position, high = vertices[0].position
        for vertex in vertices {
            low = simd_min(low, vertex.position)
            high = simd_max(high, vertex.position)
        }
        let climb = (Config.dissolveRise + 0.03) * unitsPerMetre
        let margin = SIMD3<Float>(repeating: climb) + (high - low) * 0.25
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: vertices.count,
                              topology: .triangle,
                              materialIndex: materialIndex ?? 0,
                              bounds: BoundingBox(min: low - margin, max: high + margin))
        ])

        let resource = try MeshResource(from: mesh)
        let component = DisintegrateComponent(mesh: mesh, base: vertices, centers: centers, starts: starts,
                                              drifts: drifts, axes: axes, spins: spins, up: up, rise: rise,
                                              flight: flight)
        return (resource, component)
    }
}

/// Moves the pieces every frame: still pieces stay in place, loose ones tumble, rise and shrink away.
struct DisintegrateSystem: System {
    static let query = EntityQuery(where: .has(DisintegrateComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var crumble = entity.components[DisintegrateComponent.self] else { continue }
            crumble.time += dt
            entity.components.set(crumble)
            let t = crumble.time

            crumble.mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let buffer = raw.bindMemory(to: DisintegrateVertex.self)
                for piece in crumble.centers.indices {
                    let first = piece * 3
                    let age = t - crumble.starts[piece]
                    guard age > 0 else {
                        // Not reached by the front yet: in place (written every frame, the buffer may change).
                        buffer[first] = crumble.base[first]
                        buffer[first + 1] = crumble.base[first + 1]
                        buffer[first + 2] = crumble.base[first + 2]
                        continue
                    }
                    let life = min(age / crumble.flight, 1)
                    let size = 1 - life * life                       // stays whole at first, then shrinks away
                    let turn = simd_quatf(angle: crumble.spins[piece] * age, axis: crumble.axes[piece])
                    let center = crumble.centers[piece]
                    let moved = center + crumble.drifts[piece] * age + crumble.up * (0.5 * crumble.rise * age * age)
                    for k in 0..<3 {
                        var vertex = crumble.base[first + k]
                        vertex.position = moved + turn.act((vertex.position - center) * size)
                        vertex.normal = turn.act(vertex.normal)
                        buffer[first + k] = vertex
                    }
                }
            }
        }
    }
}
