//
//  AppModel.swift
//  BloodCellJourney
//

import SwiftUI

/// How the experience is shown.
enum ExperienceMode: String {
    /// The physical anatomy model stands in the room and is recognised with object tracking.
    case physicalModel
    /// No physical model: a see-through virtual copy of the scan stands front-left of the person.
    /// Also used in the Simulator.
    case virtualModel
}

@MainActor
@Observable
final class AppModel {
    static let launchWindowID = "Launch"
    static let immersiveSpaceID = "Journey"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    /// Chosen in the launch window before the immersive space opens.
    var mode: ExperienceMode = .physicalModel
}
