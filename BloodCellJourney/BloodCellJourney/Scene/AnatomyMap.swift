//
//  AnatomyMap.swift
//  BloodCellJourney
//
//  Where things are on YOUR physical anatomy model, in the coordinate system of the scan
//  (AnatomyModel.usdz in the RealityKitContent package): metres, +y up, origin at the centre of the base,
//  the figure faces +z, its right side is −x, its raised left arm is +x.
//
//  The values were measured from the scan. Vessels and outlines run inside the body (x-ray look).
//  To fine-tune: set Config.showAlignmentGhost = true, run on Vision Pro, and move points here.
//

import Foundation
import simd

enum AnatomyMap {

    enum Landmark: String, CaseIterable {
        case heart, archTop, aorta1, celiac, renal, aorta2, bifurcation
        case rHip, rThigh1, rThigh2, rKnee, rShin, rCalf, rAnkle
        case lHip, lThigh1, lThigh2, lKnee, lShin, lCalf, lAnkle
        case neck, head, headTop
        case rSubclavian, rShoulder, rUpperArm, rElbow, rForearm, rWrist, rHand
        case lSubclavian, lShoulder, lUpperArm, lElbow, lForearm, lWrist, lHand
        case liver, stomach, spleen, gut, gutL, gutR
        case rLung, lLung, pulmTrunk
        case rMarrow, lMarrow, pelvis, organs
    }

    static let positions: [Landmark: SIMD3<Float>] = [
        .heart: SIMD3<Float>(-0.068, 0.700, -0.053),
        .archTop: SIMD3<Float>(-0.080, 0.742, -0.061),
        .aorta1: SIMD3<Float>(-0.078, 0.680, -0.043),
        .celiac: SIMD3<Float>(-0.080, 0.640, -0.025),
        .renal: SIMD3<Float>(-0.082, 0.600, -0.029),
        .aorta2: SIMD3<Float>(-0.084, 0.560, -0.029),
        .bifurcation: SIMD3<Float>(-0.088, 0.515, -0.040),
        .rHip: SIMD3<Float>(-0.118, 0.490, -0.012),
        .rThigh1: SIMD3<Float>(-0.125, 0.440, 0.007),
        .rThigh2: SIMD3<Float>(-0.122, 0.380, 0.007),
        .rKnee: SIMD3<Float>(-0.120, 0.310, 0.014),
        .rShin: SIMD3<Float>(-0.118, 0.240, 0.001),
        .rCalf: SIMD3<Float>(-0.117, 0.170, 0.005),
        .rAnkle: SIMD3<Float>(-0.115, 0.120, 0.009),
        .lHip: SIMD3<Float>(-0.060, 0.490, -0.050),
        .lThigh1: SIMD3<Float>(-0.055, 0.440, -0.032),
        .lThigh2: SIMD3<Float>(-0.052, 0.380, -0.022),
        .lKnee: SIMD3<Float>(-0.055, 0.310, -0.010),
        .lShin: SIMD3<Float>(-0.065, 0.240, -0.050),
        .lCalf: SIMD3<Float>(-0.075, 0.170, -0.061),
        .lAnkle: SIMD3<Float>(-0.080, 0.120, -0.058),
        .neck: SIMD3<Float>(-0.088, 0.790, -0.044),
        .head: SIMD3<Float>(-0.088, 0.860, -0.026),
        .headTop: SIMD3<Float>(-0.088, 0.900, -0.027),
        .rSubclavian: SIMD3<Float>(-0.135, 0.752, -0.036),
        .rShoulder: SIMD3<Float>(-0.180, 0.735, -0.014),
        .rUpperArm: SIMD3<Float>(-0.200, 0.680, -0.005),
        .rElbow: SIMD3<Float>(-0.210, 0.600, -0.003),
        .rForearm: SIMD3<Float>(-0.216, 0.520, 0.012),
        .rWrist: SIMD3<Float>(-0.214, 0.460, 0.031),
        .rHand: SIMD3<Float>(-0.205, 0.425, 0.018),
        .lSubclavian: SIMD3<Float>(-0.035, 0.755, -0.067),
        .lShoulder: SIMD3<Float>(0.010, 0.755, -0.056),
        .lUpperArm: SIMD3<Float>(0.060, 0.748, -0.038),
        .lElbow: SIMD3<Float>(0.115, 0.738, -0.024),
        .lForearm: SIMD3<Float>(0.150, 0.760, 0.018),
        .lWrist: SIMD3<Float>(0.180, 0.785, 0.065),
        .lHand: SIMD3<Float>(0.212, 0.812, 0.084),
        .liver: SIMD3<Float>(-0.125, 0.635, -0.020),
        .stomach: SIMD3<Float>(-0.045, 0.645, -0.039),
        .spleen: SIMD3<Float>(-0.032, 0.640, -0.066),
        .gut: SIMD3<Float>(-0.090, 0.555, -0.027),
        .gutL: SIMD3<Float>(-0.060, 0.545, -0.043),
        .gutR: SIMD3<Float>(-0.118, 0.545, -0.018),
        .rLung: SIMD3<Float>(-0.120, 0.712, -0.038),
        .lLung: SIMD3<Float>(-0.042, 0.714, -0.079),
        .pulmTrunk: SIMD3<Float>(-0.074, 0.722, -0.061),
        .rMarrow: SIMD3<Float>(-0.135, 0.505, -0.013),
        .lMarrow: SIMD3<Float>(-0.042, 0.505, -0.049),
        .pelvis: SIMD3<Float>(-0.088, 0.500, -0.041),
        .organs: SIMD3<Float>(-0.088, 0.595, -0.026)
    ]

