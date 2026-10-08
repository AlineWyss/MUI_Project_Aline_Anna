//
//  AnatomyOverlay.swift
//  BloodCellJourney
//
//  Everything drawn onto the anatomy model (physical or virtual):
//  • the blood stream – hundreds of small red blood cells following the real circulation,
//  • glowing outlines of the organ or body region where the story takes place,
//  • "our" red blood cell as a yellow marker with a light trail,
//  • tap targets: the whole body (to start) and the heart (to pump).
//  All children live in scan coordinates (see AnatomyMap.swift).
//

import Foundation
import RealityKit
import UIKit

@MainActor
final class AnatomyOverlay {
    let root = Entity()
    /// The flowing red blood cells (created on first use in `build()`, not when the controller is made).
    private(set) lazy var stream = BloodStream(cellCount: Config.flowCellCount)
    /// Invisible box around the figure – tapping it starts the experience.
    let tapTarget = Entity()
    /// Yellow dot = current position of "our" red blood cell.
    let marker = Entity()

    private var zoneEntities: [AnatomyMap.Zone: Entity] = [:]
    private(set) var activeZone: AnatomyMap.Zone?
    private var markerTrail: [Entity] = []

    /// Draw order (lower first): solid blood cells and marker core, then the glowing outlines and
    /// marker halo, then a see-through body (virtual model / ghost) – so nothing hides the cells.
    private let sortGroup = ModelSortGroup(depthPass: nil)
    private static let solidOrder: Int32 = 1
    private static let glowOrder: Int32 = 2
    private static let bodyOrder: Int32 = 3
    private var glowEntities: [Entity] = []

    init() {
        root.name = "AnatomyOverlay"
        tapTarget.name = "BloodstreamTapTarget"
        marker.name = "JourneyMarker"
    }

    // MARK: - Build

    func build() {
        root.addChild(stream.root)
        stream.root.components.set(BloodStreamComponent(stream: stream))
        if Config.showVesselTubes {
            buildVesselTubes()
        }
        buildZones()
        buildMarker()
        buildTapTarget()

        let solid = ModelSortGroupComponent(group: sortGroup, order: Self.solidOrder)
        root.forEachModelEntity { $0.components.set(solid) }
        let glow = ModelSortGroupComponent(group: sortGroup, order: Self.glowOrder)
        for entity in glowEntities {
            entity.forEachModelEntity { $0.components.set(glow) }
        }
    }

    /// Makes a see-through body render after the overlay (see `sortGroup`).
    func drawAfterOverlay(_ body: Entity) {
        let order = ModelSortGroupComponent(group: sortGroup, order: Self.bodyOrder)
        body.forEachModelEntity { $0.components.set(order) }
    }

    /// Optional thin tubes along the circulation (Config.showVesselTubes).
    private func buildVesselTubes() {
        let tubes = Entity()
        tubes.name = "VesselTubes"
        let material = MaterialTools.glow(Palette.artery, opacity: Config.vesselTubeOpacity)
        for (index, circuit) in CirculationBuilder.circuits().enumerated() where index % 2 == 0 {
            if let mesh = try? TubeMesh.generate(along: circuit.path.points, radius: 0.003) {
                tubes.addChild(ModelEntity(mesh: mesh, materials: [material]))
            }
        }
        // Part of the stream, so the tubes show and hide together with it.
        stream.root.addChild(tubes)
        glowEntities.append(tubes)
    }

