//
//  SqueezeScene.swift
//  BloodCellJourney
//
//  The squeeze from claudeAniamtion.blend, played by dragging: the further the person pushes the red
//  blood cell along the animated path, the further the animation runs – the cell folds through its
//  shapes and the capillary wall bulges, exactly as in Blender (all modifiers applied).
//
//  The models come from Reality Composer Pro, scene "SqueezeScene" (SqueezeAnimation.usdz, exported
//  by Tools/export_squeeze.py). There you can change their materials and rotate / scale the entity
//  "Squeeze". The app moves the cell along the path (SqueezePath.json) and sets the blend shape weights.
//
//  Used twice: the young cell squeezes all the way into the capillary (step "squeeze"), the old
//  stiff cell only gets as far as Timing.agingStopFrame and is pushed back (step "aging").
//

import Foundation
import RealityKit
import RealityKitContent
import UIKit

@MainActor
final class SqueezeScene {
    enum LoadError: LocalizedError {
        case missingEntity(String)
        var errorDescription: String? {
            switch self {
            case .missingEntity(let name):
                return "The entity “\(name)” is missing in the Reality Composer Pro scene SqueezeScene."
            }
        }
    }

    let animation: SqueezeAnimation
    /// The capillary (a stage item, so it can carry a label and be removed like any model).
    let capillary: StageItem
    /// Path of the cell in focus-area space: one point per animation frame.
    let path: SampledPath
    /// Holds the cell model from Reality Composer Pro. Shown in place of the normal model while squeezing.
    let cellModel: Entity
    /// Height of the capillary label above the capillary's container.
    let labelHeight: Float

    /// Transform of `cellModel` that matches the normal red blood cell model (size, facing the person).
    private let normalTransform: Transform
    /// Same size as the normal model, turned so the cell's flat side faces the person.
    private let facingTransform: Transform
    /// The pose in which the squeeze cell lies exactly on the normal cell (set in attach).
    private var normalPose: Transform?

    /// From the squeeze cell's mesh (SqueezeAnimation.usdz, "Cell") to the red blood cell's mesh
    /// (RedBloodCell.usdz) – the same mesh, stored turned. Measured from all 4,610 vertices (≈ 1 mm apart).
    private static let squeezeToCell = simd_float4x4(columns: (
        SIMD4<Float>(-0.148277, -0.979460, 0.133401, 0.000000),
        SIMD4<Float>(0.094153, -0.148274, -0.984009, 0.000000),
        SIMD4<Float>(0.984009, -0.133405, 0.114255, 0.000000),
        SIMD4<Float>(-0.000000, -0.000005, 0.000000, 1.000000)
    ))
    /// Transform of `cellModel` inside the scene: rotation and scale of "Squeeze" in Reality Composer Pro.
    private let sceneTransform: Transform
    private let cellShapes: Entity?
    private let capillaryShapes: Entity?
    private var shownFrame: Float = -1
    private var animationToken = 0
    private(set) var frame: Float

    var firstFrame: Float { Float(animation.firstFrame) }
    var lastFrame: Float { Float(animation.lastFrame) }
    /// Where the cell starts (focus-area space).
    var start: SIMD3<Float> { path.points[0] }

    /// The scene from Reality Composer Pro, loaded once and cloned for every use.
    private static var prototype: Entity?

