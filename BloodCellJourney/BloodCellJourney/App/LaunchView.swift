//
//  LaunchView.swift
//  BloodCellJourney
//
//  Small start window: start with the physical anatomy model or without it (virtual copy).
//  Opens the immersive experience and closes this window.
//

import SwiftUI

struct LaunchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var errorText: String?

    /// Why the physical model can't be used on this device (nil = it can).
    private var physicalModelNote: String? {
        if !TrackingService.isObjectTrackingSupported { return StoryText.Launch.needsVisionPro }
        if TrackingService.referenceObjectURL == nil { return StoryText.Launch.missingReferenceObject }
        return nil
    }

    private var isBusy: Bool {
        appModel.immersiveSpaceState == .inTransition
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "drop.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text(StoryText.Launch.title)
                .font(.extraLargeTitle)
            Text(StoryText.Launch.subtitle)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(StoryText.Launch.body)
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            VStack(spacing: 14) {
                Button {
                    Task { await begin(.physicalModel) }
                } label: {
                    Label(StoryText.Launch.withModel, systemImage: "figure.stand")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isBusy || physicalModelNote != nil)

                Button {
                    Task { await begin(.virtualModel) }
                } label: {
                    Label(StoryText.Launch.withoutModel, systemImage: "cube.transparent")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                if let note = physicalModelNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(48)
    }

    private func begin(_ mode: ExperienceMode) async {
        guard appModel.immersiveSpaceState == .closed else { return }
        appModel.mode = mode
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
        case .opened:
            appModel.immersiveSpaceState = .open
            errorText = nil
            dismissWindow(id: AppModel.launchWindowID)
        case .userCancelled, .error:
            appModel.immersiveSpaceState = .closed
            errorText = StoryText.Launch.failed
        @unknown default:
            appModel.immersiveSpaceState = .closed
            errorText = StoryText.Launch.failed
        }
    }
}
