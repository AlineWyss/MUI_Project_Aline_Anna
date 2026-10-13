//
//  Disintegrate.swift
//  BloodCellJourney
//
//  Created by Anna Graf on 13.10.2026.
//
//  Dissolve effect for the old red blood cell: the cell breaks into its own small pieces (every triangle
//  of the mesh is a piece, with the cell's material) and flows away as one soft stream – like smoke or
//  sand drawn out by a current. The cell erodes from the side the stream leaves from; each loose piece
//  is drawn into the stream, which curves away to the person's right, upwards and backwards. Along the
//  way the pieces sway a little, turn slowly, shrink and vanish. Fine dust in the cell's colour drifts
//  out with the stream.
//
//  The mesh is copied once into a LowLevelMesh; DisintegrateSystem moves the pieces every frame.
//  Tune it in Config.swift (dissolveDuration) and with the stream values below
//  (direction, length, width, gathering, pick-up and how messy the stream is).
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
    /// The stream's centre line, in the mesh's own space; it starts at the cell's centre.
    let stream: SampledPath
    /// How quickly the pieces are drawn together into the stream (mesh units).
    let gathering: Float
    /// Per piece: centre, when it comes loose (s), speed along the stream (mesh units/s), its place
    /// inside the stream, sway (two sideways directions × size, speed, phase), tumble axis and speed.
    let centers: [SIMD3<Float>]
    let starts: [Float]
    let speeds: [Float]
    let lanes: [SIMD3<Float>]
    /// Per piece: how far it strays from the stream by the end (mesh units) – the messiness.
    let strays: [SIMD3<Float>]
    let swaysA: [SIMD3<Float>]
    let swaysB: [SIMD3<Float>]
    let swaySpeeds: [Float]
    let swayPhases: [Float]
    let axes: [SIMD3<Float>]
    let spins: [Float]
    /// Seconds a piece flows before it has shrunk away.
    let flight: Float
    var time: Float = 0
}

@MainActor
enum Disintegrate {
    // MARK: Stream settings

    /// Share of the total duration it takes the cell to erode completely; the rest is the last pieces' flow.
    static let sweepShare: Float = 0.4
    /// Length of the stream in metres, and where it goes, as seen by the person:
    /// right, up and away (backwards). The stream bends smoothly through these points.
    static let streamLength: Float = 0.85
    static let streamBend: [SIMD3<Float>] = [
        SIMD3<Float>(0.00, 0.00, 0.00),
        SIMD3<Float>(0.14, 0.03, 0.02),
        SIMD3<Float>(0.32, 0.12, -0.06),
        SIMD3<Float>(0.50, 0.30, -0.20),
    ]
    /// Thickness of the stream (metres) and how far the pieces travel before they have gathered into it.
    static let streamWidth: Float = 0.014
    static let gatheringDistance: Float = 0.09
    /// Seconds a loose piece needs to be picked up (it starts at rest, then flows at full speed).
    static let pickUp: Float = 0.5
    /// How messy the stream is: 0 = a tight, tidy stream … 1 = a loose cloud of pieces.
    /// Scales its thickness, the sway, the spread in speed, the ragged edge and how far pieces stray.
    static let streamMess: Float = 0.3

    /// Starts the dissolve on every visible model below `root` (the cell's container on the stage).
    /// Returns false if nothing could be split (then the caller should fall back to a simple fade).
    @discardableResult
    static func start(on root: Entity, duration: Float) -> Bool {
        let stage = root.parent ?? root
        var started = false
        root.forEachModelEntity { entity in
            guard entity.isEnabledInHierarchy,
                  var model = entity.components[ModelComponent.self],
                  let crumble = try? makeCrumble(for: entity, from: model.mesh, duration: duration,
                                                 centreOf: root, stage: stage)
            else { return }
            // A blend-shape animation (squeeze) would no longer match the new mesh.
            entity.components.remove(BlendShapeWeightsComponent.self)
            model.mesh = crumble.resource
            entity.components.set(model)
            entity.components.set(crumble.component)
            started = true
        }
        return started
    }

