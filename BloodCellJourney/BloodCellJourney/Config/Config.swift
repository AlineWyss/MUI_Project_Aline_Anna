//
//  Config.swift
//  BloodCellJourney
//
//  Everything you are likely to tune lives here: names, sizes, positions, colours, timings.
//  Texts are in Content/StoryText.swift, positions on the physical model in Scene/AnatomyMap.swift.
//

import Foundation
import simd
import UIKit

enum Config {

    static let referenceObjectName = "AnatomyModel"

    /// Shows a translucent copy of the scanned model on top of the real one.
    /// Turn this on once to check that the bloodstream overlay sits correctly on the physical model.
    static let showAlignmentGhost = false
    
    /// TESTING ONLY: tapping the bloodstream at the start jumps straight to a later scene.
    /// nil = the normal story. .aging = from the trip to the spleen on. .recycling = the cell dissolves at once.
    /// Set back to nil before visitors use the app!
    static let debugJumpTo: JourneyStep? = nil

    /// Opacity of the virtual anatomy model (mode "without the model"). It is see-through so the
    /// bloodstream inside stays visible. 1 = solid.
    static let virtualModelOpacity: Float = 0.5

    // MARK: Blood stream on the anatomy model

    /// Number of red blood cells flowing through the anatomy model. Many tiny cells packed densely
    /// read as a flowing liquid. They are drawn with GPU instancing, so thousands are fine; lower it
    /// if the frame rate drops, raise it for a thicker stream.
    static let flowCellCount = 8000
    /// Diameter of the flowing cells (metres). A real red blood cell is 7–8 µm – far too small to see –
    /// so this is the smallest size that still reads as cells up close (about 2 mm).
    static let flowCellDiameter: Float = 0.0022
    /// How far a cell may drift sideways from the centre of the vessel (metres) – half the stream's width.
    static let flowCellSpread: Float = 0.0025
    /// Base speed of the blood in metres per second (arteries; capillaries and veins are slower).
    static let flowSpeed: Float = 0.09
    /// Heart beats per minute when the heart beats by itself (not while the person pumps it).
    static let restingHeartRate: Float = 72

    // MARK: Organ-Umrandungen
    // Dicke = Radius in Metern. Opacity: 0 = unsichtbar, 1 = voll sichtbar.
    // outline2Thickness muss grösser sein als outlineThickness, sonst sieht man outline2 nicht.

    // Linie 1 (outline): dünn und gut sichtbar
    static let outlineThickness: Float = 0.0015
    static let outlineOpacity: Float = 1.0
    // Linie 2 (outline2): dicker und durchsichtiger
    static let outline2Thickness: Float = 0.005
    static let outline2Opacity: Float = 0.15

    /// Also draw the circulation as thin tubes behind the flowing cells.
    static let showVesselTubes = true

    /// The squeezing cell takes the cell's colour in the story (young: dark red, old: brown) on top of
    /// its material from Reality Composer Pro (only for physically based materials; textures are kept).
    /// false = exactly the material set in Reality Composer Pro.
    static let squeezeCellUsesStoryColor = true
    /// The red blood cell's gentle idle movement whenever it is on stage
    /// (a little calmer than on the start screen, which uses 0.45 / 0.006).
    static let cellIdleRock: Float = 0.2     // radians, about ±9°
    static let cellIdleHover: Float = 0.004   // metres
    // MARK: The old red blood cell dissolves

    /// Seconds the old red blood cell takes to crumble away (front sweeps up, pieces drift up like ash).
    static let dissolveDuration: Float = 10.0
    /// Length of the flow (metres) in which the pieces float through the space before they travel into
    /// the anatomy model. Longer = they float around longer (it then flows faster within dissolveDuration).
    static let dissolveFloatLength: Float = 0.6
    /// How tidy the flow of the dissolving cell is: 0 = a tight, tidy stream … 1 = a loose cloud of pieces.
    static let dissolveStreamMess: Float = 0.5
    static let vesselTubeOpacity: Float = 0.25
    /// The developing cell's shell turns slowly and endlessly: degrees per second
    /// (10 ≈ one turn in 36 s). 0 = still.
    static let shellSpinSpeed: Float = 5
    /// How far its turning axis leans, in degrees, so the turn shows more of the surface.
    static let shellSpinTilt: Float = 20

