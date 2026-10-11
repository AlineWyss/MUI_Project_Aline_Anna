//
//  PumpHeart.swift
//  BloodCellJourney
//
//  Created by wyss aline on 11.10.2026.

//  Das 3D-Herz, das man im Takt pumpen muss.
//
//  Ablauf:
//  1. Wenn es heisst "Pumpe das Herz" (showHeartCounter), kommt das Herz aus der
//     Herzstelle der Statue hervor und fliegt nach vorne in die Bühne (focusRoot).
//  2. Es schlägt leicht von selbst im Ruhepuls (Config.restingHeartRate, 72/min).
//     Ein Ring zieht sich vor jedem Schlag zusammen: Wenn der Ring das Herz
//     berührt, ist der richtige Moment zum Drücken.
//  3. Tippt die Person auf das Herz, zieht es sich sichtbar zusammen.
//     • Im Takt (± Toleranz): Ring leuchtet grün, der Schlag zählt (heartTapped()).
//     • Zu früh / zu spät: Ring blinkt orange, der Schlag zählt nicht.
//  4. Wenn der bestehende Ablauf das Herzpumpen beendet (hideHeartCounter),
//     fliegt das Herz zurück in die Statue und verschwindet.
//
//  3D-Modell: Liegt eine Datei "Heart.usdz" in RealityKitContent.rkassets
//  (aus Blender exportiert), wird sie automatisch verwendet. Sonst wird eine
//  einfache rote Herzform als Ersatz gebaut. Ihr könnt also sofort testen.
//

import Foundation
import QuartzCore
import RealityKit
import RealityKitContent
import UIKit

// MARK: - Einstellungen und Texte

enum PumpHeartConfig {
    /// Grösste Kante des Herzens in der Bühne (Meter)
    static let size: Float = 0.14
    /// Wo das Herz in der Bühne schwebt (Koordinaten von focusRoot: +x rechts, +y oben, +z zum Nutzer)
    static let stagePosition = SIMD3<Float>(0, 0.02, 0)
    /// Wie genau man im Takt sein muss (Sekunden vor oder nach dem Schlag)
    static let tolerance: Double = 0.28
    /// Dauer des Hervorkommens / Zurückfliegens (Sekunden)
    static let flyDuration: TimeInterval = 0.9
    /// Name der Modell-Datei in RealityKitContent (ohne .usdz)
    static let modelName = "Heart"
}

/// Rückmeldungen unter dem Herz. Hier anpassen oder übersetzen.
enum PumpText {
    static let onBeat = "In rhythm! ♥"
    static let early = "Too early – wait until the ring touches the heart."
    static let late = "Too late – press when the ring touches the heart."
}

// MARK: - Das Herz

@MainActor
final class PumpHeart {

    enum TapResult {
        case onBeat, early, late
    }

    /// Wird bewegt (hervorkommen, zurückfliegen). Das Aufgaben-Label folgt diesem Entity.
    let root = Entity()
    /// Wird skaliert (Eigenschlag und Zusammenziehen beim Drücken).
    private let beatNode = Entity()
    /// Der Takt-Ring hinter dem Herz.
    private let ring: ModelEntity

    private let period: Double            // Sekunden pro Schlag
    private var startTime: Double = 0
    private var squeezeStart: Double = -10
    private var flashUntil: Double = -10
    private var flashColor: UIColor = .systemGreen
    private var showingFlash = false
    private var lastCountedBeat = Int.min
    private var loop: Task<Void, Never>?

    /// Abstand von der Herzmitte bis unter den Ring (für das Label darunter).
    var labelDistance: Float { PumpHeartConfig.size * 0.75 }

