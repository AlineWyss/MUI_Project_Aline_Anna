//
//  Components.swift
//  BloodCellJourney
//
//  Small RealityKit components and systems that animate the scene every frame.
//

import Foundation
import RealityKit
import SwiftUI
import UIKit

// MARK: - Marker components (no behaviour, used to find entities)

/// Marks a stage item the person can grab and drag.
struct DraggableComponent: Component {}

/// Marks an entity that reacts to a tap (the bloodstream on the physical model).
struct TapTargetComponent: Component {}

// MARK: - Motion

/// Drives the "motion" entity of a stage item: wiggle, rocking, hovering, bounce, shake and squeeze.
/// All effects are combined in one place so they never fight over the same transform.
struct MotionComponent: Component {
    var time: Float = 0
    /// Nervous jitter in metres (the nucleus that has no room).
    var wiggle: Float = 0
    /// Gentle rocking angle in radians (idle animation).
    var rockAngle: Float = 0
    var rockSpeed: Float = 0.8
    /// Gentle up/down floating in metres.
    var hover: Float = 0
    /// 0…1: scales rocking and hovering, so they fade in and out instead of jumping.
    var idleFade: Float = 1
    /// Where idleFade is heading (stopIdleMotion sets 0, calmIdle sets 1).
    var idleFadeTarget: Float = 1
    /// Start time of a bounce (heart beat), negative = inactive.
    var bounceStart: Float = -1
    var bounceHeight: Float = 0.035
    /// Start time of a shake (blocked), negative = inactive.
    var shakeStart: Float = -1
    /// 0 = normal shape, 1 = fully squeezed (stretched along x, flattened along y).
    var squeeze: Float = 0
}

struct MotionSystem: System {
    static let query = EntityQuery(where: .has(MotionComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var motion = entity.components[MotionComponent.self] else { continue }
            motion.time += dt
            let t = motion.time
            // Rocking and hovering ease in slowly (1.5 s) and settle quicker (0.5 s) instead of jumping.
            if motion.idleFade < motion.idleFadeTarget {
                motion.idleFade = min(motion.idleFade + dt / 1.5, motion.idleFadeTarget)
            } else if motion.idleFade > motion.idleFadeTarget {
                motion.idleFade = max(motion.idleFade - dt / 0.5, motion.idleFadeTarget)
            }
            let idle = motion.idleFade * motion.idleFade * (3 - 2 * motion.idleFade)   // soft start and end

            var offset = SIMD3<Float>(0, 0, 0)
            var rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

            if motion.wiggle > 0 {
                offset.x += sin(t * 23) * motion.wiggle
                offset.y += sin(t * 19 + 1.3) * motion.wiggle * 0.8
                offset.z += sin(t * 17 + 0.4) * motion.wiggle * 0.5
                rotation = simd_quatf(angle: sin(t * 11) * 0.12, axis: SIMD3<Float>(0, 0, 1)) * rotation
            }
            if motion.rockAngle > 0 {
                let rock = motion.rockAngle * idle
                let yaw = simd_quatf(angle: sin(t * motion.rockSpeed) * rock, axis: SIMD3<Float>(0, 1, 0))
                let pitch = simd_quatf(angle: sin(t * motion.rockSpeed * 0.7) * rock * 0.35, axis: SIMD3<Float>(1, 0, 0))
                rotation = yaw * pitch * rotation
            }
            if motion.hover > 0 {
                offset.y += sin(t * 1.6) * motion.hover * idle
            }
            if motion.bounceStart >= 0 {
                let progress = (t - motion.bounceStart) / 0.5
                if progress >= 1 {
                    motion.bounceStart = -1
                } else {
                    offset.y += sin(progress * .pi) * motion.bounceHeight
                }
            }
            if motion.shakeStart >= 0 {
                let progress = (t - motion.shakeStart) / 0.45
                if progress >= 1 {
                    motion.shakeStart = -1
                } else {
                    offset.x += sin(progress * 40) * 0.012 * (1 - progress)
                }
            }

            let s = motion.squeeze
            entity.position = offset
            entity.orientation = rotation
            entity.scale = SIMD3<Float>(1 + 0.45 * s, 1 - 0.5 * s, 1 - 0.15 * s)
            entity.components.set(motion)
        }
    }
}

// MARK: - Fade

/// Fades an entity (and its children) to a target opacity.
struct FadeComponent: Component {
    var target: Float
    /// Opacity change per second.
    var speed: Float
    /// Disable the entity once it is fully transparent.
    var disableWhenHidden: Bool = true
}

