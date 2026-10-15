//
//  Disintegrate.swift
//  BloodCellJourney
///
//  Dissolve effect for the old red blood cell: the cell breaks into its own small pieces (every triangle
//  of the mesh is a piece, with the cell's material) and leaves as one calm, natural flow – like a thread
//  of smoke, or cells drifting in a slow blood stream. It dissolves from its upper right edge: the loose
//  pieces float up and off to the right – above the cell, never through it – then drift on as an organic,
//  gently winding stream into the anatomy model, where the flow narrows into ONE point – the spleen, where
//  old red blood cells are recycled. There the pieces shrink into the point and vanish.
//
//  What makes it look natural:
//  • every piece eases in and out (slow start, gliding, slow arrival) instead of moving at a fixed speed;
//  • the flow first widens a little, then narrows into the point;
//  • neighbouring pieces move alike (coherent, slowly changing turbulence), and the flow twists gently;
//  • the pieces tumble slowly and get a little smaller on their way.
//
//  The mesh is copied once into a LowLevelMesh; DisintegrateSystem moves the pieces every frame.
//  Tune it in Config.swift (dissolveDuration, dissolveStreamMess) and with the values below
//  (drift to the right, winding, width, turbulence, twist, narrowing).
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
    /// The flow's centre line, in the mesh's own space; it starts at the cell's centre and ends at the target.
    let stream: SampledPath
    /// "Up" in the mesh's own space (to build the flow's cross-section).
    let up: SIMD3<Float>
    /// How quickly the pieces are drawn together into the flow (mesh units of travelled distance).
    let gathering: Float
    /// Radius of the flow at its widest (mesh units).
    let width: Float
    /// How far the gentle turbulence moves the pieces sideways (mesh units).
    let turbulence: Float
    /// How far the flow twists around its centre line over the whole way (radians).
    let twist: Float
    /// Per piece: centre, when it comes loose (s), how long its way takes (s), its place in the flow's
    /// cross-section (angle, radius 0…1), tumble axis and speed (radians/s).
    let centers: [SIMD3<Float>]
    let starts: [Float]
    let durations: [Float]
    let laneAngles: [Float]
    let laneRadii: [Float]
    let axes: [SIMD3<Float>]
    let spins: [Float]
    var time: Float = 0
}

@MainActor
enum Disintegrate {
    // MARK: Flow settings

    /// Share of the total duration it takes the cell to erode completely; the rest is the last pieces' way.
    static let sweepShare: Float = 0.45
    /// The flow starts at the cell's edge in this direction and floats there first, in stage directions as
    /// seen by the person (x = right, y = up, z = towards the person), in metres from the cell's edge –
    /// up and to the right, so it never passes through the dissolving cell …
    static let driftRight = SIMD3<Float>(0.12, 0.10, 0.02)
    /// Extra room between the cell's edge and the start of the flow (metres).
    static let clearance: Float = 0.02
    /// … then they float on to the model as an organic stream that winds gently: how far it swings to the
    /// sides (metres; 0 = straight) and how many soft bends it makes on the way.
    static let winding: Float = 0.05
    static let bends: Float = 2
    /// Radius of the flow at its widest (metres) – it starts narrower and narrows into the point at the end.
    static let streamWidth: Float = 0.016
    /// How far the slow, floaty turbulence moves the pieces sideways (metres).
    static let turbulenceAmount: Float = 0.010
    /// How many times the flow twists around its centre line over the whole way (0 = not at all).
    static let twistTurns: Float = 0.6
    /// How far a piece travels before it has joined the flow (metres).
    static let gatheringDistance: Float = 0.08
    /// How messy the flow is: 0 = a tight, tidy flow … 1 = loose (Config.swift).
    static var streamMess: Float { Config.dissolveStreamMess }
    /// The last share of the way, on which the flow narrows into one point at the target and the pieces
    /// shrink into it (0.3 = the last 30 %).
    static let convergeShare: Float = 0.3