    init(beatsPerMinute: Float) {
        period = 60.0 / Double(max(beatsPerMinute, 30))

        // Ring: flache Scheibe, zum Nutzer gedreht, halbtransparent
        ring = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: PumpHeartConfig.size * 0.62),
                           materials: [Self.ringMaterial(.white)])
        ring.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        ring.position = SIMD3<Float>(0, 0, -0.04)

        root.name = "PumpHeart"
        root.addChild(ring)
        root.addChild(beatNode)
    }

    // MARK: Laden

    /// Lädt das Herz-Modell (oder baut den Ersatz) und macht es antippbar.
    func load() async {
        let model: Entity
        if let loaded = try? await Entity(named: PumpHeartConfig.modelName, in: realityKitContentBundle) {
            model = loaded
        } else {
            print("ℹ️ Kein Heart.usdz gefunden – es wird eine Ersatzform verwendet.")
            model = Self.makePlaceholder()
        }
        beatNode.addChild(model)

        // Auf Zielgrösse bringen und mittig ausrichten
        let bounds = model.visualBounds(relativeTo: beatNode)
        let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        if maxExtent > 0 {
            model.scale *= SIMD3<Float>(repeating: PumpHeartConfig.size / maxExtent)
        }
        let centered = model.visualBounds(relativeTo: beatNode)
        model.position -= centered.center

        // Antippbar machen: Kollisionsform + Eingabeziel + Aufleuchten beim Hinschauen
        root.components.set(CollisionComponent(shapes: [.generateSphere(radius: PumpHeartConfig.size * 0.6)]))
        root.components.set(InputTargetComponent())
        root.components.set(HoverEffectComponent())
    }

    /// Einfache Herzform aus zwei Kugeln und einem gedrehten Würfel.
    private static func makePlaceholder() -> Entity {
        let material = SimpleMaterial(color: UIColor(red: 0.78, green: 0.07, blue: 0.12, alpha: 1),
                                      roughness: 0.35, isMetallic: false)
        let heart = Entity()
        let radius: Float = 0.3
        for x: Float in [-0.21, 0.21] {
            let lobe = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
            lobe.position = SIMD3<Float>(x, 0.12, 0)
            heart.addChild(lobe)
        }
        let tip = ModelEntity(mesh: .generateBox(size: 0.6, cornerRadius: 0.08), materials: [material])
        tip.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1))
        tip.position = SIMD3<Float>(0, -0.12, 0)
        heart.addChild(tip)
        return heart
    }

    // MARK: Hervorkommen und Zurückfliegen

    /// Kommt klein aus `start` hervor und fliegt gross an `target` (beides in Koordinaten des Eltern-Entities).
    func flyIn(from start: SIMD3<Float>, to target: SIMD3<Float>) {
        root.position = start
        root.scale = SIMD3<Float>(repeating: 0.15)
        var transform = root.transform
        transform.translation = target
        transform.scale = SIMD3<Float>(repeating: 1)
        root.move(to: transform, relativeTo: root.parent,
                  duration: PumpHeartConfig.flyDuration, timingFunction: .easeOut)
    }

    /// Startet Eigenschlag und Takt-Ring.
    func start() {
        startTime = CACurrentMediaTime()
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(16))   // ca. 60 Mal pro Sekunde
            }
        }
    }

    /// Stoppt alles. Mit Ziel fliegt das Herz dorthin zurück und wird kleiner, danach wird es entfernt.
    func flyOut(to target: SIMD3<Float>?) {
        loop?.cancel()
        loop = nil
        root.components.remove(InputTargetComponent.self)
        root.components.remove(HoverEffectComponent.self)
        guard let target, root.parent != nil else {
            root.removeFromParent()
            return
        }
        var transform = root.transform
        transform.translation = target
        transform.scale = SIMD3<Float>(repeating: 0.1)
        root.move(to: transform, relativeTo: root.parent,
                  duration: PumpHeartConfig.flyDuration, timingFunction: .easeIn)
        let entity = root
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(PumpHeartConfig.flyDuration + 0.1))
            entity.removeFromParent()
        }
    }

    // MARK: Takt

    /// Wird ca. 60 Mal pro Sekunde aufgerufen: Herz schlagen lassen, Ring bewegen, Farbe setzen.
    private func tick() {
        let t = CACurrentMediaTime() - startTime
        // phase: 0 genau beim Schlag, läuft bis kurz vor 1 bis zum nächsten Schlag
        let phase = (t.truncatingRemainder(dividingBy: period)) / period

        // Eigenschlag: kleines Aufpumpen direkt nach jedem Schlag
        var scale = 1 + 0.05 * Float(exp(-phase * 12))

        // Zusammenziehen nach einem Tippen (0.3 s)
        let sinceSqueeze = t - squeezeStart
        if sinceSqueeze >= 0 && sinceSqueeze < 0.3 {
            let k = Float(sin(sinceSqueeze / 0.3 * .pi))
            scale *= 1 - 0.18 * k
        }
        beatNode.scale = SIMD3<Float>(repeating: scale)

        // Ring: gross direkt nach dem Schlag, schrumpft bis zum nächsten Schlag auf Herzgrösse
        let ringScale = 1 + 0.8 * Float(1 - phase)
        ring.scale = SIMD3<Float>(ringScale, 1, ringScale)

        // Farbe: kurz grün/orange nach einem Tippen, sonst weiss
        let flashing = t < flashUntil
        if flashing != showingFlash {
            showingFlash = flashing
            ring.model?.materials = [Self.ringMaterial(flashing ? flashColor : .white)]
        }
    }

    /// Wertet ein Tippen aus: im Takt, zu früh oder zu spät.
    func registerTap() -> TapResult {
        let t = CACurrentMediaTime() - startTime
        squeezeStart = t

        // Nächster Schlag und Abstand dazu
        let beatIndex = Int((t / period).rounded())
        let difference = t - Double(beatIndex) * period

        let result: TapResult
        if abs(difference) <= PumpHeartConfig.tolerance && beatIndex != lastCountedBeat {
            lastCountedBeat = beatIndex          // pro Schlag nur einmal zählen
            result = .onBeat
            flashColor = .systemGreen
        } else {
            result = difference < 0 || beatIndex == lastCountedBeat ? .early : .late
            flashColor = .systemOrange
        }
        flashUntil = t + 0.3
        showingFlash = false                     // Farbe im nächsten tick neu setzen
        return result
    }

    private static func ringMaterial(_ color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        return material
    }
}

