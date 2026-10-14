//
//  ModelLibrary.swift
//  BloodCellJourney
//
//  Loads your 3D models from the Reality Composer Pro package and builds ready-to-use stage items.
//  Scene: Packages/RealityKitContent/.../RealityKitContent.rkassets/BloodCellModels.usda
//

import Foundation
import RealityKit
import RealityKitContent
import simd

/// The developing shell's baked development and the shell with its endless gentle wobble that takes over.
struct ShellDevelopment {
    /// A copy of the shell that plays the baked development (ShellBake.swift).
    let growing: Entity
    /// Seconds the development takes.
    let duration: Double
    /// The normal shell, hidden until the development is done, and its wobble.
    let shell: Entity
    let loopAnimated: Entity?
    let loopAnimation: AnimationResource?
}

@MainActor
final class ModelLibrary {
    /// Names of the entities inside BloodCellModels.usda.
    enum Model: String, CaseIterable {
        case redBloodCell = "RedBloodCell"
        case shell = "DevelopingShell"
        case nucleus = "DevelopingNucleus"
        case hemoglobin = "Hemoglobin"
        case oxygen = "Oxygen"
        case carbonDioxide = "CarbonDioxide"
        case bodyCellOuter = "BodyCellOuter"
        case bodyCellInner = "BodyCellInner"
        case capillary = "Capillary"
    }

    enum LoadError: LocalizedError {
        case missingModel(String)
        var errorDescription: String? {
            switch self {
            case .missingModel(let name): return "The model “\(name)” is missing in BloodCellModels.usda."
            }
        }
    }

    private var prototypes: [Model: Entity] = [:]
    private(set) var isLoaded = false

    func load() async throws {
        let scene = try await Entity(named: "BloodCellModels", in: realityKitContentBundle)
        for model in Model.allCases {
            guard let entity = scene.findEntity(named: model.rawValue) else {
                throw LoadError.missingModel(model.rawValue)
            }
            if let opacity = Config.opacityOverrides[model] {
                MaterialTools.setOpacity(entity, opacity)
            }
            prototypes[model] = entity
        }

        _ = ShellBake.shared
        isLoaded = true
    }

    /// The scan of the anatomy model (scene VirtualAnatomy.usda), shown when the physical model is not used.
    /// Its coordinates are the same as in AnatomyMap.swift: origin at the centre of the base, +y up, faces +z.
    func virtualAnatomy() async throws -> Entity {
        let scene = try await Entity(named: "VirtualAnatomy", in: realityKitContentBundle)
        guard let model = scene.findEntity(named: "AnatomyModel") else {
            throw LoadError.missingModel("AnatomyModel")
        }
        model.removeFromParent()
        return model
    }
    
    /// The scanned heart (PumpHeart.usdz in RealityKitContent.rkassets).
    func pumpHeart() async throws -> Entity {
        try await Entity(named: "PumpHeart", in: realityKitContentBundle)
    }

    private func clone(_ model: Model) -> Entity {
        guard let prototype = prototypes[model] else { return Entity() }
        let copy = prototype.clone(recursive: true)
        copy.isEnabled = true
        return copy
    }

    // MARK: - Factories

    func redBloodCell() -> StageItem {
        let item = StageItem(name: "RedBloodCell")
        let model = clone(.redBloodCell)
        let fit = StageItem.fit(model, size: Layout.Size.redBloodCell, orientation: .thinAxisTowardViewer)
        item.install(model, scale: fit.scale, rotation: fit.rotation)
        return item
    }

