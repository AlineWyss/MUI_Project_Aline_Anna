//
//  SqueezeAnimation.swift
//  BloodCellJourney
//
//  Timing of the squeeze animation from claudeAniamtion.blend (Resources/SqueezePath.json, written by
//  Tools/export_squeeze.py): where the cell is in every frame and how far the blend shapes are applied.
//  The models themselves (capillary and cell with their blend shapes and materials) are in Reality
//  Composer Pro, scene "SqueezeScene".
//
//  Coordinates: metres of the Blender scene, app axes (+x right, +y up, +z towards the person), origin at
//  the spot of the capillary wall where the cell enters – the same space as the content of the entity
//  "Squeeze" in Reality Composer Pro.
//

import Foundation

struct SqueezeAnimation {
    private struct File: Decodable {
        let firstFrame: Int
        let lastFrame: Int
        let cellShapeFirstFrame: Int
        let cellBlendShapes: [String]
        let capillaryBlendShape: String
        let cellPositions: [[Float]]
        let bulgeWeights: [Float]
    }

    let firstFrame: Int
    let lastFrame: Int
    /// Blend shapes of the cell, stacked: number i adds the change from frame (cellShapeFirstFrame + i)
    /// to frame (cellShapeFirstFrame + i + 1).
    let cellBlendShapes: [String]
    let cellShapeFirstFrame: Int
    let capillaryBlendShape: String
    /// Cell position for every frame from `firstFrame` to `lastFrame`.
    let cellPositions: [SIMD3<Float>]
    /// How far the capillary bulges (0…1) for every frame from `firstFrame` to `lastFrame`.
    let bulgeWeights: [Float]

    enum LoadError: LocalizedError {
        case missingFile
        case damaged(String)

        var errorDescription: String? {
            switch self {
            case .missingFile: return "SqueezePath.json is missing in the app bundle."
            case .damaged(let detail): return "SqueezePath.json is damaged (\(detail))."
            }
        }
    }

    @MainActor private static var cached: SqueezeAnimation?

    /// Loads the animation timing on first use and keeps it.
    @MainActor static func shared() throws -> SqueezeAnimation {
        if let cached { return cached }
        let animation = try load()
        cached = animation
        return animation
    }

    static func load(from bundle: Bundle = .main) throws -> SqueezeAnimation {
        guard let url = bundle.url(forResource: "SqueezePath", withExtension: "json") else {
            throw LoadError.missingFile
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        let frameCount = file.lastFrame - file.firstFrame + 1
        guard frameCount > 1,
              file.cellPositions.count == frameCount,
              file.bulgeWeights.count == frameCount,
              file.cellPositions.allSatisfy({ $0.count == 3 }) else {
            throw LoadError.damaged("frame count")
        }
        return SqueezeAnimation(firstFrame: file.firstFrame,
                                lastFrame: file.lastFrame,
                                cellBlendShapes: file.cellBlendShapes,
                                cellShapeFirstFrame: file.cellShapeFirstFrame,
                                capillaryBlendShape: file.capillaryBlendShape,
                                cellPositions: file.cellPositions.map { SIMD3<Float>($0[0], $0[1], $0[2]) },
                                bulgeWeights: file.bulgeWeights)
    }

    /// Weights of the cell's blend shapes at a (fractional) frame: 1 for every frame already passed,
    /// the fraction for the current one, 0 after it.
    func cellWeights(at frame: Float) -> [Float] {
        let progress = frame - Float(cellShapeFirstFrame)
        return cellBlendShapes.indices.map { index in min(max(progress - Float(index), 0), 1) }
    }

    /// Bulge of the capillary wall at a (fractional) frame.
    func bulge(at frame: Float) -> Float {
        let position = min(max(frame - Float(firstFrame), 0), Float(bulgeWeights.count - 1))
        let from = Int(position.rounded(.down))
        let to = min(from + 1, bulgeWeights.count - 1)
        let t = position - Float(from)
        return bulgeWeights[from] + (bulgeWeights[to] - bulgeWeights[from]) * t
    }
}
