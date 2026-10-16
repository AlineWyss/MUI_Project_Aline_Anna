//
//  ShellBake.swift
//  BloodCellJourney
//
//  Plays the developing shell's full animation from Blender – its shape keys and the soft-body wobble –
//  which RealityKit can't play by itself. Every frame's vertex positions were baked into
//  Resources/ShellDevelopment.json (Tools/export_shell_bake.py), like SqueezePath.json for the capillary.
//  A copy of the shell gets a LowLevelMesh whose vertices follow the baked frames (smoothly in between).
//  It keeps the shell's material, UVs, tangents and normals, so it looks exactly like the normal shell:
//  the normals only change by what the movement changes, and at rest they are the shell's own.
//  The JSON holds only the simulation (the shape in every frame). All timing is set in code:
//  skip the still frames at the start (`startFrame`), play the part up to `fastUntilFrame` at `fastSpeed`
//  and the rest at `lateSpeed`, make the wobble stronger while the cell grows (`growBoost`, fading back to
//  normal by `fastUntilFrame`) and ease it back to rest over the last `settleSeconds`.
//
//  ShellDevelopment.json: { "fps", "frameCount", "vertexCount",
//                           "rest":    [x, y, z, …] in metres (the shell's mesh space),
//                           "offsets": [[dx, dy, dz, …] per frame] in micrometres from the rest shape }
//

import Foundation
import Metal
import RealityKit

/// The baked frames: rest shape and every frame's vertex positions, in the mesh space of the shell's USDZ.
final class ShellBake: @unchecked Sendable {   // never changes after loading
    let fps: Float
    let frameCount: Int
    let vertexCount: Int
    let rest: [SIMD3<Float>]
    /// frameCount × vertexCount positions, frame after frame.
    let frames: [SIMD3<Float>]

    /// Seconds from the first to the last frame.
    var duration: Float { Float(max(frameCount - 1, 0)) / fps }

    /// Seconds the playback takes from `startFrame` when the frames up to `fastUntilFrame` play at
    /// `fastSpeed` and the rest at `lateSpeed` (1 = as in Blender).
    func duration(startFrame: Float = 0, fastUntilFrame: Float, fastSpeed: Float, lateSpeed: Float = 1) -> Float {
        let last = Float(max(frameCount - 1, 0))
        let start = min(max(startFrame, 0), last)
        let fast = min(max(fastUntilFrame, start), last)
        return (fast - start) / (fps * max(fastSpeed, 0.01)) + (last - fast) / (fps * max(lateSpeed, 0.01))
    }

    /// Smooth normals of a shape (one per bake vertex), from the given triangles.
    func normals(of positions: ArraySlice<SIMD3<Float>>, triangles: [Int]) -> [SIMD3<Float>] {
        let start = positions.startIndex
        var normals = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var i = 0
        while i + 2 < triangles.count {
            let p = triangles[i], q = triangles[i + 1], r = triangles[i + 2]
            let n = simd_cross(positions[start + q] - positions[start + p], positions[start + r] - positions[start + p])
            normals[p] += n
            normals[q] += n
            normals[r] += n
            i += 3
        }
        return normals.map { simd_length($0) > 1e-12 ? simd_normalize($0) : .zero }
    }

    /// Loaded once from the app bundle; nil if the file is missing or broken.
    /// Loaded once by preload(); nil until then, or if the file is missing or broken.
    @MainActor private(set) static var shared: ShellBake?
    @MainActor private static var isPreloaded = false

    /// Reads Resources/ShellDevelopment.json (2.4 MB) on a background thread – decoding it on the main
    /// thread froze the loading screen. Called once from ModelLibrary.load().
    @MainActor static func preload() async {
        guard !isPreloaded else { return }
        isPreloaded = true
        shared = await Task.detached(priority: .userInitiated) { ShellBake.load() }.value
    }

    private init(fps: Float, frameCount: Int, vertexCount: Int, rest: [SIMD3<Float>], frames: [SIMD3<Float>]) {
        self.fps = fps
        self.frameCount = frameCount
        self.vertexCount = vertexCount
        self.rest = rest
        self.frames = frames
    }

    private struct File: Decodable {
        let fps: Float
        let frameCount: Int
        let vertexCount: Int
        let rest: [Float]
        let offsets: [[Int32]]
    }