    /// Glowing outlines of the organs, each with two lights running around it.
    private func buildZones() {
        let lightMaterial = MaterialTools.glow(UIColor.white)
        let lightMesh = MeshResource.generateSphere(radius: Config.outlineThickness * 2.4)
        for zone in AnatomyMap.Zone.allCases {
            let outlines = AnatomyMap.outlines(for: zone)
            let allPoints = outlines.flatMap { $0.points3D }
            guard !allPoints.isEmpty else { continue }
            let center = allPoints.reduce(SIMD3<Float>(0, 0, 0), +) / Float(allPoints.count)

            // The zone entity sits at the centre so it can swell around it (BeatComponent).
            let zoneEntity = Entity()
            zoneEntity.name = "Zone-\(zone.rawValue)"
            zoneEntity.position = center
            let color = Palette.zone(zone)
            let core = MaterialTools.glow(color, opacity: 0.95)
            let halo = MaterialTools.glow(color, opacity: 0.22)

            for outline in outlines {
                let loop = Curves.closedCatmullRom(outline.points3D.map { $0 - center }, samplesPerSegment: 6)
                if let mesh = try? TubeMesh.generate(along: loop, radius: Config.outlineThickness) {
                    zoneEntity.addChild(ModelEntity(mesh: mesh, materials: [core]))
                }
                if let mesh = try? TubeMesh.generate(along: loop, radius: Config.outlineThickness * 3.2) {
                    zoneEntity.addChild(ModelEntity(mesh: mesh, materials: [halo]))
                }
                let path = SampledPath(loop)
                for lightIndex in 0..<2 {
                    let light = ModelEntity(mesh: lightMesh, materials: [lightMaterial])
                    light.components.set(MarkerComponent(path: path, progress: Float(lightIndex) * 0.5,
                                                         target: 1, speed: 0.35, loops: true))
                    zoneEntity.addChild(light)
                }
            }
            zoneEntity.components.set(BeatComponent())
            zoneEntity.components.set(OpacityComponent(opacity: 0))
            zoneEntity.isEnabled = false
            root.addChild(zoneEntity)
            zoneEntities[zone] = zoneEntity
            glowEntities.append(zoneEntity)
        }
    }

    private func buildMarker() {
        let core = ModelEntity(mesh: .generateSphere(radius: 0.010), materials: [MaterialTools.glow(Palette.marker)])
        let halo = ModelEntity(mesh: .generateSphere(radius: 0.024),
                               materials: [MaterialTools.glow(Palette.markerHalo, opacity: 0.45)])
        halo.components.set(PulseComponent(baseScale: SIMD3<Float>(repeating: 1), amount: 0.25, speed: 5))
        marker.addChild(core)
        marker.addChild(halo)
        glowEntities.append(halo)

        // A fading light trail that shows where the cell has just been.
        let trail = Entity()
        trail.name = "MarkerTrail"
        let pieces = 10
        for index in 0..<pieces {
            let fraction = Float(index) / Float(pieces)
            let piece = ModelEntity(mesh: .generateSphere(radius: 0.008 * (1 - fraction * 0.7)),
                                    materials: [MaterialTools.glow(Palette.markerHalo, opacity: 0.55 * (1 - fraction))])
            marker.addChild(piece)
            markerTrail.append(piece)
            glowEntities.append(piece)
        }
        setMarker(path: SampledPath([AnatomyMap.p(.rMarrow)]), progress: 0, target: 0, speed: 0.3, loops: false)
        marker.isEnabled = false
        root.addChild(marker)
    }

    private func buildTapTarget() {
        // Box around the whole figure (scan bounds: 0.48 × 0.94 × 0.26 m).
        let box = ShapeResource.generateBox(size: SIMD3<Float>(0.5, 0.86, 0.3))
        tapTarget.components.set(CollisionComponent(shapes: [box]))
        tapTarget.components.set(InputTargetComponent())
        tapTarget.components.set(TapTargetComponent())
        tapTarget.position = SIMD3<Float>(0, 0.5, 0)
        tapTarget.isEnabled = false
        root.addChild(tapTarget)
    }

    // MARK: - Blood stream visibility

    /// The blood stream is only shown in the first scene (until it is tapped). It fades in and out.
    func setStreamVisible(_ visible: Bool) {
        let streamRoot = stream.root
        if visible {
            if !streamRoot.isEnabled {
                streamRoot.components.set(OpacityComponent(opacity: 0))
                streamRoot.isEnabled = true
            }
            streamRoot.components.set(FadeComponent(target: 1, speed: 1.2, disableWhenHidden: true))
        } else {
            streamRoot.components.set(FadeComponent(target: 0, speed: 1.2, disableWhenHidden: true))
        }
    }

    // MARK: - Organ outlines

    func setZone(_ zone: AnatomyMap.Zone?) {
        activeZone = zone
        for (key, entity) in zoneEntities {
            if key == zone {
                entity.isEnabled = true
                entity.components.set(FadeComponent(target: 1, speed: 2.5, disableWhenHidden: true))
            } else if entity.isEnabled {
                entity.components.set(FadeComponent(target: 0, speed: 2.5, disableWhenHidden: true))
            }
        }
    }

