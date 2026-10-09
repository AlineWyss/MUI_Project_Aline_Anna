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
    /// Thickness (radius) of the glowing organ outlines in metres.
    static let outlineThickness: Float = 0.0016
    /// Also draw the circulation as thin tubes behind the flowing cells.
    static let showVesselTubes = true

    /// The squeezing cell takes the cell's colour in the story (young: dark red, old: brown) on top of
    /// its material from Reality Composer Pro (only for physically based materials; textures are kept).
    /// false = exactly the material set in Reality Composer Pro.
    static let squeezeCellUsesStoryColor = true
    static let vesselTubeOpacity: Float = 0.25

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
    /// Where the focus area sits relative to the anatomy model (the physical one, or the virtual copy),
    /// in metres, in the model's own directions:
    ///   x = to the right of the model, as seen by someone standing in front of it,
    ///   y = up from the model's base (the figure is 0.94 m tall, its heart is at 0.70 m),
    ///   z = out of the model's front, towards the person.
    /// The model then sits slightly to the left in the view, the cells and text in the middle, a bit
    /// closer to the person than the model. The same spot every time – wherever the experience was started.
    static let focusOffsetFromModel = SIMD3<Float>(0.45, 0.60, 0.50)
    /// The focus area only moves with the physical model when it really moved (someone bumped it):
    /// by more than this distance (metres) …
    static let modelMoveTolerance: Float = 0.03
    /// … or turned by more than this angle (degrees). Smaller changes are tracking noise and are ignored.
    static let modelTurnTolerance: Float = 5

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
    /// Size of the red blood cell while it flies into / out of the anatomy model.
    static let cellScaleInModel: Float = 0.07
    /// Gap between the top of a model and the bottom edge of its name label.
    /// The label grows upwards from there when (i) opens the facts.
    static let labelGap: Float = 0.02
    /// Gap between the bottom of a model and the top edge of the start button.
    static let buttonGap: Float = 0.035


    static let squeezeStart = SIMD3<Float>(-0.2, 0, -0.05)

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
    static let pop: TimeInterval = 0.45
    /// Seconds for the red blood cell to fly into or out of the anatomy model.
    static let flyToModel: TimeInterval = 1.1
    static let travelToLungs: Double = 4.5
    static let travelToSpleen: Double = 3.5
    static let heartStep: Double = 0.7
    static let requiredHeartBeats = 5
    static let requiredAgingAttempts = 2
    /// Seconds the "a red blood cell is born" text stays before the capillary appears.
    static let afterBirth: Double = 3.0
    /// Seconds to read the explanation why the old cell gets stuck before it dissolves.
    static let readTooStiff: Double = 5.0
    /// Seconds for one lap of the marker while the cycle repeats.
    static let lapDuration: Double = 40.0  //6.0
    /// How far the old cell gets into the squeeze animation (a frame of claudeAniamtion.blend).
    /// 12 = Blender's shape key "Key 1" is complete (blend shapes Squeeze01–03); 9 = it can't bend at all;
    /// 21 = it would get through.
    static let agingStopFrame: Float = 12
    /// Seconds for the cell to relax into its normal shape after squeezing.
    static let squeezeRelax: Double = 0.8
    /// Seconds for the old cell to spring back after it got stuck.
    static let springBack: Double = 0.45
}

enum Palette {
    static let rbcOxygenated = UIColor(red: 0.96, green: 0.07, blue: 0.09, alpha: 1)    // scarlet
    static let rbcDeoxygenated = UIColor(red: 0.60, green: 0.03, blue: 0.09, alpha: 1)  // dark burgundy
    static let rbcAged = UIColor(red: 0.62, green: 0.25, blue: 0.21, alpha: 1)          // dull brown-red
    static let hemoglobinFill = UIColor(red: 0.85, green: 0.10, blue: 0.12, alpha: 1)

    static let artery = UIColor(red: 1.00, green: 0.20, blue: 0.24, alpha: 1)
    static let vein = UIColor(red: 0.30, green: 0.47, blue: 1.00, alpha: 1)
    /// "Our" red blood cell on the anatomy model – yellow so it stands out from the red stream.
    static let marker = UIColor(red: 1.00, green: 0.2, blue: 0.20, alpha: 1)
    static let markerHalo = UIColor(red: 1.00, green: 0.10, blue: 0.15, alpha: 1)

    static func zone(_ zone: AnatomyMap.Zone) -> UIColor {
        switch zone {
        case .boneMarrow: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        case .lungs: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        case .heart: return UIColor(red: 1.00, green: 0.30, blue: 0.40, alpha: 1)
        case .organs: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        case .spleen: return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        }
    }
}