    /// Starts the dissolve on every visible model below `root` (the cell's container on the stage).
    /// `target` (world position, e.g. the spleen) is the point the flow goes into.
    /// Returns false if nothing could be split (then the caller should fall back to a simple fade).
    @discardableResult
    static func start(on root: Entity, duration: Float, into target: SIMD3<Float>? = nil) -> Bool {
        let stage = root.parent ?? root
        var started = false
        root.forEachModelEntity { entity in
            guard entity.isEnabledInHierarchy,
                  var model = entity.components[ModelComponent.self],
                  let crumble = try? makeCrumble(for: entity, from: model.mesh, duration: duration,
                                                 centreOf: root, stage: stage, target: target)
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

    /// A little fine dust in `color` that rises softly where the cell erodes.
    /// (`target` is accepted for the caller's convenience; the dust only follows the rise.)
    static func addDust(for item: StageItem, in parent: Entity, color: UIColor, duration: Float,
                        towards target: SIMD3<Float>? = nil) {
        let bounds = item.container.visualBounds(relativeTo: parent)
        let sweep = duration * sweepShare
        // Up and to the right, like the pieces.
        let rise = simd_normalize(driftRight)

        let emitter = Entity()
        emitter.name = "DissolveDust"
        emitter.position = bounds.center

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterShapeSize = SIMD3<Float>(repeating: max(bounds.extents.x, bounds.extents.y) / 2)
        particles.birthLocation = .volume
        particles.birthDirection = .world
        particles.emissionDirection = rise
        particles.speed = 0.015
        particles.speedVariation = 0.01
        particles.mainEmitter.birthRate = 90
        particles.mainEmitter.lifeSpan = 3.0
        particles.mainEmitter.size = 0.0016
        particles.mainEmitter.acceleration = SIMD3<Float>(0.003, 0.010, 0)
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
            try? await Task.sleep(for: .seconds(3.2))
            emitter.removeFromParent()
        }
    }

    // MARK: - Splitting the mesh into pieces

    private enum CrumbleError: Error { case unsupportedMesh }

    private static func makeCrumble(for entity: Entity, from source: MeshResource, duration: Float,
                                    centreOf root: Entity, stage: Entity, target: SIMD3<Float>?)
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

        // 2. The flow (stage directions, then expressed in the mesh's own space): the pieces drift off to the
        //    right, then float on to the target as an organic stream that winds gently.
        let unitsPerMetre = max(simd_length(entity.convert(direction: SIMD3<Float>(0, 1, 0), from: nil)), 1e-6)
        let centreOnStage = root.position(relativeTo: stage)
        let up = SIMD3<Float>(0, 1, 0)
        // The flow begins just outside the cell, on its upper right edge, so no piece floats through the cell.
        let cellBounds = root.visualBounds(relativeTo: stage)
        let cellRadius: Float = max(cellBounds.extents.x, max(cellBounds.extents.y, cellBounds.extents.z)) / 2
        let outward: SIMD3<Float> = simd_normalize(driftRight)
        let edge: SIMD3<Float> = centreOnStage + outward * (cellRadius + clearance)
        let right: SIMD3<Float> = edge + driftRight
        // Without a target they simply float on up and to the right.
        let end: SIMD3<Float> = target.map { stage.convert(position: $0, from: nil) }
            ?? right + SIMD3<Float>(0.10, 0.35, -0.05)
        let way: SIMD3<Float> = end - right
        let wayDirection: SIMD3<Float> = simd_length(way) > 1e-4 ? simd_normalize(way) : up
        var sideways: SIMD3<Float> = simd_cross(wayDirection, up)
        if simd_length(sideways) < 1e-4 { sideways = SIMD3<Float>(0, 0, 1) }
        sideways = simd_normalize(sideways)
        let upways: SIMD3<Float> = simd_normalize(simd_cross(sideways, wayDirection))
        var bendOnStage: [SIMD3<Float>] = [edge, right]
        let steps = 6
        for step in 1..<steps {
            let f = Float(step) / Float(steps)
            // Soft bends that fade out towards both ends, so the stream leaves the right and enters the model calmly.
            let envelope: Float = sin(f * .pi)
            let swing: Float = sin(f * .pi * bends) * winding * envelope
            let lilt: Float = cos(f * .pi * bends) * winding * 0.5 * envelope
            let base: SIMD3<Float> = right + way * f
            bendOnStage.append(base + sideways * swing + upways * lilt)
        }
        bendOnStage.append(end)
        let curve = Curves.catmullRom(bendOnStage, samplesPerSegment: 16)
            .map { entity.convert(position: $0, from: stage) }
        let stream = SampledPath(curve)
        let streamStart = curve.first ?? .zero
        let exitDirection = simd_normalize(entity.convert(direction: bendOnStage[1] - bendOnStage[0], from: stage))
        let upInMesh = simd_normalize(entity.convert(direction: SIMD3<Float>(0, 1, 0), from: stage))

        let mess = min(max(streamMess, 0), 1)
        let sweep = duration * sweepShare
        let flight = duration * (1 - sweepShare)

        // 3. Per piece: when it comes loose (the side the flow leaves from goes first), how long its way
        //    takes, its place in the flow, and how it tumbles.
        var centers: [SIMD3<Float>] = []
        centers.reserveCapacity(pieceCount)
        for piece in 0..<pieceCount {
            let a = vertices[piece * 3].position, b = vertices[piece * 3 + 1].position, c = vertices[piece * 3 + 2].position
            centers.append((a + b + c) / 3)
        }
        let towardsExit = centers.map { simd_dot($0 - streamStart, exitDirection) }
        let nearest = towardsExit.max() ?? 1, farthest = towardsExit.min() ?? 0
        let span = max(nearest - farthest, 1e-6)

        var starts: [Float] = [], durations: [Float] = []
        var laneAngles: [Float] = [], laneRadii: [Float] = []
        var axes: [SIMD3<Float>] = [], spins: [Float] = []
        // Every piece reaches the target within its flight; some a little sooner.
        let quickest: Float = 0.75 - 0.2 * mess
        for piece in 0..<pieceCount {
            let center = centers[piece]
            // 0 = the side the flow leaves from … 1 = the far side; a soft ragged edge.
            let order: Float = (nearest - towardsExit[piece]) / span
            let offset: SIMD3<Float> = (center - streamStart) / span
            let ragged: Float = 0.04 * sin(offset.y * 9 + offset.z * 6) * cos(offset.x * 4 + offset.y * 3)
            let jitter: Float = Float.random(in: 0...(0.02 + 0.1 * mess))
            let loose: Float = min(max(order * 0.92 + ragged * (0.5 + mess) + jitter, 0), 1)
            starts.append(loose * sweep)
            durations.append(flight * Float.random(in: quickest...1.0))

            // Its place in the flow's round cross-section (more pieces in the middle).
            laneAngles.append(Float.random(in: 0...(2 * .pi)))
            laneRadii.append(sqrt(Float.random(in: 0...1)) * Float.random(in: (1 - 0.3 * mess)...1))

            var axis = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
            axis = simd_length(axis) > 1e-4 ? simd_normalize(axis) : exitDirection
            axes.append(axis)
            spins.append(Float.random(in: 0.08...0.3) * (Bool.random() ? 1 : -1))
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

        let width: Float = streamWidth * (0.6 + 2 * mess) * unitsPerMetre
        let turbulence: Float = turbulenceAmount * (0.5 + 2 * mess) * unitsPerMetre

        // Bounds that include the cell and the whole flow.
        var low = vertices[0].position, high = vertices[0].position
        for point in vertices.map(\.position) + curve {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        let margin = SIMD3<Float>(repeating: width + turbulence + 0.05 * unitsPerMetre)
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: vertices.count,
                              topology: .triangle,
                              materialIndex: materialIndex ?? 0,
                              bounds: BoundingBox(min: low - margin, max: high + margin))
        ])

