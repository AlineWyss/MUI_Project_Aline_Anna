//
//  BloodStream.swift
//  BloodCellJourney
//
//  The blood flowing through the anatomy model: many small red blood cells following the real
//  circulation in closed loops:
//
//    left heart → arteries → capillaries (slow, cells turn dark red) → veins → right heart
//    → pulmonary artery → lung capillaries (cells turn bright red again) → pulmonary veins → left heart
//
//  Arterial blood moves in pulses with every heart beat; capillaries are slow; veins flow steadily.
//
//  Size: a real red blood cell is 7–8 µm wide – far too small to see on the model. Instead the
//  cells are tiny (Config.flowCellDiameter, about 2 mm) and packed densely, so the stream reads as a
//  flowing liquid; single cells only show up close.
//  Performance: thousands of cells are drawn with GPU instancing (MeshInstancesComponent, visionOS 26)
//  instead of one entity per cell, and one system (BloodStreamSystem) moves them all every frame.
//

import Foundation
import RealityKit
import UIKit

/// Part of the circulation a segment belongs to.
enum VesselKind {
    case artery, capillary, vein, pulmonaryArtery, lungCapillary, pulmonaryVein

    /// Relative speed: wide arteries are fast, narrow capillaries slow, veins in between.
    var speedFactor: Float {
        switch self {
        case .artery, .pulmonaryArtery: return 1.0
        case .capillary, .lungCapillary: return 0.3
        case .vein, .pulmonaryVein: return 0.65
        }
    }

    /// Arteries carry the pressure pulse of each heart beat.
    var isPulsatile: Bool {
        self == .artery || self == .pulmonaryArtery
    }

    /// Oxygen-rich (scarlet) or oxygen-poor (dark red) blood in this part of the circulation.
    var isOxygenRich: Bool {
        switch self {
        case .artery, .lungCapillary, .pulmonaryVein: return true
        case .capillary, .vein, .pulmonaryArtery: return false
        }
    }
}

/// One closed loop of the circulation.
struct BloodCircuit {
    let path: SampledPath
    /// One entry per segment: `kinds[i]` lies between `path.points[i]` and `path.points[i + 1]`.
    let kinds: [VesselKind]
}

enum CirculationBuilder {
    /// One loop for every body branch × every lung (see AnatomyMap.systemicBranches).
    static func circuits() -> [BloodCircuit] {
        var result: [BloodCircuit] = []
        let lungs: [AnatomyMap.Landmark] = [.rLung, .lLung]
        for branch in AnatomyMap.systemicBranches {
            for lung in lungs {
                result.append(circuit(branch: branch, lung: lung))
            }
        }
        return result
    }

    private static func circuit(branch: [AnatomyMap.Landmark], lung: AnatomyMap.Landmark) -> BloodCircuit {
        var builder = CircuitBuilder()

        // Left heart → aorta → artery of this branch.
        let arterial = Curves.catmullRom(AnatomyMap.arterialPoints(branch), samplesPerSegment: 5)
        builder.append(arterial, kind: .artery)

        // Capillaries at the end of the branch: a small U-turn into the vein.
        let venous = Curves.catmullRom(AnatomyMap.venousPoints(branch), samplesPerSegment: 5)
        let end = arterial[arterial.count - 1]
        var outward = end - arterial[arterial.count - 2]
        outward = simd_length(outward) > 0.0001 ? simd_normalize(outward) : SIMD3<Float>(0, -1, 0)
        let tip = end + outward * 0.008 + AnatomyMap.veinOffset * 0.5
        builder.append([end, tip, venous[0]], kind: .capillary)

        // Vein back to the right heart.
        builder.append(venous, kind: .vein)

        // Right heart → pulmonary artery → lung.
        let pulmonary = AnatomyMap.pulmonaryPoints(lung: lung)
        let toLung = Curves.catmullRom(pulmonary.toLung, samplesPerSegment: 5)
        builder.append(toLung, kind: .pulmonaryArtery)

        // Lung capillaries around the air sacs: a small loop, then the pulmonary vein.
        let fromLung = Curves.catmullRom(pulmonary.fromLung, samplesPerSegment: 5)
        let lungPoint = toLung[toLung.count - 1]
        let side: Float = lung == .rLung ? -1 : 1
        let loopA = lungPoint + SIMD3<Float>(0.012 * side, -0.006, 0.003)
        let loopB = lungPoint + SIMD3<Float>(0.010 * side, -0.014, 0.004)
        builder.append([lungPoint, loopA, loopB, fromLung[0]], kind: .lungCapillary)

        // Pulmonary vein back to the left heart, where the loop started.
        builder.append(fromLung, kind: .pulmonaryVein)
        return builder.build()
    }
}

