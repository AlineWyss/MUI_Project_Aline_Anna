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
import RealityKitContent
import simd

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

        stream.root.components.set(
            BloodStreamComponent(stream: stream)
        )

        if Config.showVesselTubes {
            buildVesselTubes()
        }

        buildZones()
        buildMarker()
        buildTapTarget()

        // MARK: - Solid models

        let solid = ModelSortGroupComponent(
            group: sortGroup,
            order: Self.solidOrder
        )

        root.forEachModelEntity {
            $0.components.set(solid)
        }

        // MARK: - Glowing elements

        let glow = ModelSortGroupComponent(
            group: sortGroup,
            order: Self.glowOrder
        )

        for entity in glowEntities {
            entity.forEachModelEntity {
                $0.components.set(glow)
            }
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

    /* private func buildMarker() {
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
    } */


private func buildMarker() {

    // MARK: - Glowing halo behind the 3D blood cell

    let halo = ModelEntity(
        mesh: .generateSphere(radius: 0.024),
        materials: [
            MaterialTools.glow(
                Palette.markerHalo,
                opacity: 0.45
            )
        ]
    )

    halo.name = "MarkerHalo"

    halo.components.set(
        PulseComponent(
            baseScale: SIMD3<Float>(repeating: 1),
            amount: 0.25,
            speed: 5
        )
    )

    marker.addChild(halo)
    glowEntities.append(halo)
    

    // MARK: - Fading trail behind the blood cell

    let pieces = 10

    for index in 0..<pieces {

        let fraction = Float(index) / Float(pieces)

        let piece = ModelEntity(
            mesh: .generateSphere(
                radius: 0.008 * (1 - fraction * 0.7)
            ),
            materials: [
                MaterialTools.glow(
                    Palette.markerHalo,
                    opacity: 0.55 * (1 - fraction)
                )
            ]
        )

        marker.addChild(piece)
        markerTrail.append(piece)
        glowEntities.append(piece)
    }


    // MARK: - Existing marker movement

    setMarker(
        path: SampledPath([AnatomyMap.p(.rMarrow)]),
        progress: 0,
        target: 0,
        speed: 0.3,
        loops: false
    )

    marker.isEnabled = false
    root.addChild(marker)


    // MARK: - Load the Reality Composer Pro 3D model

    Task { [weak self] in

        guard let self else { return }

        do {
            let library = try await Entity(
                named: "BloodCellModels",
                in: realityKitContentBundle
            )

            guard let redCell = library.findEntity(
                named: ModelLibrary.Model.redBloodCell.rawValue
            ) else {
                print("RedBloodCell not found in BloodCellModels")
                return
            }

            // Container for adjusting the model.
            let visual = Entity()
            visual.name = "RedBloodCellVisual"
            visual.addChild(redCell)


            // MARK: - Adjust blood cell size

            let bounds = visual.visualBounds(
                recursive: true,
                relativeTo: visual
            )

            let maxDimension = max(
                bounds.extents.x,
                max(bounds.extents.y, bounds.extents.z)
            )

            if maxDimension > 0 {

                // Change this to adjust the size.
                let desiredDiameter: Float = 0.020

                let scaleFactor = desiredDiameter / maxDimension

                visual.scale = SIMD3<Float>(
                    repeating: scaleFactor
                )

                // Center the model on the marker.
                visual.position = -bounds.center * scaleFactor
            }


            // MARK: - Render model in front of halo and trail

            let solid = ModelSortGroupComponent(
                group: sortGroup,
                order: Self.solidOrder
            )

            visual.forEachModelEntity {
                $0.components.set(solid)
            }


            // MARK: - Attach model to moving marker

            marker.addChild(visual)

        } catch {
            print("Failed to load RedBloodCell: \(error)")
        }
    }
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
    /*func loop(_ route: AnatomyMap.Route, lapDuration: Double) {
        marker.isEnabled = true
        setMarker(path: path(for: route), progress: 0, target: 1, speed: Float(1 / max(lapDuration, 0.5)), loops: true)
    } */

    
    func loop(_ route: AnatomyMap.Route, lapDuration: Double) {

        marker.isEnabled = true

        let loopPath: SampledPath

        switch route {

        case .fullCircuit:

            // MARK: - Full-body circulation

            let circuits = CirculationBuilder.circuits()
            let branchCount = AnatomyMap.systemicBranches.count

            // Each branch has two circuits:
            // one for the right lung, one for the left.
            guard circuits.count == branchCount * 2 else {
                print("Blood circulation circuits missing")
                return
            }

            var fullBodyPoints: [SIMD3<Float>] = []

            // Visit EVERY systemic branch:
            // head, arms, organs, intestines, legs.
            for branchIndex in 0..<branchCount {

                // Alternate between right and left lungs.
                let lungIndex = branchIndex % 2

                let circuitIndex = branchIndex * 2 + lungIndex

                let points = circuits[circuitIndex].path.points

                guard points.count >= 2 else {
                    continue
                }

                if fullBodyPoints.isEmpty {

                    fullBodyPoints.append(contentsOf: points)

                } else {

                    // Each circuit ends at the left heart.
                    // The next circuit starts at the same point.
                    // Avoid adding the shared point twice.
                    fullBodyPoints.append(
                        contentsOf: points.dropFirst()
                    )
                }
            }

            guard fullBodyPoints.count >= 2 else {
                print("Full-body circulation path is empty")
                return
            }

            loopPath = SampledPath(fullBodyPoints)

        default:

            // Keep all other explanatory routes unchanged.
            loopPath = path(for: route)
        }

        // MARK: - Animate continuously

        setMarker(
            path: loopPath,
            progress: 0,
            target: 1,
            speed: Float(1 / max(lapDuration, 0.5)),
            loops: true
        )
    }

    func loopFinalBodyCycle(lapDuration: Double = 120) {
        typealias Point = SIMD3<Float>
        typealias Landmark = AnatomyMap.Landmark

        // Local branches: do not modify AnatomyMap.systemicBranches.
        var branches: [[Landmark]] = []

        for branch in AnatomyMap.systemicBranches {
            if branch.last == .spleen && branch.contains(.stomach) {
                // Stomach and spleen are separate arterial destinations.
                branches.append(branch.filter { $0 != .spleen })
                branches.append(branch.filter { $0 != .stomach })
            } else {
                branches.append(branch)
            }
        }

        var points: [Point] = []

        // Smooth each vessel separately; remove duplicate joining points.
        func append(_ controls: [Point], smooth: Bool = true) {
            let segment = smooth && controls.count > 1
                ? Curves.catmullRom(controls, samplesPerSegment: 5)
                : controls

            for point in segment {
                if let last = points.last,
                   simd_distance(last, point) < 0.0001 {
                    continue
                }

                points.append(point)
            }
        }

        let liverIn = AnatomyMap.p(.liver)
        let liverOut = liverIn + AnatomyMap.veinOffset

        // Schematic guides, NOT measured portal-vein / vena-cava positions.
        let portalGuide = (AnatomyMap.p(.celiac) + liverIn) * 0.5
            + AnatomyMap.veinOffset * 0.5

        let cavaGuide = AnatomyMap.p(.aorta1) + AnatomyMap.veinOffset

        for (index, branch) in branches.enumerated() {
            guard let destination = branch.last else { continue }

            // 1. Left heart -> systemic artery -> selected tissue.
            let artery = Curves.catmullRom(
                AnatomyMap.arterialPoints(branch),
                samplesPerSegment: 5
            )

            guard artery.count >= 2 else { continue }

            append(artery, smooth: false)

            // 2. Schematic tissue microcirculation: artery -> venous side.
            let tissueIn = AnatomyMap.p(destination)
            let tissueOut = tissueIn + AnatomyMap.veinOffset

            let incoming = tissueIn - artery[artery.count - 2]
            let direction = simd_length(incoming) > 0.0001
                ? simd_normalize(incoming)
                : Point(0, -1, 0)

            let turn = tissueIn + direction * 0.008
                + AnatomyMap.veinOffset * 0.5

            append([tissueIn, turn, tissueOut], smooth: false)

            // 3. Return to the right heart through the appropriate route.
            switch destination {
            case .stomach, .spleen, .gut, .gutL, .gutR:
                // These organs drain through the portal system to the liver.
                var portal = [tissueOut]

                if destination == .gutL || destination == .gutR {
                    portal.append(
                        AnatomyMap.p(.gut) + AnatomyMap.veinOffset
                    )
                }

                portal.append(contentsOf: [portalGuide, liverIn])
                append(portal)

                // Second microvascular bed: liver sinusoids.
                let sinusoidTurn = liverIn + AnatomyMap.veinOffset * 0.5
                    + Point(0, -0.008, 0)

                append(
                    [liverIn, sinusoidTurn, liverOut],
                    smooth: false
                )

                // Hepatic veins -> inferior vena cava -> right heart.
                append([liverOut, cavaGuide, AnatomyMap.rightHeart])

            case .liver:
                // Direct liver trip: hepatic arterial supply -> sinusoids
                // -> hepatic veins -> inferior vena cava -> right heart.
                append([tissueOut, cavaGuide, AnatomyMap.rightHeart])

            default:
                // Head / limbs -> systemic veins -> right heart.
                append(AnatomyMap.venousPoints(branch))
            }

            // 4. Right heart -> one lung -> left heart.
            // Complete this BEFORE starting the next systemic destination.
            // Lung alternation is for teaching, not a biological rule.
            let lung: Landmark = index.isMultiple(of: 2)
                ? .rLung
                : .lLung

            let pulmonary = AnatomyMap.pulmonaryPoints(lung: lung)
            append(pulmonary.toLung)

            // Schematic lung capillaries connect artery to pulmonary vein.
            let lungIn = AnatomyMap.p(lung)
            let side: Float = lung == .rLung ? -1 : 1

            append([
                lungIn,
                lungIn + Point(0.012 * side, -0.006, 0.003),
                lungIn + Point(0.010 * side, -0.014, 0.004),
                lungIn + AnatomyMap.pulmonaryVeinOffset
            ], smooth: false)

            append(pulmonary.fromLung)
        }

        guard points.count >= 2 else { return }

        // Close the complete tour at the left heart.
        points[0] = AnatomyMap.leftHeart
        points[points.count - 1] = AnatomyMap.leftHeart

        // Do not smooth the assembled tour again.
        let tour = SampledPath(points)

        guard tour.length.isFinite, tour.length > 0,
              lapDuration.isFinite, lapDuration > 0 else {
            return
        }

        marker.position = tour.point(at: 0)

        setMarker(
            path: tour,
            progress: 0,
            target: 1,
            speed: Float(1 / max(lapDuration, 0.5)),
            loops: true
        )

        marker.isEnabled = true
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