    func zoneEntity(_ zone: AnatomyMap.Zone) -> Entity? {
        zoneEntities[zone]
    }

    func zonePosition(_ zone: AnatomyMap.Zone) -> SIMD3<Float>? {
        zoneEntities[zone]?.position(relativeTo: nil)
    }

    // MARK: - The heart on the model

    /// Turns the heart outline into a button (gaze + pinch on the heart of the model).
    func setHeartTappable(_ tappable: Bool) {
        guard let heart = zoneEntities[.heart] else { return }
        if tappable {
            heart.components.set(CollisionComponent(shapes: [ShapeResource.generateSphere(radius: 0.04)]))
            heart.components.set(InputTargetComponent())
            heart.components.set(HoverEffectComponent())
            heart.components.set(TapTargetComponent())
        } else {
            heart.components.remove(TapTargetComponent.self)
            heart.components.remove(HoverEffectComponent.self)
            heart.components.remove(InputTargetComponent.self)
            heart.components.remove(CollisionComponent.self)
        }
    }

    func isHeart(_ entity: Entity) -> Bool {
        guard let heart = zoneEntities[.heart] else { return false }
        return entity.isInside(heart)
    }

    /// One heart beat: the heart outline swells and the blood surges.
    func beatHeart() {
        stream.beat()
        guard let heart = zoneEntities[.heart], var beat = heart.components[BeatComponent.self] else { return }
        beat.beatStart = beat.time
        heart.components.set(beat)
    }

    // MARK: - Marker

    private func setMarker(path: SampledPath, progress: Float, target: Float, speed: Float, loops: Bool) {
        marker.components.set(MarkerComponent(path: path, progress: progress, target: target, speed: speed,
                                              loops: loops, trail: markerTrail, trailSpacing: 0.012))
    }

    func showMarker(at landmark: AnatomyMap.Landmark) {
        marker.isEnabled = true
        setMarker(path: SampledPath([AnatomyMap.p(landmark)]), progress: 0, target: 0, speed: 0.3, loops: false)
    }

    func hideMarker() {
        marker.isEnabled = false
    }

    /// World position of the marker (where "our" cell is in the body).
    var markerWorldPosition: SIMD3<Float> {
        marker.position(relativeTo: nil)
    }

    private func path(for route: AnatomyMap.Route) -> SampledPath {
        SampledPath(Curves.catmullRom(AnatomyMap.points(for: route), samplesPerSegment: 8))
    }

    /// World position where a route starts.
    func startPosition(of route: AnatomyMap.Route) -> SIMD3<Float> {
        root.convert(position: path(for: route).point(at: 0), to: nil)
    }

    /// Moves the marker along a route and returns when it arrives.
    func travel(_ route: AnatomyMap.Route, duration: Double) async {
        marker.isEnabled = true
        setMarker(path: path(for: route), progress: 0, target: 1, speed: Float(1 / max(duration, 0.1)), loops: false)
        let deadline = Date().addingTimeInterval(duration + 1.5)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard let component = marker.components[MarkerComponent.self] else { break }
            if component.loops || component.progress >= component.target - 0.001 { break }
        }
    }

    /// Puts the marker at the start of a route that is then walked step by step (heart beats).
    func prepareSteps(along route: AnatomyMap.Route) {
        marker.isEnabled = true
        setMarker(path: path(for: route), progress: 0, target: 0, speed: 0.3, loops: false)
    }

    /// Moves the marker to `fraction` (0...1) of the prepared route.
    func advance(to fraction: Float, duration: Double) {
        guard var component = marker.components[MarkerComponent.self] else { return }
        let distance = abs(fraction - component.progress)
        component.target = min(max(fraction, 0), 1)
        component.speed = max(distance / Float(max(duration, 0.05)), 0.01)
        component.loops = false
        marker.components.set(component)
    }

    /// Lets the marker run round and round (the cycle repeats).
    func loop(_ route: AnatomyMap.Route, lapDuration: Double) {
        marker.isEnabled = true
        setMarker(path: path(for: route), progress: 0, target: 1, speed: Float(1 / max(lapDuration, 0.5)), loops: true)
    }

    // MARK: - Reset

    func reset() {
        setZone(nil)
        hideMarker()
        setHeartTappable(false)
        tapTarget.isEnabled = false
        stream.autoBeat = true
    }
}