    /// Fine dust in `color` that drifts out with the stream while the cell erodes.
    static func addDust(for item: StageItem, in parent: Entity, color: UIColor, duration: Float) {
        let bounds = item.container.visualBounds(relativeTo: parent)
        let sweep = duration * sweepShare
        // The stream's first direction, in the parent's (stage's) space.
        let first = simd_normalize(streamBend[1] - streamBend[0])

        let emitter = Entity()
        emitter.name = "DissolveDust"
        emitter.position = bounds.center

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterShapeSize = SIMD3<Float>(repeating: max(bounds.extents.x, bounds.extents.y) / 2)
        particles.birthLocation = .volume
        particles.birthDirection = .world
        particles.emissionDirection = first
        particles.speed = 0.06
        particles.speedVariation = 0.02
        particles.mainEmitter.birthRate = 450
        particles.mainEmitter.lifeSpan = 2.6
        particles.mainEmitter.size = 0.002
        particles.mainEmitter.acceleration = SIMD3<Float>(0.01, 0.025, -0.012)
        particles.mainEmitter.color = .evolving(start: .single(color),
                                                end: .single(color.withAlphaComponent(0)))
        particles.isEmitting = true
        emitter.components.set(particles)
        parent.addChild(emitter)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(sweep) + 0.3))
            if var component = emitter.components[ParticleEmitterComponent.self] {
                component.isEmitting = false
                emitter.components.set(component)
            }
            try? await Task.sleep(for: .seconds(2.8))
            emitter.removeFromParent()
        }
    }

    // MARK: - Splitting the mesh into pieces

    private enum CrumbleError: Error { case unsupportedMesh }

    private static func makeCrumble(for entity: Entity, from source: MeshResource, duration: Float,
                                    centreOf root: Entity, stage: Entity)
        throws -> (resource: MeshResource, component: DisintegrateComponent) {
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

        // 2. The stream: from the cell's centre, bending right, up and away (stage directions),
        //    expressed in the mesh's own space.
        let unitsPerMetre = max(simd_length(entity.convert(direction: SIMD3<Float>(0, 1, 0), from: nil)), 1e-6)
        let centreOnStage = root.position(relativeTo: stage)
        let scale = streamLength / max(simd_length(streamBend.last! - streamBend.first!), 1e-6)
        let bendOnStage = streamBend.map { centreOnStage + $0 * scale }
        let curve = Curves.catmullRom(bendOnStage, samplesPerSegment: 16)
            .map { entity.convert(position: $0, from: stage) }
        let stream = SampledPath(curve)
        let streamStart = curve.first ?? .zero
        let exitDirection = simd_normalize(entity.convert(direction: streamBend[1] - streamBend[0], from: stage))

        let sweep = duration * sweepShare
        let flight = duration * (1 - sweepShare)

        // 3. Per piece: when it comes loose (the side the stream leaves from goes first) and its place in the stream.
        var centers: [SIMD3<Float>] = []
        centers.reserveCapacity(pieceCount)
        for piece in 0..<pieceCount {
            let a = vertices[piece * 3].position, b = vertices[piece * 3 + 1].position, c = vertices[piece * 3 + 2].position
            centers.append((a + b + c) / 3)
        }
        let towardsExit = centers.map { simd_dot($0 - streamStart, exitDirection) }
        let nearest = towardsExit.max() ?? 1, farthest = towardsExit.min() ?? 0
        let span = max(nearest - farthest, 1e-6)

        // Two directions across the stream (for its width and the sway).
        var across1 = simd_cross(exitDirection, SIMD3<Float>(0, 1, 0))
        if simd_length(across1) < 1e-4 { across1 = simd_cross(exitDirection, SIMD3<Float>(1, 0, 0)) }
        across1 = simd_normalize(across1)
        let across2 = simd_normalize(simd_cross(exitDirection, across1))

        var starts: [Float] = [], speeds: [Float] = [], lanes: [SIMD3<Float>] = [], strays: [SIMD3<Float>] = []
        let mess = min(max(streamMess, 0), 1)
        var swaysA: [SIMD3<Float>] = [], swaysB: [SIMD3<Float>] = [], swaySpeeds: [Float] = [], swayPhases: [Float] = []
        var axes: [SIMD3<Float>] = [], spins: [Float] = []
        for piece in 0..<pieceCount {
            let center = centers[piece]
            // 0 = the side the stream leaves from … 1 = the far side; a soft ragged edge.
            let order = (nearest - towardsExit[piece]) / span
            let offset = (center - streamStart) / span
            let ragged = 0.06 * sin(offset.y * 9 + offset.z * 6) * cos(offset.x * 4 + offset.y * 3)
            starts.append(min(max(order * 0.9 + ragged * (0.5 + mess) + Float.random(in: 0...(0.03 + 0.2 * mess)), 0), 1) * sweep)

            // Flows the whole stream within its flight (minus the pick-up), a little faster or slower each.
            let full = stream.length / max(flight - pickUp, 0.1)
            speeds.append(full * Float.random(in: (0.9 - 0.4 * mess)...1.0))

            // Its place inside the stream (a soft round cross-section).
            let angle = Float.random(in: 0...(2 * .pi))
            let radius = sqrt(Float.random(in: 0...1)) * streamWidth * (0.5 + 3 * mess) * unitsPerMetre
            lanes.append((across1 * cos(angle) + across2 * sin(angle)) * radius)
            // Strays a little off the stream as it flows on (more when messier).
            let strayAngle = Float.random(in: 0...(2 * .pi))
            let strayDistance = Float.random(in: 0...1) * 0.2 * mess * unitsPerMetre
            strays.append((across1 * cos(strayAngle) + across2 * sin(strayAngle)) * strayDistance)

            // A gentle sway across the stream.
            let amplitude = Float.random(in: 0.003...0.009) * (0.4 + 2 * mess) * unitsPerMetre
            swaysA.append(across1 * amplitude)
            swaysB.append(across2 * amplitude * 0.7)
            swaySpeeds.append(Float.random(in: 2.0...3.5))
            swayPhases.append(Float.random(in: 0...(2 * .pi)))

            var axis = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
            axis = simd_length(axis) > 1e-4 ? simd_normalize(axis) : exitDirection
            axes.append(axis)
            spins.append(Float.random(in: 0.8...2.5) * (Bool.random() ? 1 : -1))
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

        // Bounds that include the cell and the whole stream.
        var low = vertices[0].position, high = vertices[0].position
        for point in vertices.map(\.position) + curve {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        let margin = SIMD3<Float>(repeating: (streamWidth * 3 * (0.5 + 3 * mess) + 0.2 * mess + 0.05) * unitsPerMetre)
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: vertices.count,
                              topology: .triangle,
                              materialIndex: materialIndex ?? 0,
                              bounds: BoundingBox(min: low - margin, max: high + margin))
        ])

        let resource = try MeshResource(from: mesh)
        let component = DisintegrateComponent(mesh: mesh, base: vertices, stream: stream,
                                              gathering: gatheringDistance * unitsPerMetre,
                                              centers: centers, starts: starts, speeds: speeds, lanes: lanes, strays: strays,
                                              swaysA: swaysA, swaysB: swaysB,
                                              swaySpeeds: swaySpeeds, swayPhases: swayPhases,
                                              axes: axes, spins: spins, flight: flight)
        return (resource, component)
    }
}