    private static func load() -> ShellBake? {
        guard let url = Bundle.main.url(forResource: "ShellDevelopment", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            print("ShellBake: Resources/ShellDevelopment.json is missing or broken – the cell pops in instead.")
            return nil
        }
        let count = file.vertexCount
        guard file.frameCount > 1, count > 0, file.fps > 0, file.rest.count == count * 3,
              file.offsets.count == file.frameCount, file.offsets.allSatisfy({ $0.count == count * 3 }) else {
            print("ShellBake: ShellDevelopment.json has the wrong size – the cell pops in instead.")
            return nil
        }
        let rest = (0..<count).map { SIMD3<Float>(file.rest[$0 * 3], file.rest[$0 * 3 + 1], file.rest[$0 * 3 + 2]) }
        var frames: [SIMD3<Float>] = []
        frames.reserveCapacity(file.frameCount * count)
        for offsets in file.offsets {
            for k in 0..<count {
                let offset = SIMD3<Float>(Float(offsets[k * 3]), Float(offsets[k * 3 + 1]), Float(offsets[k * 3 + 2]))
                frames.append(rest[k] + offset / 1_000_000)          // micrometres → metres
            }
        }
        return ShellBake(fps: file.fps, frameCount: file.frameCount, vertexCount: count, rest: rest, frames: frames)
    }
}

/// One vertex of the playing mesh.
struct ShellBakeVertex {
    var position: SIMD3<Float> = .zero
    var normal: SIMD3<Float> = .zero
    var tangent: SIMD3<Float> = .zero
    var bitangent: SIMD3<Float> = .zero
    var uv: SIMD2<Float> = .zero
}

struct ShellPlaybackComponent: Component {
    let bake: ShellBake
    let mesh: LowLevelMesh
    /// The mesh's vertices as the shell has them (normals, tangents, UVs); positions are replaced every frame.
    let base: [ShellBakeVertex]
    /// The smooth normals of the rest shape (per bake vertex): each frame only adds how the movement
    /// changes them, so at rest the shell's own normals are back exactly.
    let restNormals: [SIMD3<Float>]
    /// Playback starts at this frame (skips the still frames at the beginning).
    let startFrame: Float
    /// Frames up to here play at `fastSpeed`, the rest at `lateSpeed` (1 = as in Blender).
    let fastUntilFrame: Float
    let fastSpeed: Float
    let lateSpeed: Float
    /// Extra wobble while the cell grows: 1.5 = two and a half times as strong at the start,
    /// fading back to normal by fastUntilFrame (where the cell reaches full size).
    let growBoost: Float
    /// Over the last seconds of the playback the wobble eases back to rest (0 = it simply stops at the end).
    let settleSeconds: Float
    /// For every mesh vertex: its vertex in the bake (RealityKit splits vertices at UV seams).
    let bakeIndex: [Int]
    /// The mesh's triangles, as bake vertices (for smooth normals every frame).
    let triangles: [Int]
    /// From the bake's mesh space to this mesh's space (usually identity).
    let transform: simd_float4x4
    var time: Float = 0
}

@MainActor
enum ShellBakePlayer {
    /// Lets every mesh below `root` (a copy of the shell) follow the bake. Returns false if the shell's
    /// mesh doesn't match the bake (then nothing is changed).
    static func attach(_ bake: ShellBake, to root: Entity, startFrame: Float = 0,
                       fastUntilFrame: Float = 0, fastSpeed: Float = 1, lateSpeed: Float = 1,
                       growBoost: Float = 0, settleSeconds: Float = 0) -> Bool {
        var made: [(Entity, ModelComponent, ShellPlaybackComponent)] = []
        var fits = true
        root.forEachModelEntity { entity in
            guard fits, var model = entity.components[ModelComponent.self] else { return }
            guard let playback = try? makePlayback(bake, from: model.mesh, startFrame: startFrame,
                                                   fastUntilFrame: fastUntilFrame, fastSpeed: fastSpeed,
                                                   lateSpeed: lateSpeed, growBoost: growBoost,
                                                   settleSeconds: settleSeconds) else {
                fits = false
                return
            }
            model.mesh = playback.resource
            made.append((entity, model, playback.component))
        }
        guard fits, !made.isEmpty else {
            print("ShellBake: the shell's mesh doesn't match ShellDevelopment.json – the cell pops in instead.")
            return false
        }
        for (entity, model, component) in made {
            entity.components.remove(BlendShapeWeightsComponent.self)
            entity.components.set(model)
            entity.components.set(component)
        }
        return true
    }

