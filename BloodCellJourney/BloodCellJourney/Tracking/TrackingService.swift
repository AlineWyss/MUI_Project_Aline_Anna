//
//  TrackingService.swift
//  BloodCellJourney
//
//  ARKit: recognises the physical anatomy model (object tracking with the .referenceobject
//  trained from your scan) and reports where the person's head is (world tracking).
//
//  Two separate sessions:
//  • world tracking starts immediately in both modes (head position),
//  • object tracking only runs with the physical model and can be stopped when the person
//    continues without it. Object tracking only works on Apple Vision Pro, not in the Simulator.
//

import ARKit
import Foundation
import QuartzCore
import simd

@MainActor
final class TrackingService {
    enum Status: Equatable {
        case idle
        case unsupported
        case notAuthorized
        case missingReferenceObject
        case running
        case failed(String)
    }

    /// Status of object tracking (the physical model).
    private(set) var status: Status = .idle
    private(set) var referenceObject: ReferenceObject?

    private let worldSession = ARKitSession()
    private let objectSession = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private var objectTrackingStoppedOnPurpose = false

    /// True on Apple Vision Pro, false in the Simulator.
    static var isObjectTrackingSupported: Bool {
        ObjectTrackingProvider.isSupported
    }

    static var referenceObjectURL: URL? {
        Bundle.main.url(forResource: Config.referenceObjectName, withExtension: "referenceobject")
    }

    /// Starts head tracking. Returns as soon as it runs (or right away if it isn't available).
    func startWorldTracking() async {
        guard WorldTrackingProvider.isSupported else { return }
        do {
            try await worldSession.run([worldTracking])
        } catch {
            // Without head tracking the app falls back to fixed positions.
        }
    }

    /// Looks for the physical model and calls `onObject` for every pose update.
    /// Only returns when object tracking stops or can't start; check `status` afterwards.
    func runObjectTracking(onObject: @escaping @MainActor (_ originFromObject: simd_float4x4, _ isTracked: Bool) -> Void) async {
        guard let objectTracking = await makeObjectTracking() else { return }
        // The person may have chosen "without the model" while permission/loading was pending.
        guard !objectTrackingStoppedOnPurpose else { return }
        do {
            try await objectSession.run([objectTracking])
        } catch {
            status = .failed(error.localizedDescription)
            return
        }

        status = .running
        for await update in objectTracking.anchorUpdates {
            let anchor = update.anchor
            switch update.event {
            case .added, .updated:
                onObject(anchor.originFromAnchorTransform, anchor.isTracked)
            case .removed:
                onObject(anchor.originFromAnchorTransform, false)
            @unknown default:
                break
            }
        }
        // The update stream ended although nobody stopped it: tracking stopped by itself.
        if !Task.isCancelled && !objectTrackingStoppedOnPurpose {
            status = .failed("Object tracking stopped. Close and reopen the experience.")
        }
    }

    /// Checks support, permission and the reference object. Sets `status` if something is missing.
    private func makeObjectTracking() async -> ObjectTrackingProvider? {
        guard ObjectTrackingProvider.isSupported else {
            status = .unsupported
            return nil
        }
        let authorization = await objectSession.requestAuthorization(for: [.worldSensing])
        if authorization[.worldSensing] == .denied {
            status = .notAuthorized
            return nil
        }
        guard let url = Self.referenceObjectURL else {
            status = .missingReferenceObject
            return nil
        }
        do {
            let object = try await ReferenceObject(from: url)
            referenceObject = object
            return ObjectTrackingProvider(referenceObjects: [object])
        } catch {
            status = .failed(error.localizedDescription)
            return nil
        }
    }

    /// The person continues without the physical model: stop looking for it.
    func stopObjectTracking() {
        objectTrackingStoppedOnPurpose = true
        objectSession.stop()
    }

    func stop() {
        objectTrackingStoppedOnPurpose = true
        objectSession.stop()
        worldSession.stop()
    }

    /// Current head pose in world space, if world tracking is running.
    func devicePose() -> simd_float4x4? {
        guard worldTracking.state == .running,
              let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return nil }
        return device.originFromAnchorTransform
    }

    func headPosition() -> SIMD3<Float>? {
        guard let pose = devicePose() else { return nil }
        return SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
    }
}
