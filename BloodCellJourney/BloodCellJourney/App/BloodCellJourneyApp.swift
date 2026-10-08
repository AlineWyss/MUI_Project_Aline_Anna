//
//  BloodCellJourneyApp.swift
//  BloodCellJourney
//
//  A visionOS app that follows a red blood cell through its life. A physical anatomy model is
//  recognised with object tracking and extended with the bloodstream; the interactive cells
//  appear in front of the person.
//

import SwiftUI

@main
struct BloodCellJourneyApp: App {
    @State private var appModel = AppModel()

    init() {
        JourneySystems.registerAll()
    }

    var body: some Scene {
        WindowGroup(id: AppModel.launchWindowID) {
            LaunchView()
                .environment(appModel)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            JourneyImmersiveView(mode: appModel.mode)
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