    private enum PlaybackError: Error { case doesNotMatch }

    private static func makePlayback(_ bake: ShellBake, from source: MeshResource, startFrame: Float,
                                     fastUntilFrame: Float, fastSpeed: Float, lateSpeed: Float,
                                     growBoost: Float, settleSeconds: Float)
        throws -> (resource: MeshResource, component: ShellPlaybackComponent) {
        // Find every bake vertex by its rest position (same mesh, so the positions match to a micrometre).
        func bakeVertex(at p: SIMD3<Float>) -> Int? {
            var best = -1
            var bestDistance = Float.greatestFiniteMagnitude
            for (index, point) in bake.rest.enumerated() {
                let distance = simd_distance_squared(point, p)
                if distance < bestDistance { bestDistance = distance; best = index }
            }
            return best >= 0 && bestDistance < 0.00005 * 0.00005 ? best : nil      // within 0.05 mm
        }

        var vertices: [ShellBakeVertex] = []
        var bakeIndex: [Int] = []
        var indices: [UInt32] = []
        var materialIndex: Int?
        guard source.contents.instances.count == 1, let instance = source.contents.instances.first,
              let model = source.contents.models[instance.model] else { throw PlaybackError.doesNotMatch }
        let transform = instance.transform
        for part in model.parts {
            guard let triangles = part.triangleIndices?.elements else { continue }
            if let materialIndex, materialIndex != part.materialIndex { throw PlaybackError.doesNotMatch }
            materialIndex = part.materialIndex
            let positions = part.positions.elements
            let normals = part.normals?.elements
            let tangents = part.tangents?.elements
            let bitangents = part.bitangents?.elements
            let uvs = part.textureCoordinates?.elements
            let first = UInt32(vertices.count)
            for i in positions.indices {
                guard let found = bakeVertex(at: positions[i]) else { throw PlaybackError.doesNotMatch }
                bakeIndex.append(found)
                let normal = (normals != nil && i < normals!.count) ? normals![i] : SIMD3<Float>(0, 0, 1)
                // Tangents carry the normal map of the shell's material; without them it looks different.
                var tangent = (tangents != nil && i < tangents!.count) ? tangents![i] : .zero
                if simd_length(tangent) < 1e-6 {
                    let helper = abs(normal.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
                    tangent = simd_normalize(simd_cross(helper, normal))
                }
                var bitangent = (bitangents != nil && i < bitangents!.count) ? bitangents![i] : .zero
                if simd_length(bitangent) < 1e-6 { bitangent = simd_cross(normal, tangent) }
                let uv = (uvs != nil && i < uvs!.count) ? uvs![i] : .zero
                vertices.append(ShellBakeVertex(position: positions[i], normal: normal,
                                                tangent: tangent, bitangent: bitangent, uv: uv))
            }
            indices += triangles.map { $0 + first }
        }
        guard !vertices.isEmpty, !indices.isEmpty else { throw PlaybackError.doesNotMatch }

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<ShellBakeVertex>.offset(of: \.position)!),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<ShellBakeVertex>.offset(of: \.normal)!),
            .init(semantic: .tangent, format: .float3, offset: MemoryLayout<ShellBakeVertex>.offset(of: \.tangent)!),
            .init(semantic: .bitangent, format: .float3, offset: MemoryLayout<ShellBakeVertex>.offset(of: \.bitangent)!),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<ShellBakeVertex>.offset(of: \.uv)!)
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<ShellBakeVertex>.stride)]
        descriptor.vertexCapacity = vertices.count
        descriptor.indexCapacity = indices.count
        descriptor.indexType = .uint32

        let mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let buffer = raw.bindMemory(to: ShellBakeVertex.self)
            for i in vertices.indices { buffer[i] = vertices[i] }
        }
        mesh.withUnsafeMutableIndices { raw in
            let buffer = raw.bindMemory(to: UInt32.self)
            for i in indices.indices { buffer[i] = indices[i] }
        }

        // Bounds that include every baked frame.
        var low = bake.rest[0], high = bake.rest[0]
        for (index, point) in bake.frames.enumerated() {
            let rest = bake.rest[index % bake.vertexCount]
            let boosted = rest + (point - rest) * (1 + max(growBoost, 0))
            low = simd_min(low, simd_min(point, boosted))
            high = simd_max(high, simd_max(point, boosted))
        }
        let corners = [low, high, SIMD3<Float>(low.x, high.y, low.z), SIMD3<Float>(high.x, low.y, high.z)]
            .map { transform * SIMD4<Float>($0, 1) }
            .map { SIMD3<Float>($0.x, $0.y, $0.z) }
        var boxLow = corners[0], boxHigh = corners[0]
        for corner in corners {
            boxLow = simd_min(boxLow, corner)
            boxHigh = simd_max(boxHigh, corner)
        }
        let margin = (boxHigh - boxLow) * 0.1
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: indices.count,
                              topology: .triangle,
                              materialIndex: materialIndex ?? 0,
                              bounds: BoundingBox(min: boxLow - margin, max: boxHigh + margin))
        ])

        let resource = try MeshResource(from: mesh)
        let triangles = indices.map { bakeIndex[Int($0)] }
        let restNormals = bake.normals(of: bake.rest[...], triangles: triangles)
        let component = ShellPlaybackComponent(bake: bake, mesh: mesh, base: vertices,
                                               restNormals: restNormals,
                                               startFrame: max(startFrame, 0),
                                               fastUntilFrame: fastUntilFrame, fastSpeed: max(fastSpeed, 0.01),
                                               lateSpeed: max(lateSpeed, 0.01),
                                               growBoost: max(growBoost, 0),
                                               settleSeconds: max(settleSeconds, 0),
                                               bakeIndex: bakeIndex, triangles: triangles,
                                               transform: transform)
        return (resource, component)
    }
}