    /// The O2 and CO2 models were exported with 10–14 % opacity and are hard to see in the headset.
    /// These values replace the exported opacity. Remove an entry to keep the original look.
    static let opacityOverrides: [ModelLibrary.Model: Float] = [
        .oxygen: 0.85,
        .carbonDioxide: 0.85,
        .shell: 0.30,
        .bodyCellOuter: 0.55
    ]
}

/// Positions in metres inside the focus area – the stage for the cells, labels, Start button, text panel
/// and end screen. +x = right, +y = up, +z = towards the person. The focus area is turned towards the
/// person at the start of every round.
enum Layout {
    /// Where the focus area (welcome screen, cells, labels) sits relative to the anatomy model – the physical
    /// one or the virtual copy – in metres, in the model's own directions:
    ///   x = to the right of the model, as seen by someone standing in front of it,
    ///   y = up from the model's base (the figure is 0.94 m tall, its heart is at 0.70 m),
    ///   z = out of the model's front, towards the person.
    /// Always the same spot next to the model: to its right and a little in front of it, facing the same way
    /// as the model's front. It does not depend on where the person looks or stands.
    static let focusOffsetFromModel = SIMD3<Float>(0.45, 0.60, 0.50)
    /// Only if the content faces sideways or backwards on the physical model: turns the model's "front"
    /// (degrees, e.g. 90 or -90). 0 = the scan's front is the human's front.
    static let physicalModelFrontTurn: Float = 0
    /// The focus area only moves with the physical model when it really moved (someone bumped it):
    /// by more than this distance (metres) …
    static let modelMoveTolerance: Float = 0.08
    /// … or turned by more than this angle (degrees). Smaller changes are tracking noise and are ignored.
    static let modelTurnTolerance: Float = 15

    /// While searching for the physical model the hint sits in front of the person (there is no model to
    /// place it next to yet): this far from the eyes …
    static let focusDistance: Float = 0.75
    /// … and this far below eye height. Without the physical model, the virtual copy is placed so the
    /// focus area ends up exactly here, and the copy at focusOffsetFromModel from it.
    static let focusDrop: Float = 0.22

    /// Assumed head position when head tracking is not available (e.g. Simulator).
    static let fallbackHeadPosition = SIMD3<Float>(0, 1.45, 0)

    static let mainSlot = SIMD3<Float>(-0.10, 0, 0)
    static let sideSlot = SIMD3<Float>(0.14, 0, 0)
    /// The text panel – always on the right.
    static let panelSlot = SIMD3<Float>(0.46, 0.03, -0.03)
    static let startPromptSlot = SIMD3<Float>(-0.06, 0.02, 0)
    /// The end screen with "Start again" – in the middle, where the cells were.
    static let finalPanelSlot = SIMD3<Float>(0, 0.04, 0)
    /// The "Tap the heart" counter sits this far to the side of the model's heart (towards the focus area).
    /// It is attached to the anatomy model, so it stays next to the heart.
    static let heartCounterSideOffset: Float = 0.12
    /// The scanned heart while it is pumped: 2 = twice its real size (~16 cm).
    static let heartModelScale: Float = 1.0
    /// How far the heart floats out of the model, towards the person.
    static let heartPopOutDistance: Float = 0.45
    /// Turn the scan around its vertical axis if its front doesn't face you (radians, e.g. .pi / 2).
    static let heartModelYaw: Float = 0
    /// Size of the red blood cell while it flies into / out of the anatomy model.
    static let cellScaleInModel: Float = 0.07
    /// Gap between the top of a model and the bottom edge of its name label.
    /// The label grows upwards from there when (i) opens the facts.
    static let labelGap: Float = 0.02
    /// Gap between the bottom of a model and the top edge of the start button.
    static let buttonGap: Float = 0.035
    /// Abstand zwischen der Unterkante eines Modells und dem Aufgaben-Label darunter.
    static let hintGap: Float = 0.03
    /// Feste Position der Aufgaben-Labels (TaskHint) auf der Bühne, in Metern.
          /// Gleiches Koordinatensystem wie mainSlot/sideSlot:
          ///   x = links (−) / rechts (+)
          ///   y = unten (−) / oben (+)  – 0 ist die Höhe, auf der die Zellen schweben
          ///   z = nach hinten (−) / zur Person hin (+)
        static let hintSlot = SIMD3<Float>(-0.1, -0.15, 0.02)
    static let squeezeStart = SIMD3<Float>(-0.2, 0, -0.05)
    /// A held object turns this many times as far as the wrist (2 = a small turn shows the back).
    static let grabRotationGain: Float = 2