    static func p(_ landmark: Landmark) -> SIMD3<Float> {
        positions[landmark] ?? SIMD3<Float>(0, 0.5, 0)
    }

    // MARK: - Heart chambers

    /// Right side of the heart: receives oxygen-poor blood from the body, pumps it to the lungs.
    static var rightHeart: SIMD3<Float> { p(.heart) + SIMD3<Float>(-0.010, 0.002, 0.002) }
    /// Left side of the heart: receives oxygen-rich blood from the lungs, pumps it into the aorta.
    static var leftHeart: SIMD3<Float> { p(.heart) + SIMD3<Float>(0.008, -0.004, 0.004) }

    /// Veins run next to the arteries, shifted by this offset.
    static let veinOffset = SIMD3<Float>(-0.010, 0, -0.007)
    /// Pulmonary veins run next to the pulmonary arteries, shifted by this offset.
    static let pulmonaryVeinOffset = SIMD3<Float>(0, -0.008, 0.004)

    // MARK: - Circulation (the flowing red blood cells)

    /// Every branch of the body circulation, starting at the top of the aortic arch.
    /// Blood flows from the left heart through the branch (artery), turns around in the
    /// capillaries at its end, flows back next to it (vein) to the right heart, through the
    /// lungs and back to the left heart. Each branch becomes one closed loop.
    static let systemicBranches: [[Landmark]] = [
        [.archTop, .neck, .head, .headTop],
        [.archTop, .rSubclavian, .rShoulder, .rUpperArm, .rElbow, .rForearm, .rWrist, .rHand],
        [.archTop, .lSubclavian, .lShoulder, .lUpperArm, .lElbow, .lForearm, .lWrist, .lHand],
        [.archTop, .aorta1, .celiac, .liver],
        [.archTop, .aorta1, .celiac, .stomach, .spleen],
        [.archTop, .aorta1, .celiac, .renal, .gut, .gutL],
        [.archTop, .aorta1, .celiac, .renal, .gut, .gutR],
        [.archTop, .aorta1, .celiac, .renal, .aorta2, .bifurcation, .rHip, .rThigh1, .rThigh2, .rKnee, .rShin, .rCalf, .rAnkle],
        [.archTop, .aorta1, .celiac, .renal, .aorta2, .bifurcation, .lHip, .lThigh1, .lThigh2, .lKnee, .lShin, .lCalf, .lAnkle]
    ]

    /// Arterial landmarks of a branch (left heart → end of the branch).
    static func arterialPoints(_ branch: [Landmark]) -> [SIMD3<Float>] {
        [leftHeart] + branch.map { p($0) }
    }

    /// Venous landmarks of a branch (end of the branch → right heart). Head and arms return
    /// from above (superior vena cava), the rest of the body from below (inferior vena cava).
    static func venousPoints(_ branch: [Landmark]) -> [SIMD3<Float>] {
        var landmarks = Array(branch.reversed())
        if landmarks.contains(.aorta1) {
            landmarks.removeLast()   // lower body: skip the arch, enter the heart from below
        }
        return landmarks.map { p($0) + veinOffset } + [rightHeart]
    }