/// Moves the shell's vertices along the baked frames, smoothly in between. The frames up to
/// `fastUntilFrame` play `fastSpeed` times faster. Normals keep the shell's own and only add what the
/// movement changes. After the last frame it holds the last (rest) shape.
struct ShellPlaybackSystem: System {
    static let query = EntityQuery(where: .has(ShellPlaybackComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var playback = entity.components[ShellPlaybackComponent.self] else { continue }
            playback.time += dt
            entity.components.set(playback)

            let bake = playback.bake
            let count = bake.vertexCount
            let last = Float(bake.frameCount - 1)
            // From startFrame; faster up to fastUntilFrame, normal speed after it.
            let start = min(playback.startFrame, last)
            let fastFrames = min(max(playback.fastUntilFrame, start), last)
            let fastTime = (fastFrames - start) / (bake.fps * playback.fastSpeed)
            let played = playback.time < fastTime
                ? start + playback.time * bake.fps * playback.fastSpeed
                : fastFrames + (playback.time - fastTime) * bake.fps * playback.lateSpeed
            let frame = min(played, last)
            // Stronger wobble while growing, fading smoothly back to normal by fastUntilFrame.
            let growth = fastFrames > start ? min(max((frame - start) / (fastFrames - start), 0), 1) : 1
            let boost = 1 + playback.growBoost * (1 - growth * growth * (3 - 2 * growth))
            // Settle: over the last settleSeconds of the playback the wobble eases back to rest.
            let total = fastTime + (last - fastFrames) / (bake.fps * playback.lateSpeed)
            var settle: Float = 1
            if playback.settleSeconds > 0 {
                let s = min(max((playback.time - (total - playback.settleSeconds)) / playback.settleSeconds, 0), 1)
                settle = 1 - s * s * (3 - 2 * s)
            } else if playback.time >= total {
                settle = 0
            }
            let strength = boost * settle
            let a = Int(frame)
            let b = min(a + 1, bake.frameCount - 1)
            let t = frame - Float(a)

            // Positions of this moment (between two baked frames).
            var positions = [SIMD3<Float>](repeating: .zero, count: count)
            for k in 0..<count {
                let point = simd_mix(bake.frames[a * count + k], bake.frames[b * count + k], SIMD3<Float>(repeating: t))
                positions[k] = bake.rest[k] + (point - bake.rest[k]) * strength
            }
            // How the movement turns the surface: smooth normals now, minus those of the rest shape.
            let moved = bake.normals(of: positions[...], triangles: playback.triangles)

            let transform = playback.transform
            playback.mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
                let buffer = raw.bindMemory(to: ShellBakeVertex.self)
                for m in playback.base.indices {
                    var vertex = playback.base[m]
                    let k = playback.bakeIndex[m]
                    let p = transform * SIMD4<Float>(positions[k], 1)
                    vertex.position = SIMD3<Float>(p.x, p.y, p.z)
                    let change = transform * SIMD4<Float>(moved[k] - playback.restNormals[k], 0)
                    let normal = vertex.normal + SIMD3<Float>(change.x, change.y, change.z)
                    if simd_length(normal) > 1e-6 { vertex.normal = simd_normalize(normal) }
                    buffer[m] = vertex
                }
            }
        }
    }
}

