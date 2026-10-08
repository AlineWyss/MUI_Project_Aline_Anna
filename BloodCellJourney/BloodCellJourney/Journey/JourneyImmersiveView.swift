//
//  JourneyImmersiveView.swift
//  BloodCellJourney
//
//  The immersive space: one RealityView that hosts the whole scene and forwards gestures
//  to the JourneyController.
//

import RealityKit
import SwiftUI

struct JourneyImmersiveView: View {
    @State private var controller: JourneyController
    @Environment(\.openWindow) private var openWindow

    init(mode: ExperienceMode) {
        _controller = State(initialValue: JourneyController(mode: mode))
    }

    var body: some View {
        RealityView { content in
            // Keep this closure short: RealityView shows its content only after it returns,
            // so loading happens in .task below while the "Loading…" message is already visible.
            content.add(controller.root)
        }
        .gesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .task {
            await controller.prepare()
        }
        .task {
            await controller.runTracking()
        }
        .onDisappear {
            controller.shutDown()
            openWindow(id: AppModel.launchWindowID)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                controller.dragChanged(value)
            }
            .onEnded { value in
                controller.dragEnded(value)
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                controller.tapped(value.entity)
            }
    }
}