/// Moves the pieces every frame: still pieces stay in place; loose ones are drawn into the stream,
/// flow along it, sway a little, turn slowly and shrink away.
struct DisintegrateSystem: System {
    static let query = EntityQuery(where: .has(DisintegrateComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        let pickUp = Disintegrate.pickUp
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var crumble = entity.components[DisintegrateComponent.self] else { continue }
            crumble.time += dt
            entity.components.set(crumble)
            let t = crumble.time
            let streamStart = crumble.stream.point(at: 0)
            let length = max(crumble.stream.length, 1e-6)

            crumble.mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let buffer = raw.bindMemory(to: DisintegrateVertex.self)
                for piece in crumble.centers.indices {
                    let first = piece * 3
                    let age = t - crumble.starts[piece]
                    guard age > 0 else {
                        // Not loose yet: in place (written every frame, the buffer may change).
                        buffer[first] = crumble.base[first]
                        buffer[first + 1] = crumble.base[first + 1]
                        buffer[first + 2] = crumble.base[first + 2]
                        continue
                    }
                    // How far along the stream: starts at rest, then flows at its speed.
                    let travelled = crumble.speeds[piece] * (age - pickUp * (1 - exp(-age / pickUp)))
                    let onStream = crumble.stream.point(at: min(travelled / length, 1))
                    // Drawn together: its offset from the cell's centre fades into its place in the stream.
                    let gathered = exp(-travelled / crumble.gathering)
                    let offset = crumble.centers[piece] - streamStart
                    let phase = crumble.swaySpeeds[piece] * age + crumble.swayPhases[piece]
                    let sway = crumble.swaysA[piece] * sin(phase) + crumble.swaysB[piece] * cos(phase)
                    // The stream widens softly as it flows on, like smoke spreading out.
                    let widening = 1 + 1.5 * min(travelled / length, 1)
                    let along = min(travelled / length, 1)
                    let moved = onStream + offset * gathered
                        + (crumble.lanes[piece] * widening + sway) * (1 - gathered)
                        + crumble.strays[piece] * along * along

                    // Stays whole for the first half of its flow, then shrinks away smoothly.
                    let life = min(age / crumble.flight, 1)
                    let shrink = min(max((life - 0.5) / 0.5, 0), 1)
                    let size = 1 - shrink * shrink * (3 - 2 * shrink)
                    let turn = simd_quatf(angle: crumble.spins[piece] * age, axis: crumble.axes[piece])
                    let center = crumble.centers[piece]
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