    /// Longest side of each model in the focus area, in metres.
    enum Size {
        static let redBloodCell: Float = 0.15
        static let developingCell: Float = 0.17
        static let hemoglobin: Float = 0.075
        static let oxygen: Float = 0.055
        static let carbonDioxide: Float = 0.055
        static let bodyCell: Float = 0.20
    }
}

enum Timing {
    /// Seconds a released object takes to turn back to how it was.
    static let grabRotationReturn: Double = 0.4
    static let pop: TimeInterval = 0.45
    /// Seconds for the red blood cell to fly into or out of the anatomy model.
    static let flyToModel: TimeInterval = 1.1
    /// Speed of "our" red blood cell (the light on the model) on every journey, in metres per second.
    /// travelToLungs, travelToSpleen and lapDuration no longer change its speed.
    static let markerSpeed: Float = 0.25
    /// Second in the recording voice_pumpToOrgans where the voice has just said "bright red": the cell flies
    /// into the body from here. Open the file (e.g. in QuickTime) and read off the time.
    ///     /// Speed of "our" cell on its first trip, from the bone marrow to the lungs (metres per second).
    /// Lower = slower. All other trips use markerSpeed.
    ///     /// Speed of "our" cell on the final body loop and on to the spleen (metres per second).
    /// The loop plus the way to the spleen is about 6.9 m; it should take as long as the voice lines
    /// cycleRepeats + agingIntro together: speed = 6.9 / (both recordings in seconds).
    static let bodyLoopSpeed: Float = 0.28
    static let marrowToLungsSpeed: Float = 0.05
    static let brightRedCue: TimeInterval = 3.0
    /// Second in the recording voice_pickUpCO2 where the voice has just said "dark red".
    static let darkRedCue: TimeInterval = 10.5
    /// Seconds the developing cell takes to fly from the pelvis's bone marrow to the person. It grows on the way.
    static let developingCellFlight: TimeInterval = 3.0
    static let travelToLungs: Double = 4.5
    static let travelToSpleen: Double = 2.5
    /// Aging: the marker reaches the spleen (and the old cell flies out) this many seconds BEFORE the voice line
    /// agingIntro ends, so the next line (agingTry) follows without a silent gap. Bigger = earlier.
    static let agingEarlyArrival: Double = 1.5
    static let heartStep: Double = 0.7
    static let heartPopOut: Double = 0.8
    static let requiredHeartBeats = 5
    static let requiredAgingAttempts = 2
    /// Seconds the "a red blood cell is born" text stays before the capillary appears.
    static let afterBirth: Double = 3.0
    /// Seconds to read the explanation why the old cell gets stuck before it dissolves.
    static let readTooStiff: Double = 5.0
    /// The cell's development (Resources/ShellDevelopment.json, 24 frames per second): the shell grows
    /// from nothing to full size until the pop frame, the nucleus until its own frame (as in the .blend).
    static let shellAnimationFPS: Double = 24
    static let shellPopFrame: Double = 73
    static let nucleusGrowFrame: Double = 75
    /// The development plays this many times faster up to shellPopFrame, then at normal speed
    /// (1 = as in Blender; the growth takes the same time, so shell and nucleus stay in sync).
    static let shellEarlySpeed: Double = 0.5
    /// Speed of the development after full size (1 = as in Blender, 0.5 = slow motion, 2 = twice as fast).
    static let shellLateSpeed: Double = 1.5
    /// The development starts at this frame of the bake (frames before it are still).
    static let shellStartFrame: Double = 14
    /// Extra wobble while the cell grows: 1.5 = two and a half times as strong at the start, easing back
    /// to the original strength by the time it reaches full size. 0 = as in Blender.
    static let shellGrowWobbleBoost: Double = 1.5
    /// The nucleus jiggles this much (metres) while the developing shell wobbles …
    static let nucleusDevelopJiggle: Double = 0.0015
    /// … and calms down over the last seconds of the development, together with the shell
    /// (matches the 72-frame settle baked into ShellDevelopment.json).
    static let shellSettleSeconds: Double = 3.0
    /// Seconds the capillary takes to fade away before the old cell turns to the person and dissolves.
    static let recycleCapillaryFade: Double = 0.5
    /// Seconds for one lap of the marker while the cycle repeats.
    static let lapDuration: Double = 25.0  //6.0
    /// How far the old cell gets into the squeeze animation (a frame of claudeAniamtion.blend).
    /// 12 = Blender's shape key "Key 1" is complete (blend shapes Squeeze01–03); 9 = it can't bend at all;
    /// 21 = it would get through.
    static let agingStopFrame: Float = 12
    /// Seconds for the cell to relax into its normal shape after squeezing.
    static let squeezeRelax: Double = 0.8
    /// Seconds for the old cell to spring back after it got stuck.
    static let springBack: Double = 0.45
    /// Seconds a released object takes to turn back to how it was.
}