    /// - Parameters:
    ///   - start: Where the cell starts in the focus area. The capillary is placed relative to it.
    ///   - cellSize: Size of the normal red blood cell model (its longest side), so the swap of the normal
    ///     model for the squeezing one is invisible.
    ///   - cellColor: The cell's current colour in the story (young / old). Tints the cell if its material
    ///     in Reality Composer Pro is a physically based one; shader graph materials stay as they are.
    init(animation: SqueezeAnimation, start: SIMD3<Float>, cellSize: Float, cellColor: UIColor?) async throws {
        self.animation = animation
        self.frame = Float(animation.firstFrame)

        let root: Entity
        if let prototype = SqueezeScene.prototype {
            root = prototype.clone(recursive: true)
        } else {
            let loaded = try await Entity(named: "SqueezeScene", in: realityKitContentBundle)
            SqueezeScene.prototype = loaded
            root = loaded.clone(recursive: true)
        }
        guard let squeeze = root.findEntity(named: "Squeeze") else { throw LoadError.missingEntity("Squeeze") }
        guard let cellRoot = squeeze.findEntity(named: "Cell") else { throw LoadError.missingEntity("Cell") }
        guard let capillaryRoot = squeeze.findEntity(named: "Capillary") else { throw LoadError.missingEntity("Capillary") }

        // Rotation and scale set on "Squeeze" in Reality Composer Pro (its position is not used).
        let rotation = squeeze.orientation
        let scale = squeeze.scale
        let sceneTransform = Transform(scale: scale, rotation: rotation)
        self.sceneTransform = sceneTransform

        // Cell: lifted out of the scene into a holder; inside it keeps its transform within "Squeeze".
        let cellToScene = cellRoot.transformMatrix(relativeTo: squeeze)
        cellRoot.removeFromParent()
        cellRoot.transform = Transform(matrix: cellToScene)
        let holder = Entity()
        holder.name = "SqueezingRedBloodCell"
        holder.addChild(cellRoot)
        let bounds = holder.visualBounds(relativeTo: holder)
        let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let normalScale = longest > 0 ? cellSize / longest : 1
        let normalTransform = Transform(scale: SIMD3<Float>(repeating: normalScale))
        holder.transform = normalTransform
        if Config.squeezeCellUsesStoryColor, let cellColor {
            SqueezeScene.tint(holder, cellColor)
        }
        self.normalTransform = normalTransform
        let flatSide = SqueezeScene.flatSideNormal(of: holder)
        self.facingTransform = Transform(scale: SIMD3<Float>(repeating: normalScale),
                                         rotation: simd_quatf(from: flatSide.z < 0 ? -flatSide : flatSide,
                                                              to: SIMD3<Float>(0, 0, 1)))
        self.cellModel = holder
        self.cellShapes = SqueezeScene.blendShapeEntity(in: cellRoot)

        // Path: the animated cell positions, turned and scaled like "Squeeze", the first one at `start`.
        let origin = start - rotation.act(animation.cellPositions[0] * scale)
        self.path = SampledPath(animation.cellPositions.map { origin + rotation.act($0 * scale) })

        // Capillary: the rest of the scene (keeps the rotation and scale of "Squeeze") at the entry point.
        squeeze.removeFromParent()
        squeeze.position = SIMD3<Float>(0, 0, 0)
        SqueezeScene.showInsideOfWall(capillaryRoot)
        let capillary = StageItem(name: "Capillary")
        capillary.body.addChild(squeeze)
        capillary.container.position = origin
        self.capillary = capillary
        self.capillaryShapes = SqueezeScene.blendShapeEntity(in: capillaryRoot)
        self.labelHeight = squeeze.visualBounds(relativeTo: capillary.container).max.y + Layout.labelGap
            - Layout.capillaryLabelDrop

        apply(frame: frame)
    }

    // MARK: - Swapping the cell's model

    /// Shows the squeezing cell instead of the cell's normal model, lying exactly on it (so nothing
    /// jumps), then shrinks and turns it to fit the scene.
    func attach(to cell: StageItem, duration: TimeInterval) {
        cell.body.isEnabled = false
        cellModel.removeFromParent()
        cell.motion.addChild(cellModel)
        // Starts lying exactly on the normal cell, so the swap can't be seen; from there it turns
        // smoothly into its place in the capillary.
        normalPose = pose(matching: cell)
        cellModel.transform = normalPose ?? facingTransform
        cellModel.move(to: sceneTransform, relativeTo: cell.motion, duration: duration, timingFunction: .easeInOut)
    }

    /// Grows and turns the squeezing cell back to match the normal model.
    func restoreSize(duration: TimeInterval) {
        guard let parent = cellModel.parent else { return }
        cellModel.move(to: normalTransform, relativeTo: parent, duration: duration, timingFunction: .easeInOut)
    }

    /// Turns the cell smoothly back into the pose of the normal cell (normal size, facing the person).
    func faceFront(duration: TimeInterval) {
        guard let parent = cellModel.parent else { return }
        cellModel.move(to: normalPose ?? facingTransform, relativeTo: parent, duration: duration,
                       timingFunction: .easeInOut)
    }
    
    /// Puts the cell into its normal shape and the normal cell's pose at once (while it is out of sight).
    func snapToNormal() {
        show(frame: firstFrame)
        cellModel.stopAllAnimations()
        cellModel.transform = normalPose ?? facingTransform
    }
    
