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
import RealityKitContent
import UIKit
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
    /// The final body loop while it runs, and where it passes the left heart (metres along it).
    private var finalTour: SampledPath?
    private var finalTourHeartStops: [Float] = []

    /// Draw order (lower first): solid blood cells and marker core, then the glowing outlines and
    /// marker halo, then a see-through body (virtual model / ghost) – so nothing hides the cells.
    private let sortGroup = ModelSortGroup(depthPass: nil)
    private static let solidOrder: Int32 = 1
    /// Die dünne outline wird VOR outline2 gezeichnet. So liegt der durchsichtige
    /// outline2-Schlauch darüber, und die Linie scheint durch ihn hindurch.
    private static let outlineOrder: Int32 = 2
    private static let glowOrder: Int32 = 3
    /// Der rote Punkt (Blutkörperchen im Modell) wird NACH den leuchtenden Linien gezeichnet.
    private static let markerOrder: Int32 = 4
    private static let bodyOrder: Int32 = 5
    /// Wie weit der rote Punkt zur Person hin rückt (Meter), damit er vor den Linien liegt.
    private static let markerForward: Float = 0.03
    private var glowEntities: [Entity] = []
    /// Invisible shells around the vessel tubes. While the stream is visible they are the tap target, and
    /// only their rims glow when looked at (VesselHoverRim), so tubes and cells keep their colours.
    private var vesselOutlines: Entity?
    /// Alle Teile der dünnen Linie 1 (outline), damit sie zuletzt gezeichnet werden können.
    private var outlineEntities: [Entity] = []
    /// The scanned heart that comes out of the model's heart while it has to be pumped.
    private let heartModel = Entity()
    /// Inner pivot that contracts on every beat (BeatSystem sets its scale every frame).
    private let heartBeatPivot = Entity()

    init() {
        root.name = "AnatomyOverlay"
        tapTarget.name = "BloodstreamTapTarget"
        marker.name = "JourneyMarker"
        heartModel.name = "PumpHeart"
        heartModel.addChild(heartBeatPivot)
        heartModel.isEnabled = false
        root.addChild(heartModel)
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

        // MARK: - Dünne outline vor outline2 zeichnen, damit sie durchscheint
        let outlineFirst = ModelSortGroupComponent(group: sortGroup, order: Self.outlineOrder)
        for line in outlineEntities {
            line.components.set(outlineFirst)
        }
    }


    /// Makes a see-through body render after the overlay (see `sortGroup`).
    func drawAfterOverlay(_ body: Entity) {
        let order = ModelSortGroupComponent(group: sortGroup, order: Self.bodyOrder)
        body.forEachModelEntity { $0.components.set(order) }
    }

    /// Optional thin tubes along the circulation (Config.showVesselTubes). Around each tube sits a slightly
    /// wider, invisible shell: while the person looks at the stream, only its rim glows (VesselHoverRim
    /// material in Reality Composer Pro), so the tubes keep their red colour and just get an outline.
    private func buildVesselTubes() {
        let radius: Float = 0.003
        let tubes = Entity()
        tubes.name = "VesselTubes"
        let outlines = Entity()
        outlines.name = "VesselOutlines"
        let rich = MaterialTools.glow(Palette.rbcOxygenated, opacity: Config.vesselTubeOpacity)
        let poor = MaterialTools.glow(Palette.rbcDeoxygenated, opacity: Config.vesselTubeOpacity)
        let invisible = MaterialTools.glow(.white, opacity: 0)   // until the rim material has loaded
        var rimModels: [ModelEntity] = []

        func addTube(_ points: [SIMD3<Float>], oxygenRich: Bool) {
            guard points.count > 1 else { return }
            if let mesh = try? TubeMesh.generate(along: points, radius: radius) {
                tubes.addChild(ModelEntity(mesh: mesh, materials: [oxygenRich ? rich : poor]))
            }
            if let mesh = try? TubeMesh.generate(along: points, radius: radius * 1.2) {
                let rim = ModelEntity(mesh: mesh, materials: [invisible])
                outlines.addChild(rim)
                rimModels.append(rim)
            }
        }

        // The circuits come in pairs (right lung, left lung) that share the same body vessels.
        // Every second circuit draws each body vessel once – plus the right lung.
        for (index, circuit) in CirculationBuilder.circuits().enumerated() where index % 2 == 0 {
            for run in circuit.colorRuns() {
                addTube(run.points, oxygenRich: run.oxygenRich)
            }
        }
        // The left lung's own vessels (they were missing): pulmonary artery, capillary loop, pulmonary vein.
        let leftLung = AnatomyMap.pulmonaryPoints(lung: .lLung)
        let toLung = Curves.catmullRom(leftLung.toLung, samplesPerSegment: 5)
        let fromLung = Curves.catmullRom(leftLung.fromLung, samplesPerSegment: 5)
        if let lungPoint = toLung.last, let veinStart = fromLung.first {
            addTube(toLung, oxygenRich: false)
            // Same small loop as the flowing cells take (BloodStream.swift, left side).
            let loopA = lungPoint + SIMD3<Float>(0.012, -0.006, 0.003)
            let loopB = lungPoint + SIMD3<Float>(0.010, -0.014, 0.004)
            addTube([lungPoint, loopA, loopB, veinStart] + fromLung.dropFirst(), oxygenRich: true)
        }

        // Part of the stream, so tubes and rims show and hide together with it.
        stream.root.addChild(tubes)
        stream.root.addChild(outlines)
        glowEntities.append(tubes)
        glowEntities.append(outlines)
        vesselOutlines = outlines

        let rims = rimModels
        Task { @MainActor in
            do {
                let rimMaterial = try await ShaderGraphMaterial(named: "/Root/VesselHoverRim",
                                                               from: "HoverMaterials.usda",
                                                               in: realityKitContentBundle)
                for rim in rims { rim.model?.materials = [rimMaterial] }
            } catch {
                print("⚠️ VesselHoverRim material unavailable – the stream has no hover outline: \(error)")
            }
        }
    }

    private func buildZones() {
        for zone in AnatomyMap.Zone.allCases {
            let outlines = AnatomyMap.outlines(for: zone)
            let allPoints = outlines.flatMap { $0.points3D }
            guard !allPoints.isEmpty else { continue }
            let center = allPoints.reduce(SIMD3<Float>(0, 0, 0), +) / Float(allPoints.count)

            let zoneEntity = Entity()
            zoneEntity.name = "Zone-\(zone.rawValue)"
            zoneEntity.position = center
            let color = Palette.zone(zone)

            // ── Linie 1: outline (dünn, gut sichtbar) ──
            let outlineMaterial = MaterialTools.glow(color, opacity: Config.outlineOpacity)
            for outline in outlines {
                let loop = Curves.closedCatmullRom(outline.points3D.map { $0 - center }, samplesPerSegment: 6)
                if let mesh = try? TubeMesh.generate(along: loop, radius: Config.outlineThickness) {
                    let line = ModelEntity(mesh: mesh, materials: [outlineMaterial])
                    zoneEntity.addChild(line)
                    outlineEntities.append(line)   // merken für die Zeichen-Reihenfolge
                }
            }

            // ── Linie 2: outline2 (dicker, durchsichtiger) ──
            let outline2Material = MaterialTools.glow(color, opacity: Config.outline2Opacity)
            for outline2 in outlines {
                let loop2 = Curves.closedCatmullRom(outline2.points3D.map { $0 - center }, samplesPerSegment: 6)
                if let mesh = try? TubeMesh.generate(along: loop2, radius: Config.outline2Thickness) {
                    zoneEntity.addChild(ModelEntity(mesh: mesh, materials: [outline2Material]))
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

    // MARK: - Marker ("our" red blood cell on the anatomy model)

    /// The marker: a glowing disc behind the cell and a fading trail. The 3D red blood cell itself is
    /// added later with `setMarkerCell(_:)`, as soon as ModelLibrary has loaded it (see prepare()).
    private func buildMarker() {

        // MARK: Glowing disc BEHIND the blood cell
        // A flat round glow that always faces the person and sits 1.5 cm behind the cell's centre
        // (seen from the person), so it can never cover the cell.

        let haloPivot = Entity()
        haloPivot.name = "MarkerHaloPivot"
        haloPivot.components.set(BillboardComponent())          // +z always points at the person

        let halo = ModelEntity(
            mesh: .generatePlane(width: 0.048, height: 0.048, cornerRadius: 0.024),
            materials: [
                MaterialTools.glow(
                    Palette.markerHalo,
                    opacity: 0.45
                )
            ]
        )
        halo.name = "MarkerHalo"
        halo.position = SIMD3<Float>(0, 0, -0.015)
        halo.components.set(
            PulseComponent(
                baseScale: SIMD3<Float>(repeating: 1),
                amount: 0.25,
                speed: 5
            )
        )

        haloPivot.addChild(halo)
        marker.addChild(haloPivot)
        glowEntities.append(halo)

        // MARK: Fading trail behind the blood cell
        // Small spheres that start behind the cell (see trailSpacing in setMarker), so they don't cover it.

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

        // MARK: Start position (hidden until the story needs it)

        setMarker(
            path: SampledPath([AnatomyMap.p(.rMarrow)]),
            progress: 0,
            target: 0,
            speed: 0.3,
            loops: false
        )

        marker.isEnabled = false
        root.addChild(marker)
    }

    /// Puts the red blood cell model on the marker (a copy of the one ModelLibrary has already loaded,
    /// so nothing is loaded a second time). Called from JourneyController.prepare().
    func setMarkerCell(_ cell: Entity, diameter: Float = 0.020) {
        marker.findEntity(named: "MarkerCellPivot")?.removeFromParent()
        marker.findEntity(named: "RedBloodCellVisual")?.removeFromParent()

        let visual = Entity()
        visual.name = "RedBloodCellVisual"
        visual.addChild(cell)

        let bounds = visual.visualBounds(recursive: true, relativeTo: visual)
        let maxDimension = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        if maxDimension > 0 {
            let scale = diameter / maxDimension
            visual.scale = SIMD3<Float>(repeating: scale)
            visual.position = -bounds.center * scale      // centred on the marker
        }

        let pivot = Entity()
        pivot.name = "MarkerCellPivot"
        pivot.components.set(BillboardComponent())
        visual.position.z += Self.markerForward
        pivot.addChild(visual)

        // Wird nach den Linien gezeichnet (siehe markerOrder).
        let front = ModelSortGroupComponent(group: sortGroup, order: Self.markerOrder)
        visual.forEachModelEntity { $0.components.set(front) }
        marker.addChild(pivot)
    }
    /// Gives the marker's cell the same look as the cell in front of the person.
    func setMarkerLook(_ look: CellLook) {
        guard let visual = marker.findEntity(named: "RedBloodCellVisual") else { return }
        CellTextures.apply(look, to: visual)
    }
    /// Puts the heart scan into the overlay, enlarged and centred so it beats around its middle.
    func setHeartModel(_ model: Entity) {
        heartBeatPivot.children.removeAll()
        let visual = Entity()
        visual.addChild(model)
        let bounds = visual.visualBounds(recursive: true, relativeTo: visual)
        let scale = Layout.heartModelScale
        visual.scale = SIMD3<Float>(repeating: scale)
        visual.orientation = simd_quatf(angle: Layout.heartModelYaw, axis: SIMD3<Float>(0, 1, 0))
        visual.position = -visual.orientation.act(bounds.center * scale)
        let solid = ModelSortGroupComponent(group: sortGroup, order: Self.solidOrder)
        visual.forEachModelEntity { $0.components.set(solid) }
        heartBeatPivot.addChild(visual)
        heartBeatPivot.components.set(BeatComponent(amount: -0.18))   // negative = contracts, like a real beat
    }

    /// The heart comes out of the model's heart (real size) and floats to `target` (2× size).
    func showHeartModel(at target: SIMD3<Float>) {
        guard !heartBeatPivot.children.isEmpty else { return }
        heartModel.position = AnatomyMap.p(.heart)
        heartModel.scale = SIMD3<Float>(repeating: 1 / Layout.heartModelScale)
        heartModel.isEnabled = true
        let end = Transform(scale: .one, rotation: heartModel.orientation, translation: target)
        heartModel.move(to: end, relativeTo: root, duration: Timing.heartPopOut, timingFunction: .easeOut)
    }

    /// The heart goes back into the model and disappears.
    func hideHeartModel(animated: Bool = true) {
        guard heartModel.isEnabled else { return }
        guard animated else { heartModel.isEnabled = false; return }
        let back = Transform(scale: SIMD3<Float>(repeating: 1 / Layout.heartModelScale),
                             rotation: heartModel.orientation, translation: AnatomyMap.p(.heart))
        heartModel.move(to: back, relativeTo: root, duration: Timing.heartPopOut, timingFunction: .easeIn)
        Task { @MainActor [heartModel] in
            try? await Task.sleep(for: .seconds(Timing.heartPopOut))
            if simd_distance(heartModel.position, AnatomyMap.p(.heart)) < 0.01 { heartModel.isEnabled = false }
        }
    }

    private func buildTapTarget() {
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
            // Box around the whole figure (scan bounds: 0.48 × 0.94 × 0.26 m), same place as the old tap target.
            let box = ShapeResource.generateBox(size: SIMD3<Float>(0.5, 0.86, 0.3))
                .offsetBy(translation: SIMD3<Float>(0, 0.5, 0))
            // Gaze box and glow sit on the vessel tubes only (falls back to the whole stream without tubes).
            let target = vesselOutlines ?? streamRoot
            target.components.set(CollisionComponent(shapes: [box]))
            target.components.set(InputTargetComponent())
            target.components.set(TapTargetComponent())
            // With rims: only their edges light up (shader). Without tubes: the default effect on the whole stream.
            target.components.set(vesselOutlines != nil ? HoverEffectComponent(.shader(.default)) : HoverEffectComponent())
        } else {
            let target = vesselOutlines ?? streamRoot
            target.components.remove(HoverEffectComponent.self)
            target.components.remove(TapTargetComponent.self)
            target.components.remove(InputTargetComponent.self)
            target.components.remove(CollisionComponent.self)
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
        let heart = heartModel
        if tappable {
            heart.components.set(CollisionComponent(shapes: [ShapeResource.generateSphere(radius: 0.045*Layout.heartModelScale)]))
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
        entity.isInside(heartModel)
    }

    /// One heart beat: the heart outline swells and the blood surges.
    func beatHeart() {
        stream.beat()
        guard var beat = heartBeatPivot.components[BeatComponent.self] else { return }
        beat.beatStart = beat.time
        heartBeatPivot.components.set(beat)
    }

    // MARK: - Marker movement

    private func setMarker(path: SampledPath, progress: Float, target: Float, speed: Float, loops: Bool) {
        // trailSpacing 0.018: the first trail sphere starts behind the 2 cm cell instead of overlapping it.
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

    /// World position where the marker's next journey starts: where the marker is now (see
    /// pathFromMarker), so the red blood cell flies to the right spot and nothing jumps.
    func startPosition(of route: AnatomyMap.Route) -> SIMD3<Float> {
        root.convert(position: pathFromMarker(to: route).point(at: 0), to: nil)
    }

    /// Moves the marker along a route and returns when it arrives. It always sets off from where it is
    /// now (see pathFromMarker), so it never jumps, wherever it was.
    func travel(_ route: AnatomyMap.Route, duration: Double) async {
        marker.isEnabled = true
        let way = pathFromMarker(to: route)
        // The route's usual speed. Coming from the body loop it keeps at least the speed it had there,
        // so a longer way (first round to the heart) neither drags nor rushes.
        var metresPerSecond = path(for: route).length / Float(max(duration, 0.1))
        if let tour = finalTour, let current = marker.components[MarkerComponent.self], current.loops {
            metresPerSecond = max(metresPerSecond, current.speed * tour.length)
        }
        let seconds = max(Double(way.length / max(metresPerSecond, 0.001)), 0.1)
        finalTour = nil
        setMarker(path: way, progress: 0, target: 1, speed: Float(1 / seconds), loops: false)
        let deadline = Date().addingTimeInterval(seconds + 1.5)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard let component = marker.components[MarkerComponent.self] else { break }
            if component.loops || component.progress >= component.target - 0.001 { break }
        }
    }

    /// Puts the marker at the start of a route that is then walked step by step (heart beats).
    /// The route starts where the marker is now, so it doesn't jump.
    func prepareSteps(along route: AnatomyMap.Route) {
        marker.isEnabled = true
        let way = pathFromMarker(to: route)
        finalTour = nil
        setMarker(path: way, progress: 0, target: 0, speed: 0.3, loops: false)
    }

    /// The way from where the marker is now to the end of `route`, without a jump:
    /// - on the final body loop, when the route leaves from the left heart, the marker first follows its
    ///   current vessel round to the left heart and takes the route from there – the way blood goes;
    /// - anywhere else, a smooth curve joins the route from the marker's current position.
    private func pathFromMarker(to route: AnatomyMap.Route) -> SampledPath {
        let controls = AnatomyMap.points(for: route)
        let here = marker.position

        if let tour = finalTour, tour.length > 0,
           let current = marker.components[MarkerComponent.self], current.loops,
           let heart = controls.firstIndex(where: { simd_distance($0, AnatomyMap.leftHeart) < 0.0005 }) {
            let from = current.progress * tour.length
            let stop = finalTourHeartStops.first(where: { $0 >= from - 0.0001 })
                ?? (finalTourHeartStops.first.map { $0 + tour.length } ?? tour.length)
            var points = tourPoints(tour, from: from, to: stop)
            for point in Curves.catmullRom(Array(controls[heart...]), samplesPerSegment: 8) {
                if let last = points.last, simd_distance(last, point) < 0.0001 { continue }
                points.append(point)
            }
            return SampledPath(points)
        }

        let routePoints = Curves.catmullRom(controls, samplesPerSegment: 8)
        guard let first = routePoints.first, simd_distance(here, first) > 0.001 else {
            return SampledPath(routePoints)
        }
        return SampledPath(Curves.catmullRom([here] + controls, samplesPerSegment: 8))
    }

    /// Points of the final body loop between two distances (metres along it). `end` may run past the
    /// end of the loop and continue from its start – the loop is closed at the left heart.
    private func tourPoints(_ tour: SampledPath, from start: Float, to end: Float) -> [SIMD3<Float>] {
        var points = [tour.point(at: start / tour.length)]
        for (index, distance) in tour.cumulative.enumerated()
        where distance > start && distance <= min(end, tour.length) {
            points.append(tour.points[index])
        }
        if end > tour.length {
            for (index, distance) in tour.cumulative.enumerated()
            where distance > 0 && distance <= end - tour.length {
                points.append(tour.points[index])
            }
        }
        return points
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

        // Join the loop where the marker is now (the nearest point of the tour), so it doesn't jump.
        let here = marker.position
        var nearest = 0
        for index in tour.points.indices
        where simd_distance(tour.points[index], here) < simd_distance(tour.points[nearest], here) {
            nearest = index
        }

        setMarker(
            path: tour,
            progress: tour.cumulative[nearest] / tour.length,
            target: 1,
            speed: Float(1 / max(lapDuration, 0.5)),
            loops: true
        )

        marker.isEnabled = true
        // Remember the loop and where it passes the left heart, so the next journey can leave from it.
        finalTour = tour
        finalTourHeartStops = tour.points.indices
            .filter { simd_distance(tour.points[$0], AnatomyMap.leftHeart) < 0.0005 }
            .map { tour.cumulative[$0] }
    }

    // MARK: - Reset

    func reset() {
        setZone(nil)
        hideMarker()
        finalTour = nil
        setHeartTappable(false)
        tapTarget.isEnabled = false
        stream.autoBeat = true
    }
}