private struct CircuitBuilder {
    private var points: [SIMD3<Float>] = []
    private var kinds: [VesselKind] = []

    mutating func append(_ segment: [SIMD3<Float>], kind: VesselKind) {
        for point in segment {
            if let last = points.last, simd_distance(last, point) < 0.0005 { continue }
            if !points.isEmpty { kinds.append(kind) }
            points.append(point)
        }
    }

    func build() -> BloodCircuit {
        BloodCircuit(path: SampledPath(points), kinds: kinds.isEmpty ? [.artery] : kinds)
    }
}

/// Owns all flowing cells and moves them every frame.
///
/// There are two instanced entities: one draws the oxygen-rich (scarlet) cells, one the oxygen-poor
/// (dark red) ones. Every cell has a slot in both; the slot of the colour it does not have right now is
/// collapsed to zero size. That way a cell can change colour without moving data around.
@MainActor
final class BloodStream {
    private struct Cell {
        let circuit: Int
        var distance: Float
        let speed: Float
        /// Sideways position inside the vessel.
        let offset: SIMD3<Float>
        /// Rotation and size of the cell; the position is written into it every frame.
        let basis: simd_float4x4
    }

    let root = Entity()
    private let circuits: [BloodCircuit]
    private var cells: [Cell] = []
    private var oxygenRichCells: LowLevelInstanceData?
    private var oxygenPoorCells: LowLevelInstanceData?
    /// Transform of a slot that is not in use (zero size).
    private static let hidden = simd_float4x4(diagonal: SIMD4<Float>(0, 0, 0, 1))

    private var time: Float = 0
    private var lastBeat: Float = -10
    private var nextAutoBeat: Float = 0

    /// The heart beats by itself (resting rate). Off while the person pumps the heart.
    var autoBeat = true

    init(cellCount: Int) {
        root.name = "BloodStream"
        circuits = CirculationBuilder.circuits()

        var random = SeededRandom(seed: 11)
        let lengths = circuits.map { $0.path.length }
        let total = max(lengths.reduce(0, +), 0.001)
        let spread = Config.flowCellSpread

        for (circuitIndex, circuit) in circuits.enumerated() where circuit.path.length > 0 {
            let count = max(4, Int((Float(cellCount) * lengths[circuitIndex] / total).rounded()))
            for index in 0..<count {
                let distance = (Float(index) + random.next(in: 0...0.8)) / Float(count) * circuit.path.length
                var axis = SIMD3<Float>(random.next(in: -1...1), random.next(in: -1...1), random.next(in: -1...1))
                axis = simd_length(axis) > 0.01 ? simd_normalize(axis) : SIMD3<Float>(0, 1, 0)
                let basis = Transform(scale: SIMD3<Float>(repeating: random.next(in: 0.85...1.15)),
                                      rotation: simd_quatf(angle: random.next(in: 0...6.28), axis: axis),
                                      translation: SIMD3<Float>(0, 0, 0)).matrix
                let offset = SIMD3<Float>(random.next(in: -spread...spread),
                                          random.next(in: -spread...spread),
                                          random.next(in: -spread...spread))
                cells.append(Cell(circuit: circuitIndex,
                                  distance: distance,
                                  speed: Config.flowSpeed * random.next(in: 0.85...1.15),
                                  offset: offset,
                                  basis: basis))
            }
        }

        makeInstancedEntities()
        update(deltaTime: 0)   // every cell in place before the first frame
    }