// MARK: - Anbindung an den JourneyController

extension JourneyController {

    /// Position des Herzens der Statue in Koordinaten der Bühne (focusRoot).
    private var statueHeartOnStage: SIMD3<Float> {
        let world = anatomyRoot.convert(position: AnatomyMap.p(.heart), to: nil)
        return focusRoot.convert(position: world, from: nil)
    }

    /// Lässt das 3D-Herz aus der Statue hervorkommen (aufgerufen in showHeartCounter).
    func startPumpHeart() {
        guard pumpHeart == nil else { return }   // nicht doppelt
        let heart = PumpHeart(beatsPerMinute: Config.restingHeartRate)
        pumpHeart = heart
        focusRoot.addChild(heart.root)
        heart.root.position = statueHeartOnStage
        heart.root.scale = SIMD3<Float>(repeating: 0.01)   // unsichtbar klein, bis das Modell geladen ist

        Task { @MainActor in
            await heart.load()
            guard self.pumpHeart === heart else { return }   // inzwischen schon beendet?
            heart.flyIn(from: self.statueHeartOnStage, to: PumpHeartConfig.stagePosition)
            heart.start()
            self.updateTaskHint()   // Aufgabe unter das Herz
        }
    }

    /// Lässt das 3D-Herz zurück in die Statue fliegen (aufgerufen in hideHeartCounter).
    func stopPumpHeart(animated: Bool = true) {
        guard let heart = pumpHeart else { return }
        pumpHeart = nil
        pumpFeedback = nil
        // Das Aufgaben-Label soll dem verschwindenden Herz nicht folgen
        hintSlot?.entity?.components.remove(FollowComponent.self)
        heart.flyOut(to: animated ? statueHeartOnStage : nil)
        updateTaskHint()
    }

    /// Das 3D-Herz wurde angetippt (aufgerufen in tapped(_:)).
    func pumpHeartTapped() {
        guard let heart = pumpHeart else { return }
        switch heart.registerTap() {
        case .onBeat:
            showPumpFeedback(PumpText.onBeat)
            heartTapped()          // bestehende Logik: zählt den Schlag, bewegt das Blut weiter
        case .early:
            showPumpFeedback(PumpText.early)
        case .late:
            showPumpFeedback(PumpText.late)
        }
    }

    /// Zeigt eine Rückmeldung kurz statt der Aufgabe unter dem Herz.
    private func showPumpFeedback(_ text: String) {
        pumpFeedback = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            if self.pumpFeedback == text {
                self.pumpFeedback = nil
            }
        }
    }
}