struct FadeSystem: System {
    static let query = EntityQuery(where: .has(FadeComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        let entities = Array(context.entities(matching: Self.query, updatingSystemWhen: .rendering))
        for entity in entities {
            guard let fade = entity.components[FadeComponent.self] else { continue }
            let current = entity.components[OpacityComponent.self]?.opacity ?? 1
            let step = fade.speed * dt
            let next: Float
            if current < fade.target {
                next = min(current + step, fade.target)
            } else {
                next = max(current - step, fade.target)
            }
            entity.components.set(OpacityComponent(opacity: next))
            if abs(next - fade.target) < 0.0001 {
                entity.components.remove(FadeComponent.self)
                if fade.target >= 0.999 {
                    // Fully visible again: drop the opacity so the models render as normal solid objects.
                    entity.components.remove(OpacityComponent.self)
                } else if fade.target <= 0.001 && fade.disableWhenHidden {
                    entity.isEnabled = false
                }
            }
        }
    }
}

// MARK: - Colour tween

/// Smoothly changes the base colour of every model below the entity.
struct ColorTweenComponent: Component {
    var from: SIMD4<Float>
    var to: SIMD4<Float>
    var duration: Float
    var elapsed: Float = 0
}

struct ColorTweenSystem: System {
    static let query = EntityQuery(where: .has(ColorTweenComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        let entities = Array(context.entities(matching: Self.query, updatingSystemWhen: .rendering))
        for entity in entities {
            guard var tween = entity.components[ColorTweenComponent.self] else { continue }
            tween.elapsed += dt
            let progress = min(tween.elapsed / max(tween.duration, 0.001), 1)
            let eased = progress * progress * (3 - 2 * progress)
            let color = tween.from + (tween.to - tween.from) * eased
            MaterialTools.setBaseColor(entity, UIColor(rgba: color))
            if progress >= 1 {
                entity.components.remove(ColorTweenComponent.self)
            } else {
                entity.components.set(tween)
            }
        }
    }
}

// MARK: - Beat

/// Makes an organ outline swell briefly (the heart on every beat).
struct BeatComponent: Component {
    var time: Float = 0
    var beatStart: Float = -10
    var amount: Float = 0.15
}

struct BeatSystem: System {
    static let query = EntityQuery(where: .has(BeatComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var beat = entity.components[BeatComponent.self] else { continue }
            beat.time += dt
            let progress = (beat.time - beat.beatStart) / 0.35
            let swell: Float = (progress >= 0 && progress < 1) ? sin(progress * .pi) * beat.amount : 0
            entity.scale = SIMD3<Float>(repeating: 1 + swell)
            entity.components.set(beat)
        }
    }
}

// MARK: - Follow

/// Keeps an entity (a label or button) next to another entity every frame.
struct FollowComponent: Component {
    /// Which point of a SwiftUI attachment sits at `target + offset`.
    enum Anchor {
        case center
        /// The bottom edge – the view grows upwards (labels above a model).
        case bottom
        /// The top edge – the view grows downwards (the Start button below a model).
        case top
    }

    weak var target: Entity?
    var offset: SIMD3<Float>
    var anchor: Anchor = .center
}

struct FollowSystem: System {
    static let query = EntityQuery(where: .has(FollowComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let follow = entity.components[FollowComponent.self],
                  follow.target != nil,
                  let parent = entity.parent else { continue }
            entity.position = Self.position(of: entity, following: follow, in: parent)
        }
    }