    var cellCount: Int { cells.count }

    private func makeInstancedEntities() {
        guard !cells.isEmpty,
              let mesh = try? CellMesh.redBloodCell(diameter: Config.flowCellDiameter, rings: 1, segments: 8) else {
            return
        }
        oxygenRichCells = makeInstancedEntity(name: "OxygenRichCells", mesh: mesh, color: Palette.rbcOxygenated)
        oxygenPoorCells = makeInstancedEntity(name: "OxygenPoorCells", mesh: mesh, color: Palette.rbcDeoxygenated)
    }

    private func makeInstancedEntity(name: String, mesh: MeshResource, color: UIColor) -> LowLevelInstanceData? {
        do {
            let instances = try LowLevelInstanceData(instanceCount: cells.count)
            let entity = ModelEntity(mesh: mesh, materials: [MaterialTools.solid(color)])
            entity.name = name
            // Everywhere the cells can go on the model (model space, metres); used for culling.
            let bounds = BoundingBox(min: SIMD3<Float>(-0.4, -0.1, -0.35), max: SIMD3<Float>(0.4, 1.1, 0.35))
            let component = try MeshInstancesComponent(mesh: mesh,
                                                       modelID: mesh.contents.models.first?.id,
                                                       instances: instances,
                                                       bounds: bounds)
            entity.components.set(component)
            root.addChild(entity)
            return instances
        } catch {
            print("BloodStream: could not set up instancing for \(name): \(error)")
            return nil
        }
    }

    /// One heart beat: arterial blood surges forward.
    func beat() {
        lastBeat = time
    }

    func update(deltaTime: Float) {
        guard let oxygenRichCells, let oxygenPoorCells else { return }
        let dt = min(deltaTime, 0.1)
        time += dt
        if autoBeat && time >= nextAutoBeat {
            lastBeat = time
            nextAutoBeat = time + 60 / Config.restingHeartRate
        }
        // Pressure pulse after each beat, fading within a fraction of a second.
        let envelope = exp(-(time - lastBeat) * 5)
        let arterialPulse: Float = 0.35 + 1.6 * envelope
        let venousPulse: Float = 0.55 + 0.3 * envelope

        oxygenRichCells.withMutableTransforms { rich in
            oxygenPoorCells.withMutableTransforms { poor in
                for index in cells.indices {
                    var cell = cells[index]
                    let circuit = circuits[cell.circuit]
                    let located = circuit.path.locate(distance: cell.distance)
                    let kind = circuit.kinds[min(located.segment, circuit.kinds.count - 1)]

                    var pulse: Float = 1
                    if kind.isPulsatile {
                        pulse = arterialPulse
                    } else if kind == .vein || kind == .pulmonaryVein {
                        pulse = venousPulse
                    }
                    cell.distance += cell.speed * kind.speedFactor * pulse * dt
                    if cell.distance >= circuit.path.length {
                        cell.distance -= circuit.path.length
                    }
                    cells[index] = cell

                    var matrix = cell.basis
                    let position = located.point + cell.offset
                    matrix.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
                    if kind.isOxygenRich {
                        rich[index] = matrix
                        poor[index] = Self.hidden
                    } else {
                        rich[index] = Self.hidden
                        poor[index] = matrix
                    }
                }
            }
        }
    }
}

struct BloodStreamComponent: Component {
    let stream: BloodStream
}

struct BloodStreamSystem: System {
    static let query = EntityQuery(where: .has(BloodStreamComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            // Hidden (disabled) entities are still returned by queries – don't move cells nobody sees.
            guard entity.isEnabledInHierarchy else { continue }
            guard let stream = entity.components[BloodStreamComponent.self]?.stream else { continue }
            // RealityKit runs systems on the main thread; this tells the compiler so.
            MainActor.assumeIsolated {
                stream.update(deltaTime: dt)
            }
        }
    }
}

/// Small deterministic random generator, so the blood stream looks the same every time.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(state % 1_000_000) / 1_000_000
    }

    mutating func next(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * next()
    }
}