    /// Right heart → lung → left heart.
    static func pulmonaryPoints(lung: Landmark) -> (toLung: [SIMD3<Float>], fromLung: [SIMD3<Float>]) {
        let lungPoint = p(lung)
        let toLung = [rightHeart, p(.pulmTrunk), lungPoint]
        let fromLung = [lungPoint + pulmonaryVeinOffset, p(.pulmTrunk) + pulmonaryVeinOffset, leftHeart]
        return (toLung, fromLung)
    }

    // MARK: - Organ outlines (glowing contours instead of colour blobs)

    enum Zone: String, CaseIterable {
        case boneMarrow, lungs, heart, organs, spleen
    }

    /// A closed contour in the frontal plane (seen from the front), at depth `z`.
    struct Outline {
        let z: Float
        let points: [SIMD2<Float>]

        var points3D: [SIMD3<Float>] { points.map { SIMD3<Float>($0.x, $0.y, z) } }
    }

    /// Traced on the scan: right lung, heart, liver, stomach and intestines are visible in the open
    /// torso; the left lung, spleen and pelvis are drawn where they are anatomically.
    static func outlines(for zone: Zone) -> [Outline] {
        switch zone {
        case .lungs:
            return [
                Outline(z: -0.031, points: [
                    SIMD2<Float>(-0.105, 0.760), SIMD2<Float>(-0.125, 0.752), SIMD2<Float>(-0.142, 0.735), SIMD2<Float>(-0.150, 0.712),
                    SIMD2<Float>(-0.149, 0.692), SIMD2<Float>(-0.140, 0.683), SIMD2<Float>(-0.118, 0.680), SIMD2<Float>(-0.098, 0.682),
                    SIMD2<Float>(-0.088, 0.690), SIMD2<Float>(-0.087, 0.712), SIMD2<Float>(-0.090, 0.735), SIMD2<Float>(-0.096, 0.752)]),
                Outline(z: -0.067, points: [
                                SIMD2<Float>(-0.071, 0.760), SIMD2<Float>(-0.051, 0.752),
                                SIMD2<Float>(-0.034, 0.735), SIMD2<Float>(-0.026, 0.712),
                                SIMD2<Float>(-0.027, 0.692), SIMD2<Float>(-0.036, 0.683),
                                SIMD2<Float>(-0.058, 0.680), SIMD2<Float>(-0.078, 0.682),
                                SIMD2<Float>(-0.088, 0.690), SIMD2<Float>(-0.089, 0.712),
                                SIMD2<Float>(-0.086, 0.735), SIMD2<Float>(-0.080, 0.752)  ]),
            ]
            
        case .heart:
            return [
                Outline(z: -0.053, points: [
                    SIMD2<Float>(-0.076, 0.737), SIMD2<Float>(-0.084, 0.722), SIMD2<Float>(-0.087, 0.704), SIMD2<Float>(-0.084, 0.689),
                    SIMD2<Float>(-0.075, 0.679), SIMD2<Float>(-0.062, 0.676), SIMD2<Float>(-0.051, 0.679), SIMD2<Float>(-0.049, 0.690),
                    SIMD2<Float>(-0.054, 0.705), SIMD2<Float>(-0.063, 0.721), SIMD2<Float>(-0.069, 0.733)])
            ]
        case .organs:
            return [
                // liver
                Outline(z: -0.027, points: [
                    SIMD2<Float>(-0.142, 0.668), SIMD2<Float>(-0.122, 0.676), SIMD2<Float>(-0.090, 0.677), SIMD2<Float>(-0.062, 0.670),
                    SIMD2<Float>(-0.040, 0.656), SIMD2<Float>(-0.038, 0.642), SIMD2<Float>(-0.058, 0.630), SIMD2<Float>(-0.090, 0.620),
                    SIMD2<Float>(-0.120, 0.613), SIMD2<Float>(-0.140, 0.620), SIMD2<Float>(-0.147, 0.642)]),
                // stomach
                Outline(z: -0.031, points: [
                    SIMD2<Float>(-0.060, 0.646), SIMD2<Float>(-0.044, 0.648), SIMD2<Float>(-0.034, 0.636), SIMD2<Float>(-0.036, 0.618),
                    SIMD2<Float>(-0.048, 0.608), SIMD2<Float>(-0.064, 0.610), SIMD2<Float>(-0.070, 0.622), SIMD2<Float>(-0.066, 0.636)]),
                // intestines
                Outline(z: -0.023, points: [
                    SIMD2<Float>(-0.128, 0.592), SIMD2<Float>(-0.090, 0.598), SIMD2<Float>(-0.048, 0.592), SIMD2<Float>(-0.034, 0.572),
                    SIMD2<Float>(-0.036, 0.536), SIMD2<Float>(-0.050, 0.518), SIMD2<Float>(-0.090, 0.512), SIMD2<Float>(-0.125, 0.520),
                    SIMD2<Float>(-0.138, 0.545), SIMD2<Float>(-0.137, 0.575)])
            ]
        case .spleen:
            return [
                Outline(z: -0.052, points: [
                    SIMD2<Float>(-0.030, 0.662), SIMD2<Float>(-0.022, 0.652), SIMD2<Float>(-0.020, 0.636),
                    SIMD2<Float>(-0.026, 0.622), SIMD2<Float>(-0.034, 0.626), SIMD2<Float>(-0.036, 0.642)])
            ]
        case .boneMarrow:
            // The pelvis: red bone marrow in adults is mainly in flat bones like this one.
            return [
                Outline(z: -0.022, points: [
                    SIMD2<Float>(-0.088, 0.520), SIMD2<Float>(-0.110, 0.528), SIMD2<Float>(-0.135, 0.540), SIMD2<Float>(-0.152, 0.530),
                    SIMD2<Float>(-0.155, 0.510), SIMD2<Float>(-0.145, 0.490), SIMD2<Float>(-0.135, 0.475), SIMD2<Float>(-0.120, 0.462),
                    SIMD2<Float>(-0.100, 0.452), SIMD2<Float>(-0.088, 0.450), SIMD2<Float>(-0.076, 0.452), SIMD2<Float>(-0.056, 0.462),
                    SIMD2<Float>(-0.041, 0.475), SIMD2<Float>(-0.031, 0.490), SIMD2<Float>(-0.021, 0.510), SIMD2<Float>(-0.024, 0.530),
                    SIMD2<Float>(-0.041, 0.540), SIMD2<Float>(-0.066, 0.528)])
            ]
        }
    }