        let resource = try MeshResource(from: mesh)
        let component = DisintegrateComponent(mesh: mesh, base: vertices, stream: stream, up: upInMesh,
                                              gathering: gatheringDistance * unitsPerMetre,
                                              width: width, turbulence: turbulence,
                                              twist: twistTurns * 2 * .pi,
                                              centers: centers, starts: starts, durations: durations,
                                              laneAngles: laneAngles, laneRadii: laneRadii,
                                              axes: axes, spins: spins)
        return (resource, component)
    }
}

/// Moves the pieces every frame: still pieces stay in place; loose ones glide into the flow, follow it with
/// a soft ease-in and ease-out, sway and twist gently together, and on the last part of the way the flow
/// narrows into one point at the target, where the pieces shrink and vanish.
struct DisintegrateSystem: System {
    static let query = EntityQuery(where: .has(DisintegrateComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        let converge: Float = max(Disintegrate.convergeShare, 0.01)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var crumble = entity.components[DisintegrateComponent.self] else { continue }
            crumble.time += dt
            entity.components.set(crumble)
            let t: Float = crumble.time
            let streamStart: SIMD3<Float> = crumble.stream.point(at: 0)
            let length: Float = max(crumble.stream.length, 1e-6)

            crumble.mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let buffer = raw.bindMemory(to: DisintegrateVertex.self)
                for piece in crumble.centers.indices {
                    let first = piece * 3
                    let age: Float = t - crumble.starts[piece]
                    guard age > 0 else {
                        // Not loose yet: in place (written every frame, the buffer may change).
                        buffer[first] = crumble.base[first]
                        buffer[first + 1] = crumble.base[first + 1]
                        buffer[first + 2] = crumble.base[first + 2]
                        continue
                    }

                    // Where along the flow: a soft start, a gliding middle and a slow arrival (smootherstep).
                    let u: Float = min(age / crumble.durations[piece], 1)
                    let along: Float = u * u * u * (u * (u * 6 - 15) + 10)
                    let onStream: SIMD3<Float> = crumble.stream.point(at: along)

                    // The flow's direction here, and two directions across it.
                    let ahead: SIMD3<Float> = crumble.stream.point(at: min(along + 0.01, 1))
                    let behind: SIMD3<Float> = crumble.stream.point(at: max(along - 0.01, 0))
                    var tangent: SIMD3<Float> = ahead - behind
                    tangent = simd_length(tangent) > 1e-6 ? simd_normalize(tangent) : crumble.up
                    var side: SIMD3<Float> = simd_cross(tangent, crumble.up)
                    if simd_length(side) < 1e-4 { side = simd_cross(tangent, SIMD3<Float>(1, 0, 0)) }
                    side = simd_normalize(side)
                    let across: SIMD3<Float> = simd_cross(tangent, side)

                    // Width: starts a little narrower, opens up, and narrows into one point at the end.
                    let left: Float = min(max((1 - along) / converge, 0), 1)
                    let spread: Float = left * left * (3 - 2 * left)
                    let open: Float = min(along / 0.35, 1)
                    let opening: Float = 0.35 + 0.65 * open * open * (3 - 2 * open)
                    let radius: Float = crumble.laneRadii[piece] * crumble.width * opening * spread

                    // Its place in the cross-section turns slowly as the flow twists.
                    let angle: Float = crumble.laneAngles[piece] + along * crumble.twist + t * 0.06
                    let laneSide: SIMD3<Float> = side * (cos(angle) * radius)
                    let laneAcross: SIMD3<Float> = across * (sin(angle) * radius)

                    // Slow, coherent, floaty turbulence: neighbouring pieces move alike in long, lazy waves,
                    // and the whole flow bobs gently – like cells carried along in a slow blood stream.
                    let laneAngle: Float = crumble.laneAngles[piece]
                    let wave1: Float = sin(along * 4 + laneAngle * 0.6 + t * 0.35)
                    let wave2: Float = cos(along * 3 - laneAngle * 0.4 + t * 0.28)
                    let bobbing: Float = sin(t * 0.45 + along * 2.5)
                    let strength: Float = crumble.turbulence * spread
                    let waves: SIMD3<Float> = side * (wave1 * strength) + across * (wave2 * 0.8 * strength)
                    let drift: SIMD3<Float> = waves + crumble.up * (bobbing * 0.6 * strength)

                    // Drawn into the flow: its offset from the cell's centre fades out over the first few cm.
                    let gathered: Float = exp(-(along * length) / crumble.gathering)
                    let fromCell: SIMD3<Float> = (crumble.centers[piece] - streamStart) * gathered
                    let inFlow: SIMD3<Float> = (laneSide + laneAcross + drift) * (1 - gathered)
                    let moved: SIMD3<Float> = onStream + fromCell + inFlow

                    // A little smaller on the way, then it shrinks into the point and vanishes there.
                    let size: Float = spread * (1 - 0.25 * along)
                    let turn = simd_quatf(angle: crumble.spins[piece] * age, axis: crumble.axes[piece])
                    let center: SIMD3<Float> = crumble.centers[piece]
                    for k in 0..<3 {
                        var vertex = crumble.base[first + k]
                        let local: SIMD3<Float> = (vertex.position - center) * size
                        vertex.position = moved + turn.act(local)
                        vertex.normal = turn.act(vertex.normal)
                        buffer[first + k] = vertex
                    }
                }
            }
        }
    }
}
