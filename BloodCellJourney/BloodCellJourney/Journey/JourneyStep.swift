//
//  JourneyStep.swift
//  BloodCellJourney
//
//  The steps of the experience, in order.
//

import Foundation

enum JourneyStep: Int, CaseIterable {
    /// Waiting until the physical anatomy model is recognised.
    case searching
    /// Bloodstream glows on the physical model, start prompt in front of the person.
    case intro
    /// Red blood cell with name label, info, Start button and general facts.
    case meetCell
    /// Developing cell (shell + nucleus) in the bone marrow.
    case boneMarrow
    /// Drag hemoglobin into the cell.
    case addHemoglobin
    /// Pull the nucleus out; the cell turns into a red blood cell.
    case ejectNucleus
    /// Drag the new cell through a capillary into the bloodstream.
    case squeezeIntoBlood
    /// Travel to the lungs, then drag oxygen into the cell.
    case lungsOxygen
    /// Tap the heart 5× – blood flows to the organs.
    case pumpToOrgans
    /// Drag oxygen into the body cell, carbon dioxide comes back automatically.
    case organsExchange
    /// Tap the heart 5× – blood flows back to the lungs.
    case pumpToLungs
    /// Pull carbon dioxide out of the cell.
    case lungsCarbonDioxide
    /// How often the cycle repeats.
    case cycleRepeats
    /// The old cell no longer fits through the capillary.
    case aging
    /// The cell dissolves.
    case recycling
    /// Final facts and restart button in front of the physical model.
    case finished
}