    /// Position (in `parent` space) that puts the anchor point of `entity` at `target + offset`.
    static func position(of entity: Entity, following follow: FollowComponent, in parent: Entity) -> SIMD3<Float> {
        guard let target = follow.target else { return entity.position }
        var position = target.position(relativeTo: parent) + follow.offset
        // The size of a SwiftUI view in metres; it changes when the view grows (e.g. facts opened).
        // Before SwiftUI has laid the view out, the bounds can be empty (infinite) – then use the centre.
        if follow.anchor != .center,
           let bounds = entity.components[ViewAttachmentComponent.self]?.bounds,
           bounds.min.y.isFinite, bounds.max.y.isFinite, bounds.max.y >= bounds.min.y {
            switch follow.anchor {
            case .bottom: position.y -= bounds.min.y
            case .top: position.y -= bounds.max.y
            case .center: break
            }
        }
        return position
    }
}

// MARK: - Journey marker

/// Moves an entity along a path: "our" red blood cell (with a light trail) and the running
/// lights around the organ outlines.
struct MarkerComponent: Component {
    var path: SampledPath
    var progress: Float = 0
    var target: Float = 0
    /// Progress (0...1) per second.
    var speed: Float = 0.25
    var loops: Bool = false
    /// Children that form a fading trail behind the marker while it moves.
    var trail: [Entity] = []
    /// Distance between trail pieces in metres.
    var trailSpacing: Float = 0.012
}

struct MarkerSystem: System {
    static let query = EntityQuery(where: .has(MarkerComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var marker = entity.components[MarkerComponent.self] else { continue }
            var moving = marker.loops
            if marker.loops {
                marker.progress += marker.speed * dt
                if marker.progress > 1 { marker.progress -= 1 }
            } else if marker.progress < marker.target {
                marker.progress = min(marker.progress + marker.speed * dt, marker.target)
                moving = true
            } else if marker.progress > marker.target {
                marker.progress = max(marker.progress - marker.speed * dt, marker.target)
                moving = true
            }
            let point = marker.path.point(at: marker.progress)
            entity.position = point

            // Trail pieces are children of the marker, so they are placed relative to it.
            let length = marker.path.length
            for (index, piece) in marker.trail.enumerated() {
                var trailPoint = point
                if moving && length > 0 {
                    var distance = marker.progress * length - Float(index + 1) * marker.trailSpacing
                    if marker.loops && distance < 0 { distance += length }
                    trailPoint = marker.path.point(at: max(distance, 0) / length)
                }
                piece.position = trailPoint - point
                piece.isEnabled = moving        // no trail while the marker stands still
            }
            entity.components.set(marker)
        }
    }
}

// MARK: - Pulse

/// Lets highlight zones and the marker halo breathe.
struct PulseComponent: Component {
    var baseScale: SIMD3<Float>
    var amount: Float = 0.08
    var speed: Float = 3
    var time: Float = 0
}

struct PulseSystem: System {
    static let query = EntityQuery(where: .has(PulseComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var pulse = entity.components[PulseComponent.self] else { continue }
            pulse.time += dt
            entity.scale = pulse.baseScale * (1 + pulse.amount * sin(pulse.time * pulse.speed))
            entity.components.set(pulse)
        }
    }
}

// MARK: - Slow spin

/// Turns a model slowly and endlessly around a slightly tilted axis, so it never looks static.
/// Put it on the model itself (not on `motion`, which MotionSystem turns).
struct SlowSpinComponent: Component {
    var current: simd_quatf
    /// Degrees per second (10 ≈ one full turn in 36 seconds).
    var speed: Float = 10
    /// How far the turning axis leans away from vertical, in degrees.
    var tilt: Float = 20
    var time: Float = 0
}

struct SlowSpinSystem: System {
    static let query = EntityQuery(where: .has(SlowSpinComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var spin = entity.components[SlowSpinComponent.self] else { continue }
            spin.time += dt
            // The axis leans a little and slowly circles around, so the turn feels organic.
            let lean = simd_quatf(angle: spin.tilt * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
            let circle = simd_quatf(angle: spin.time * 0.15, axis: SIMD3<Float>(0, 1, 0))
            let axis = (circle * lean).act(SIMD3<Float>(0, 1, 0))
            // Turn a small step every frame, so the movement stays smooth however long it runs.
            let step = simd_quatf(angle: spin.speed * .pi / 180 * dt, axis: axis)
            spin.current = simd_normalize(step * spin.current)
            entity.orientation = spin.current
            entity.components.set(spin)
        }
    }
}
// MARK: - Registration

enum JourneySystems {
    /// Call once at app launch.
    static func registerAll() {
        DraggableComponent.registerComponent()
        TapTargetComponent.registerComponent()
        MotionComponent.registerComponent()
        FadeComponent.registerComponent()
        ColorTweenComponent.registerComponent()
        BloodStreamComponent.registerComponent()
        BeatComponent.registerComponent()
        MarkerComponent.registerComponent()
        PulseComponent.registerComponent()
        FollowComponent.registerComponent()
        ShellPlaybackComponent.registerComponent()
        GrowComponent.registerComponent()
        DisintegrateComponent.registerComponent()
        SlowSpinComponent.registerComponent()

        MotionSystem.registerSystem()
        FadeSystem.registerSystem()
        ColorTweenSystem.registerSystem()
        BloodStreamSystem.registerSystem()
        BeatSystem.registerSystem()
        MarkerSystem.registerSystem()
        PulseSystem.registerSystem()
        FollowSystem.registerSystem()
        ShellPlaybackSystem.registerSystem()
        GrowSystem.registerSystem()
        DisintegrateSystem.registerSystem()
        SlowSpinSystem.registerSystem()
    }
}
