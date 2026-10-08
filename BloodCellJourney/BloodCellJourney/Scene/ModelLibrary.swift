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

    /// The developing cell (shell) and its nucleus. The nucleus is its own item so it can be pulled out.
    func developingCell() -> (cell: StageItem, nucleus: StageItem) {
        let cell = StageItem(name: "DevelopingCell")
        let shell = clone(.shell)
        let fit = StageItem.fit(shell, size: Layout.Size.developingCell, orientation: .keep)
        cell.install(shell, scale: fit.scale, rotation: fit.rotation)

        let nucleus = StageItem(name: "Nucleus")
        nucleus.install(clone(.nucleus), scale: fit.scale, rotation: fit.rotation)
        cell.container.addChild(nucleus.container)
        nucleus.container.position = SIMD3<Float>(0, 0, 0)
        return (cell, nucleus)
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
