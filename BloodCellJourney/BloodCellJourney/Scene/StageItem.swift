//
//  StageItem.swift
//  BloodCellJourney
//
//  One interactive model in the focus area.
//
//  container  – positioned in the focus area, receives input, carries the name label
//   └ motion  – wiggle / bounce / rocking / squeeze (MotionSystem)
//      └ body – orientation + scale that make the model the right size
//         └ offset – centres the model
//            └ model (your USDZ)
//

import Foundation
import RealityKit
import UIKit

@MainActor
final class StageItem {
    enum Orientation {
        case keep
        /// Turns the thinnest side towards the person (a disc shows its face).
        case thinAxisTowardViewer
        /// Lays the longest side left-to-right.
        case longAxisHorizontal
    }

    let container = Entity()
    let motion = Entity()
    let body = Entity()

    /// Radius of a sphere around the model (container space).
    private(set) var radius: Float = 0.05
    /// Half the height of the model (container space), used to place labels.
    private(set) var halfHeight: Float = 0.05
    /// Current base colour (only tracked for items that change colour).
    var currentColor: SIMD4<Float>?
    /// Centre line for tube-shaped models (capillary), container space.
    var centerline: [SIMD3<Float>] = []

    init(name: String) {
        container.name = name
        motion.name = name + "-motion"
        body.name = name + "-body"
        container.addChild(motion)
        motion.addChild(body)
        motion.components.set(MotionComponent())
    }

    /// Computes scale and rotation so the model's longest side equals `size`.
    static func fit(_ model: Entity, size: Float, orientation: Orientation) -> (scale: Float, rotation: simd_quatf) {
        let extents = model.visualBounds(relativeTo: nil).extents
        let longest = max(extents.x, max(extents.y, extents.z))
        let scale = longest > 0 ? size / longest : 1
        return (scale, rotation(for: orientation, extents: extents))
    }

    static func rotation(for orientation: Orientation, extents e: SIMD3<Float>) -> simd_quatf {
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        switch orientation {
        case .keep:
            return identity
        case .thinAxisTowardViewer:
            if e.x <= e.y && e.x <= e.z { return simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0)) } // x → z
            if e.y <= e.x && e.y <= e.z { return simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)) }  // y → z
            return identity
        case .longAxisHorizontal:
            if e.y >= e.x && e.y >= e.z { return simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 0, 1)) } // y → x
            if e.z >= e.x && e.z >= e.y { return simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)) }  // z → x
            return identity
        }
    }

    /// Adds a model below `body`, centred on its own bounds.
    func install(_ model: Entity, scale: Float, rotation: simd_quatf) {
        let bounds = model.visualBounds(relativeTo: nil)
        let offset = Entity()
        offset.position = -bounds.center
        offset.addChild(model)
        body.addChild(offset)
        body.scale = SIMD3<Float>(repeating: scale)
        body.orientation = rotation
        measure()
    }

    private func measure() {
        let bounds = body.visualBounds(relativeTo: container)
        let extents = bounds.extents
        radius = max(extents.x, max(extents.y, extents.z)) / 2
        halfHeight = extents.y / 2
    }

    // MARK: - Motion helpers

    func updateMotion(_ change: (inout MotionComponent) -> Void) {
        var component = motion.components[MotionComponent.self] ?? MotionComponent()
        change(&component)
        motion.components.set(component)
    }

    func bounce() { updateMotion { $0.bounceStart = $0.time } }
    func shake() { updateMotion { $0.shakeStart = $0.time } }
    func setSqueeze(_ amount: Float) { updateMotion { $0.squeeze = amount } }

    func stopIdleMotion() {
        updateMotion {
            $0.rockAngle = 0
            $0.hover = 0
            $0.wiggle = 0
        }
    }
}
