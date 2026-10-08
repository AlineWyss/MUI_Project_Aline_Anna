//
//  MaterialTools.swift
//  BloodCellJourney
//
//  Helpers to recolour models and to build simple glowing materials.
//

import Foundation
import RealityKit
import UIKit

enum MaterialTools {
    /// Calls `body` for every entity below (and including) `root` that has a model.
    static func visitModels(_ root: Entity, _ body: (inout ModelComponent) -> Void) {
        if var model = root.components[ModelComponent.self] {
            body(&model)
            root.components.set(model)
        }
        for child in root.children {
            visitModels(child, body)
        }
    }

    /// Replaces the base colour of all materials below `root` (keeps roughness, metallic and opacity).
    static func setBaseColor(_ root: Entity, _ color: UIColor) {
        visitModels(root) { model in
            model.materials = model.materials.map { material -> any RealityKit.Material in
                if var pbr = material as? PhysicallyBasedMaterial {
                    // Keep an existing colour texture; the tint multiplies it.
                    pbr.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color, texture: pbr.baseColor.texture)
                    return pbr
                }
                var pbr = PhysicallyBasedMaterial()
                pbr.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color, texture: nil)
                pbr.roughness = 0.45
                return pbr
            }
        }
    }

    /// Sets the opacity of all physically based materials below `root`.
    static func setOpacity(_ root: Entity, _ opacity: Float) {
        visitModels(root) { model in
            model.materials = model.materials.map { material -> any RealityKit.Material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                if opacity >= 0.999 {
                    pbr.blending = .opaque
                } else {
                    pbr.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: opacity))
                }
                return pbr
            }
        }
    }

    /// Turns a model into a see-through "ghost" (used for the alignment check).
    static func makeGhost(_ root: Entity) {
        var ghost = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
        ghost.blending = .transparent(opacity: .init(floatLiteral: 0.25))
        visitModels(root) { model in
            model.materials = model.materials.map { _ -> any RealityKit.Material in ghost }
        }
    }

    /// Bright, unlit, optionally see-through material for vessels, zones and markers.
    static func glow(_ color: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if opacity < 0.999 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// Opaque lit material (the small red blood cells of the blood stream).
    static func solid(_ color: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color, texture: nil)
        material.roughness = 0.4
        return material
    }

    /// Translucent lit material (hemoglobin filling the young cell).
    static func translucent(_ color: UIColor, opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color, texture: nil)
        material.roughness = 0.35
        material.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: opacity))
        return material
    }
}

extension UIColor {
    convenience init(rgba: SIMD4<Float>) {
        self.init(red: CGFloat(rgba.x), green: CGFloat(rgba.y), blue: CGFloat(rgba.z), alpha: CGFloat(rgba.w))
    }

    var rgba: SIMD4<Float> {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }
}