    /// Relaxes the cell straight from its current squeezed shape into its normal shape – without playing
    /// the squeeze backwards (which would pass through its folded, triangle-like shapes).
    func relax(duration: TimeInterval) async {
        guard let cellShapes else { return }
        animationToken += 1
        let token = animationToken
        let squeezed = animation.cellWeights(at: frame)
        let steps = max(Int(duration * 60), 1)
        for step in 1...steps {
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
            guard token == animationToken else { return }
            let p = Float(step) / Float(steps)
            let left = 1 - p * p * (3 - 2 * p)
            SqueezeScene.setWeights(squeezed.map { $0 * left }, names: animation.cellBlendShapes, on: cellShapes)
        }
        frame = firstFrame
        shownFrame = firstFrame
    }

    /// The holder's pose (relative to the cell's motion entity) in which the squeeze cell's mesh lies
    /// exactly where the normal cell's mesh is.
    private func pose(matching cell: StageItem) -> Transform? {
        guard let squeezeMesh = Self.firstModel(in: cellModel),
              let cellMesh = Self.firstModel(in: cell.body) else { return nil }
        let meshInHolder = squeezeMesh.transformMatrix(relativeTo: cellModel)
        let cellMeshInMotion = cellMesh.transformMatrix(relativeTo: cell.motion)
        return Transform(matrix: cellMeshInMotion * Self.squeezeToCell * meshInHolder.inverse)
    }