enum Palette {
    static let rbcOxygenated = UIColor(red: 0.63, green: 0.08, blue: 0.08, alpha: 1)    // average of RBC_withOxygen.png
    static let rbcDeoxygenated = UIColor(red: 0.43, green: 0.04, blue: 0.04, alpha: 1)  // average of RBC_withoutOxygen.png // dark burgundy
    static let rbcAged = UIColor(red: 0.62, green: 0.25, blue: 0.21, alpha: 1)          // dull brown-red
    static let hemoglobinFill = UIColor(red: 0.85, green: 0.10, blue: 0.12, alpha: 1)

    static let artery = UIColor(red: 1.00, green: 0.20, blue: 0.24, alpha: 1)
    static let vein = UIColor(red: 0.30, green: 0.47, blue: 1.00, alpha: 1)
    /// "Our" red blood cell on the anatomy model – yellow so it stands out from the red stream.
    static let marker = UIColor(red: 1.00, green: 0.2, blue: 0.20, alpha: 1)
    static let markerHalo = UIColor(red: 1, green: 0.10, blue: 0.15, alpha: 0.7)
    /// Schriftfarbe für Hinweise, z. B. die Pinch-Zeile im Startprompt (Hellblau, voll sichtbar).
    static let taskHint = UIColor(red: 0.25, green: 0.85, blue: 1, alpha: 1)

    static func zone(_ zone: AnatomyMap.Zone) -> UIColor {
        switch zone {
        case .boneMarrow: return UIColor(red: 10.00, green: 10.00, blue: 10.00, alpha: 1)
        case .lungs: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        case .heart: return UIColor(red: 1.00, green: 0.30, blue: 0.40, alpha: 1)
        case .organs: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        case .spleen: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        }
    }
}