    func developingCell() -> (cell: StageItem, nucleus: StageItem, development: ShellDevelopment?) {
        let cell = StageItem(name: "DevelopingCell")
        let shell = clone(.shell)
        let fit = StageItem.fit(shell, size: Layout.Size.developingCell, orientation: .keep)
        cell.install(shell, scale: fit.scale, rotation: fit.rotation)

        // A pivot carries the slow turn, so the developing copy and the shell that takes over
        // afterwards always face the same way.
        let pivot = Entity()
        pivot.name = "ShellPivot"
        shell.parent?.addChild(pivot)
        pivot.transform = shell.transform
        shell.transform = Transform()
        pivot.addChild(shell)
        pivot.components.set(SlowSpinComponent(current: pivot.orientation,
                                               speed: Config.shellSpinSpeed,
                                               tilt: Config.shellSpinTilt))

        // The shell's endless gentle wobble from Blender (shape keys Key_1 / Key_2).
        let loopAnimated = Self.firstAnimated(in: shell)
        let loopAnimation = loopAnimated?.availableAnimations.first

        var development: ShellDevelopment?
        if let bake = ShellBake.shared {
            // A copy of the shell plays the development from Blender (shape keys + soft-body wobble);
            // the shell itself (hidden until then) takes over when it is done.
            let growing = shell.clone(recursive: true)
            growing.isEnabled = true
            pivot.addChild(growing)
            growing.transform = shell.transform
            let start = Float(Timing.shellStartFrame)
            let fastUntil = Float(Timing.shellPopFrame)
            let fastSpeed = Float(Timing.shellEarlySpeed)
            if ShellBakePlayer.attach(bake, to: growing, startFrame: start, fastUntilFrame: fastUntil,
                                      fastSpeed: fastSpeed, growBoost: Float(Timing.shellGrowWobbleBoost)) {
                shell.isEnabled = false
                let duration = bake.duration(startFrame: start, fastUntilFrame: fastUntil, fastSpeed: fastSpeed)
                development = ShellDevelopment(growing: growing, duration: Double(duration), shell: shell,
                                               loopAnimated: loopAnimated, loopAnimation: loopAnimation)
            } else {
                growing.removeFromParent()
            }
        }
        if development == nil, let loopAnimated, let loopAnimation {
            loopAnimated.playAnimation(loopAnimation.repeat())
        }

        let nucleus = StageItem(name: "Nucleus")
        nucleus.install(clone(.nucleus), scale: fit.scale, rotation: fit.rotation)
        cell.container.addChild(nucleus.container)
        nucleus.container.position = SIMD3<Float>(0, 0, 0)
        return (cell, nucleus, development)
    }

    /// The first entity below `entity` that shows a mesh.
    private static func firstModel(in entity: Entity) -> Entity? {
        if entity.components.has(ModelComponent.self) { return entity }
        for child in entity.children {
            if let found = firstModel(in: child) { return found }
        }
        return nil
    }
    /// The entity below `entity` that carries an animation from the USDZ.
    private static func firstAnimated(in entity: Entity) -> Entity? {
        if !entity.availableAnimations.isEmpty { return entity }
        for child in entity.children {
            if let found = firstAnimated(in: child) { return found }
        }
        return nil
    }

    func hemoglobin() -> StageItem {
        let item = StageItem(name: "Hemoglobin")
        let model = clone(.hemoglobin)
        let fit = StageItem.fit(model, size: Layout.Size.hemoglobin, orientation: .keep)
        item.install(model, scale: fit.scale, rotation: fit.rotation)
        return item
    }

    func oxygen() -> StageItem {
        let item = StageItem(name: "Oxygen")
        let model = clone(.oxygen)
        let fit = StageItem.fit(model, size: Layout.Size.oxygen, orientation: .longAxisHorizontal)
        item.install(model, scale: fit.scale, rotation: fit.rotation)
        return item
    }

    func carbonDioxide() -> StageItem {
        let item = StageItem(name: "CarbonDioxide")
        let model = clone(.carbonDioxide)
        let fit = StageItem.fit(model, size: Layout.Size.carbonDioxide, orientation: .longAxisHorizontal)
        item.install(model, scale: fit.scale, rotation: fit.rotation)
        return item
    }

    /// The body cell that receives oxygen (outer membrane + inner part share one scale).
    func bodyCell() -> StageItem {
        let item = StageItem(name: "BodyCell")
        let outer = clone(.bodyCellOuter)
        let fit = StageItem.fit(outer, size: Layout.Size.bodyCell, orientation: .keep)
        item.install(outer, scale: fit.scale, rotation: fit.rotation)
        item.install(clone(.bodyCellInner), scale: fit.scale, rotation: fit.rotation)
        return item
    }
    
    /// A plain copy of the red blood cell model (for the marker on the anatomy model). Nothing is loaded again.
    func redBloodCellModel() -> Entity {
        clone(.redBloodCell)
    }

    /// A capillary lying left-to-right, `length` metres long. Its centre line is measured from the mesh.
    func capillary(length: Float) -> StageItem {
        let item = StageItem(name: "Capillary")
        let model = clone(.capillary)
        let fit = StageItem.fit(model, size: length, orientation: .longAxisHorizontal)
        item.install(model, scale: fit.scale, rotation: fit.rotation)
        item.centerline = MeshSampling.centerline(of: item.body, in: item.container)
        if item.centerline.count < 2 {
            item.centerline = [SIMD3<Float>(-length / 2, 0, 0), SIMD3<Float>(length / 2, 0, 0)]
        }
        return item
    }
}