    /// Back to the normal model with a crossfade; after faceFront both face the same way.
    func crossfadeBack(to cell: StageItem, duration: TimeInterval) {
        let model = cellModel
        let speed = Float(1 / max(duration, 0.1))
        cell.body.isEnabled = true
        cell.body.components.set(OpacityComponent(opacity: 0))
        cell.body.components.set(FadeComponent(target: 1, speed: speed, disableWhenHidden: false))
        model.components.set(FadeComponent(target: 0, speed: speed, disableWhenHidden: false))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            model.removeFromParent()
        }
    }

    /// Direction of the cell's flat side (where its vertices spread least), in `root`'s space.
    private static func flatSideNormal(of root: Entity) -> SIMD3<Float> {
        var points: [SIMD3<Float>] = []
        root.forEachModelEntity { entity in
            guard let mesh = entity.components[ModelComponent.self]?.mesh else { return }
            let toRoot = entity.transformMatrix(relativeTo: root)
            for model in mesh.contents.models {
                for part in model.parts {
                    for p in part.positions.elements {
                        let w = toRoot * SIMD4<Float>(p, 1)
                        points.append(SIMD3<Float>(w.x, w.y, w.z))
                    }
                }
            }
        }
        guard points.count > 3 else { return SIMD3<Float>(0, 0, 1) }
        let mean = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        var spread = simd_float3x3()
        for p in points {
            let d = p - mean
            spread = spread + simd_float3x3(columns: (d * d.x, d * d.y, d * d.z))
        }
        // Smallest spread = largest eigenvector of (trace·I − spread), found by repeated multiplication.
        let trace = spread[0][0] + spread[1][1] + spread[2][2]
        let flipped = simd_float3x3(diagonal: SIMD3<Float>(repeating: trace)) - spread
        var normal = simd_normalize(SIMD3<Float>(0.3, 0.5, 0.8))
        for _ in 0..<40 {
            let next = flipped * normal
            if simd_length(next) < 1e-12 { break }
            normal = simd_normalize(next)
        }
        return normal
    }

    /// Back to the cell's normal model.
    func detach(from cell: StageItem) {
        cellModel.removeFromParent()
        cell.body.isEnabled = true
    }

    // MARK: - Frames and distances

    /// Animation frame at a distance (metres) along the path.
    func frame(atDistance distance: Float) -> Float {
        let cumulative = path.cumulative
        guard cumulative.count > 1 else { return firstFrame }
        let d = min(max(distance, 0), path.length)
        var low = 0
        var high = cumulative.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulative[middle] < d { low = middle } else { high = middle }
        }
        let segment = cumulative[high] - cumulative[low]
        let t = segment > 0 ? (d - cumulative[low]) / segment : 0
        return firstFrame + Float(low) + t
    }

    /// Distance (metres) along the path at an animation frame.
    func distance(atFrame frame: Float) -> Float {
        let cumulative = path.cumulative
        let position = min(max(frame - firstFrame, 0), Float(cumulative.count - 1))
        let low = Int(position.rounded(.down))
        let high = min(low + 1, cumulative.count - 1)
        let t = position - Float(low)
        return cumulative[low] + (cumulative[high] - cumulative[low]) * t
    }

    /// Cell position (focus-area space) at an animation frame.
    func position(atFrame frame: Float) -> SIMD3<Float> {
        path.locate(distance: distance(atFrame: frame)).point
    }

    // MARK: - Showing the animation

    /// Shows the animation at `frame` (cell shape and capillary bulge). Stops a running `animate`.
    func show(frame: Float) {
        animationToken += 1
        apply(frame: frame)
    }

    /// Runs the animation to `target` over `duration` seconds and moves `cell` along the path with it.
    /// `includeCapillary: false` leaves the capillary wall as it is (when the cell relaxes after it got through).
    func animate(to target: Float, duration: TimeInterval, moving cell: StageItem? = nil,
                 includeCapillary: Bool = true) async {
        animationToken += 1
        let token = animationToken
        let from = frame
        let steps = max(Int(duration * 60), 1)
        for step in 1...steps {
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
            guard token == animationToken else { return }
            let progress = Float(step) / Float(steps)
            let eased = progress * progress * (3 - 2 * progress)
            let value = from + (target - from) * eased
            apply(frame: value, includeCapillary: includeCapillary)
            if let cell {
                cell.container.position = position(atFrame: value)
            }
        }
    }

    private func apply(frame value: Float, includeCapillary: Bool = true) {
        frame = min(max(value, firstFrame), lastFrame)
        guard abs(frame - shownFrame) > 0.0005 else { return }
        shownFrame = frame
        if let cellShapes {
            SqueezeScene.setWeights(animation.cellWeights(at: frame), names: animation.cellBlendShapes, on: cellShapes)
        }
        if includeCapillary, let capillaryShapes {
            SqueezeScene.setWeights([animation.bulge(at: frame)], names: [animation.capillaryBlendShape],
                                    on: capillaryShapes)
        }
    }

    // MARK: - Blend shapes

    /// The entity below `root` whose mesh has the blend shapes. Gets a BlendShapeWeightsComponent if
    /// RealityKit didn't add one when loading.
    private static func blendShapeEntity(in root: Entity) -> Entity? {
        if let found = entityWithWeights(in: root) { return found }
        guard let model = firstModel(in: root), let mesh = model.components[ModelComponent.self]?.mesh else {
            return nil
        }
        model.components.set(BlendShapeWeightsComponent(weightsMapping: BlendShapeWeightsMapping(meshResource: mesh)))
        return model
    }

    private static func entityWithWeights(in entity: Entity) -> Entity? {
        if entity.components.has(BlendShapeWeightsComponent.self) { return entity }
        for child in entity.children {
            if let found = entityWithWeights(in: child) { return found }
        }
        return nil
    }

    private static func firstModel(in entity: Entity) -> Entity? {
        if entity.components.has(ModelComponent.self) { return entity }
        for child in entity.children {
            if let found = firstModel(in: child) { return found }
        }
        return nil
    }

    /// Sets the weights by name. Weights whose name RealityKit reports empty or unknown are set by their
    /// position (the order of the export).
    private static func setWeights(_ values: [Float], names: [String], on entity: Entity) {
        guard var component = entity.components[BlendShapeWeightsComponent.self] else { return }
        var weightSet = component.weightSet
        guard var data = weightSet.default ?? weightSet.first else { return }
        let weightNames = data.weightNames
        var weights = [Float](repeating: 0, count: weightNames.count)
        for (index, weightName) in weightNames.enumerated() {
            if !weightName.isEmpty, let match = names.firstIndex(where: { weightName.hasSuffix($0) }) {
                weights[index] = match < values.count ? values[match] : 0
            } else if index < values.count {
                weights[index] = values[index]
            }
        }
        data.weights = BlendShapeWeights(weights)
        _ = weightSet.set(data)
        component.weightSet = weightSet
        entity.components.set(component)
    }

    // MARK: - Materials

    /// The capillary is an open tube: draw the inside of the wall too (whatever material it has).
    private static func showInsideOfWall(_ root: Entity) {
        MaterialTools.visitModels(root) { model in
            model.materials = model.materials.map { material -> any RealityKit.Material in
                if var pbr = material as? PhysicallyBasedMaterial {
                    pbr.faceCulling = .none
                    return pbr
                }
                if var shaderGraph = material as? ShaderGraphMaterial {
                    shaderGraph.faceCulling = .none
                    return shaderGraph
                }
                return material
            }
        }
    }

    /// Tints physically based materials with the cell's story colour (textures are kept).
    private static func tint(_ root: Entity, _ color: UIColor) {
        MaterialTools.visitModels(root) { model in
            model.materials = model.materials.map { material -> any RealityKit.Material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                pbr.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color, texture: pbr.baseColor.texture)
                return pbr
            }
        }
    }
}
