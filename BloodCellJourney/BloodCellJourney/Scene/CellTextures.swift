//
//  CellTextures.swift
//  BloodCellJourney
//
//  CellTextures.swift
//  BloodCellJourney
//
//  The two looks of the red blood cell: base-colour PNGs painted for RedBloodCell.usdz's UV layout
//  (Resources/RBC_withOxygen.png and Resources/RBC_withoutOxygen.png).
//

import RealityKit
import UIKit

enum CellLook {
    case withOxygen, withoutOxygen
}

@MainActor
enum CellTextures {
    private static var textures: [CellLook: TextureResource] = [:]

    /// Loads both PNGs from the app bundle. Called once from JourneyController.prepare().
    static func load() async {
        let files: [(CellLook, String)] = [(.withOxygen, "RBC_withOxygen"), (.withoutOxygen, "RBC_withoutOxygen")]
        for (look, name) in files {
            do {
                textures[look] = try await TextureResource(named: name)
            } catch {
                print("CellTextures: could not load \(name).png – \(error)")
            }
        }
    }

    /// Puts the look's PNG on every material below `root`, unchanged (white tint).
    static func apply(_ look: CellLook, to root: Entity) {
        guard let texture = textures[look] else { return }
        MaterialTools.visitModels(root) { model in
            model.materials = model.materials.map { material -> any RealityKit.Material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                pbr.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white, texture: .init(texture))
                return pbr
            }
        }
    }
}