// MARK: - Growing

/// Grows an entity from nothing to `target` in `duration` seconds while it turns: fast at first, slowing
/// down, and coming to rest exactly when it reaches full size. It ends in the orientation it had, so
/// nothing changes afterwards. Optional pulses and squash-and-stretch make it look alive while it grows;
/// they fade out completely by full size. The developing shell and its nucleus grow in the same time.
struct GrowComponent: Component {
    var target: SIMD3<Float>
    var duration: Float
    /// Orientation at full size (the entity's normal orientation).
    var finalOrientation: simd_quatf
    /// How far it turns while growing, in radians (negative = the other way), and around which axis.
    var spin: Float = .pi
    var axis: SIMD3<Float> = simd_normalize(SIMD3<Float>(0.25, 1, 0.15))
    /// Soft growth pulses: how many, and how strong (0.12 = swells up to 12 % in between).
    var pulses: Float = 0
    var pulseAmount: Float = 0
    /// Squash and stretch: how much width, height and depth shift against each other (0.08 = 8 %).
    var squash: Float = 0
    /// A small pop when it reaches full size: how far it swells (0.06 = 6 %), how long it takes, and how
    /// long after reaching full size it starts (0 = right then). 0 = no pop.
    var popAmount: Float = 0
    var popDuration: Float = 0.35
    var popDelay: Float = 0
    var time: Float = 0
}

struct GrowSystem: System {
    static let query = EntityQuery(where: .has(GrowComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var grow = entity.components[GrowComponent.self] else { continue }
            grow.time += dt
            let t = min(grow.time / max(grow.duration, 0.01), 1)
            // Everything extra fades out smoothly towards full size.
            let fading = (1 - t) * (1 - t)

            // Size: soft start, soft arrival at full size (smootherstep), with optional pulses.
            var size = t * t * t * (t * (t * 6 - 15) + 10)
            size *= 1 + grow.pulseAmount * sin(t * grow.pulses * 2 * .pi) * fading
            // Squash and stretch: the three directions swell and shrink a third of a cycle apart.
            let phase = t * 2 * .pi * 2.5
            let stretch = SIMD3<Float>(sin(phase), sin(phase + 2.094), sin(phase + 4.189)) * grow.squash * fading
            entity.scale = grow.target * max(size, 0.001) * (SIMD3<Float>(repeating: 1) + stretch)

            // Turn: fast at first, slowing to a stop at full size (ease-out), ending at the normal orientation.
            let remaining = (1 - t) * (1 - t) * (1 - t)
            let turn = simd_quatf(angle: -grow.spin * remaining, axis: grow.axis)
            entity.orientation = turn * grow.finalOrientation

            if t >= 1 {
                entity.orientation = grow.finalOrientation
                // The small pop after reaching full size (if any): a quick swell that settles back.
                let afterFull = grow.time - grow.duration - grow.popDelay
                if grow.popAmount > 0, afterFull < grow.popDuration {
                    let p = max(afterFull / max(grow.popDuration, 0.01), 0)
                    let swell = sin(p * .pi)
                    entity.scale = grow.target * (1 + grow.popAmount * swell * swell)
                    entity.components.set(grow)
                } else {
                    entity.scale = grow.target
                    entity.components.remove(GrowComponent.self)
                }
            } else {
                entity.components.set(grow)
            }
        }
    }
}