    // MARK: - Routes of "our" red blood cell (the yellow marker)

    enum Route {
        case marrowToLungs, lungsToOrgans, organsToLungs, fullCircuit, lungsToSpleen
    }

    static func points(for route: Route) -> [SIMD3<Float>] {
        switch route {
        case .marrowToLungs:
            return vein([.rMarrow, .rHip, .bifurcation, .aorta2, .renal, .celiac, .aorta1])
                + [rightHeart, p(.pulmTrunk), p(.rLung)]
        case .lungsToOrgans:
            return [p(.rLung) + pulmonaryVeinOffset, p(.pulmTrunk) + pulmonaryVeinOffset, leftHeart]
                + artery([.archTop, .aorta1, .celiac, .renal, .organs])
        case .organsToLungs:
            return vein([.organs, .renal, .celiac, .aorta1])
                + [rightHeart, p(.pulmTrunk), p(.lLung)]
        case .fullCircuit:
            return [p(.lLung) + pulmonaryVeinOffset, p(.pulmTrunk) + pulmonaryVeinOffset, leftHeart]
                + artery([.archTop, .aorta1, .celiac, .renal, .organs])
                + vein([.renal, .celiac, .aorta1])
                + [rightHeart, p(.pulmTrunk), p(.lLung)]
        case .lungsToSpleen:
            return [p(.lLung) + pulmonaryVeinOffset, p(.pulmTrunk) + pulmonaryVeinOffset, leftHeart]
                + artery([.archTop, .aorta1, .celiac, .stomach, .spleen])
        }
    }

    private static func artery(_ landmarks: [Landmark]) -> [SIMD3<Float>] {
        landmarks.map { p($0) }
    }

    private static func vein(_ landmarks: [Landmark]) -> [SIMD3<Float>] {
        landmarks.map { p($0) + veinOffset }
    }
}
