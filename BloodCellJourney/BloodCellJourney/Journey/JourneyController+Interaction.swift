//
//  JourneyController+Interaction.swift
//  BloodCellJourney
//
//  Drag and tap handling. Every draggable model is a StageItem whose container has a
//  DraggableComponent, a collision sphere and an input target (see makeDraggable).
//  While an item is held, turning the wrist turns it (amplified by Layout.grabRotationGain);
//  the turn goes on the item's spin entity, so labels stay upright and the idle motion keeps running.
//  On release it turns smoothly back.
//

import Foundation
import RealityKit
import Spatial
import SwiftUI

extension JourneyController {

    // MARK: - Tap

    func tapped(_ entity: Entity) {
        if overlay.isHeart(entity) {
            heartTapped()
        } else if entity.isInside(overlay.stream.root) || entity.isInside(overlay.tapTarget) {
            bloodstreamTapped()
        }
    }

    // MARK: - Drag

    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        guard !interactionLocked else { return }
        // Solange die Stimme spricht: die Zelle noch nicht in die Gefässwand drücken lassen
        if waitingForVoice && (step == .squeezeIntoBlood || step == .aging) { return }

        // SwiftUI does not call onEnded when a gesture is cancelled (e.g. hand tracking lost).
        // A different start location means a new gesture: drop the stale session.
        if let stale = drag, stale.gestureStart != value.startLocation3D {
            returnSpin(stale.item)
            drag = nil
            isHolding = false
        }

        if drag == nil {
            guard let item = draggableItem(for: value.entity), item.container.parent != nil else { return }
            beginDrag(item)
            guard let parent = item.container.parent else { return }
            let start = value.convert(value.startLocation3D, from: .local, to: parent)
            drag = DragSession(item: item,
                               startPosition: item.container.position,
                               startLocation: start,
                               gestureStart: value.startLocation3D,
                               handStart: value.startInputDevicePose3D?.rotation,
                               spinStart: item.spin.orientation,
                               rotates: canRotate(item))
        }

        guard var session = drag, let parent = session.item.container.parent else { return }
        let location = value.convert(value.location3D, from: .local, to: parent)
        let proposed = session.startPosition + (location - session.startLocation)
        let position = constrain(session.item, proposed, session: &session)
        session.item.container.position = position
        if session.rotates, let handStart = session.handStart, let hand = value.inputDevicePose3D?.rotation {
            let turn = handTurn(from: handStart, to: hand)
            // The turn is in scene space; the spin entity lives in the container's space.
            let frame = session.item.container.orientation(relativeTo: nil)
            session.item.spin.orientation = frame.inverse * turn * frame * session.spinStart
        }
        // `constrain` may have finished the step (and ended the drag) – only keep a running session.
        if drag != nil {
            drag = session
        }
    }

    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let session = drag else { return }
        drag = nil
        isHolding = false
        returnSpin(session.item)
        finishDrag(session)
    }

    private func draggableItem(for entity: Entity) -> StageItem? {
        var current: Entity? = entity
        while let candidate = current {
            if let item = draggables[ObjectIdentifier(candidate)] { return item }
            current = candidate.parent
        }
        return nil
    }

    /// The red blood cell has to fit the gap in the two squeeze steps, so it can't be turned there.
    private func canRotate(_ item: StageItem) -> Bool {
        !(item === redBloodCell && (step == .squeezeIntoBlood || step == .aging))
    }

    /// How far the wrist has turned since the grab started, in scene space, amplified by Layout.grabRotationGain.
    private func handTurn(from start: Rotation3D, to current: Rotation3D) -> simd_quatf {
        var delta = simd_quatf(current) * simd_quatf(start).inverse
        if delta.real < 0 { delta = simd_quatf(vector: -delta.vector) }   // shortest way round
        // Gesture values use SwiftUI's space (y down); negating x and z gives RealityKit's scene space.
        let turn = simd_quatf(ix: -delta.imag.x, iy: delta.imag.y, iz: -delta.imag.z, r: delta.real)
        guard turn.angle > 0.0001 else { return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)) }
        return simd_quatf(angle: turn.angle * Layout.grabRotationGain, axis: turn.axis)
    }

    /// Turns an item smoothly back to how it was before it was grabbed.
    func returnSpin(_ item: StageItem) {
        item.spin.move(to: Transform(), relativeTo: item.container,
                       duration: Timing.grabRotationReturn, timingFunction: .easeInOut)
    }

    private func beginDrag(_ item: StageItem) {
        // A looked-at item keeps its inner animations (the shell's wobble); only its own movement stops.
        let deep = item !== lookAtItem
        item.container.stopAllAnimations(recursive: deep)
        item.spin.stopAllAnimations(recursive: deep)
        // The first cell is looked at on its own: its label and the Start button stay where they are.
        if step == .meetCell, item === redBloodCell { detachUI(from: item) }
        // Looked at: the label stays where it is; remember how it followed, so it can follow again later.
        if item === lookAtItem {
            if let follow = mainLabelSlot.entity?.components[FollowComponent.self],
               follow.target?.isInside(item.container) == true {
                lookAtLabelFollow = follow
            }
            detachUI(from: item)
        }
        // Grabbed for squeezing: the red blood cell settles straight.
        if item === redBloodCell { item.stopIdleMotion() }
        item.container.scale = SIMD3<Float>(repeating: 1)
        // Molecules attached to the red blood cell are lifted out into the focus area.
        // The nucleus stays inside its cell so its distance from the centre can be measured.
        if item.container.parent !== focusRoot && item !== nucleus {
            item.container.setParent(focusRoot, preservingWorldTransform: true)
        }
        isHolding = true
    }

    /// Limits where an item can go while it is dragged.
    private func constrain(_ item: StageItem, _ proposed: SIMD3<Float>, session: inout DragSession) -> SIMD3<Float> {
        switch step {
        case .squeezeIntoBlood where item === redBloodCell:
            return constrainSqueeze(item, proposed)

        case .aging where item === redBloodCell:
            return constrainAging(item, proposed, session: &session)

        default:
            return proposed
        }
    }

    /// Checks whether the item was dropped in the right place.
    private func finishDrag(_ session: DragSession) {
        let item = session.item
        if item === lookAtItem {
            // Looked at: it floats back to its place and rocks gently again; once it is back, its label
            // follows it again.
            let back = max(0.6, Timing.grabRotationReturn)
            lookAtBackAt = Date().addingTimeInterval(back)
            move(item.container, to: lookAtSlot, duration: 0.6)
            if item === redBloodCell { item.updateMotion { $0.idleFadeTarget = 1 } }
            let id = runID
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(back))
                guard id == self.runID, self.drag?.item !== item, self.mainLabel != nil,
                      let follow = self.lookAtLabelFollow, let label = self.mainLabelSlot.entity else { return }
                self.lookAtLabelFollow = nil
                self.follow(label, item.container, offset: follow.offset, anchor: follow.anchor)
            }
            return
        }
        switch step {
        case .addHemoglobin where item === hemoglobin:
            guard let cell = developingCell else { return }
            if !waitingForVoice && simd_distance(item.container.position, cell.container.position) < cell.radius * 0.9 {
                hemoglobinDelivered()
            } else {
                move(item.container, to: Layout.sideSlot, duration: 0.4)
            }

        case .ejectNucleus where item === nucleus:
            guard let cell = developingCell else { return }
            // The nucleus position is relative to the centre of its cell.
            if !waitingForVoice && simd_length(item.container.position) > cell.radius * 0.95 {
                nucleusRemoved()
            } else {
                move(item.container, to: SIMD3<Float>(0, 0, 0), duration: 0.35)
            }

        case .lungsOxygen where item === oxygen:
            guard let cell = redBloodCell else { return }
            if !waitingForVoice && simd_distance(item.container.position, cell.container.position) < cell.radius * 1.1 {
                oxygenBound()
            } else {
                move(item.container, to: Layout.sideSlot, duration: 0.4)
            }

        case .organsExchange where item === oxygen:
            guard let cell = redBloodCell, let target = bodyCell else { return }
            if !waitingForVoice && simd_distance(item.container.position, target.container.position) < target.radius * 0.9 {
                oxygenDelivered()
            } else {
                bind(item, to: cell, at: oxygenSlot(on: cell), duration: 0.4)
            }

        case .lungsCarbonDioxide where item === carbonDioxide:
            guard let cell = redBloodCell else { return }
            if !waitingForVoice && simd_distance(item.container.position, cell.container.position) > cell.radius * 1.5 {
                carbonDioxideReleased()
            } else {
                bind(item, to: cell, at: carbonDioxideSlot(on: cell), duration: 0.4)
            }

        case .aging where item === redBloodCell:
            springBack(item)
            calmIdle(item)   // back at the start: eases into its gentle movement again
            if session.blocked {
                agingAttemptFailed()
            }
        case .meetCell where item === redBloodCell:
            // Looked at: it floats back to its place and rocks gently again, as before.
            move(item.container, to: Layout.mainSlot, duration: 0.6)
            item.updateMotion { $0.idleFadeTarget = 1 }
            // Once it is back, label and Start button follow it again.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                guard self.step == .meetCell, self.redBloodCell === item else { return }
                self.reattachStartUI(to: item)
            }
            // Looked at: it floats back to its place and rocks gently again, as before.
            move(item.container, to: Layout.mainSlot, duration: 0.6)
            item.updateMotion { $0.idleFadeTarget = 1 }
        default:
            // Squeezing: the cell simply stays where it was released.
            break
        }
    }
    
    /// Label and Start button follow the first cell again, at the same places as in enterMeetCell.
    private func reattachStartUI(to cell: StageItem) {
        if mainLabel != nil, let label = mainLabelSlot.entity {
            follow(label, cell.container,
                   offset: SIMD3<Float>(0, cell.halfHeight + Layout.labelGap, 0), anchor: .bottom)
        }
        if showsStartButton, let button = startButtonSlot.entity {
            follow(button, cell.container,
                   offset: SIMD3<Float>(0, -(cell.halfHeight + Layout.buttonGap), 0), anchor: .top)
        }
    }
    
    // MARK: - Look at it: an item on its own can be held and turned

    /// An item standing alone on stage can be picked up, moved and turned to look at it; on release it
    /// floats back to `slot`. `carrying` turns along with it (the nucleus inside the developing cell).
    func allowLookAt(_ item: StageItem, returningTo slot: SIMD3<Float>, carrying: [StageItem] = []) {
        lookAtItem = item
        lookAtSlot = slot
        lookAtBackAt = .distantPast
        lookAtLabelFollow = nil
        for carried in carrying {
            carried.container.setParent(item.spin, preservingWorldTransform: true)
        }
        lookAtCarried = carrying
        makeDraggable(item)
        interactionLocked = false   // nothing else on stage can be grabbed in these moments
    }

    /// Before the story goes on: waits until the looked-at item is let go and back in its place (label
    /// following again), then it can no longer be grabbed. Returns false if the story was restarted.
    func endLookAt(_ id: Int) async -> Bool {
        guard let item = lookAtItem else { return id == runID }
        while true {
            // Still in the hand: the story waits until it is let go …
            while drag?.item === item {
                guard await pause(0.1, id) else { return false }
            }
            // … and until it has floated and turned back.
            let left = lookAtBackAt.timeIntervalSinceNow + 0.1
            if left > 0 {
                guard await pause(left, id) else { return false }
            }
            if drag?.item !== item { break }   // grabbed again meanwhile → wait once more
        }
        guard lookAtItem === item else { return id == runID }   // already ended by another caller
        makeStatic(item)
        // What turned along goes back to where it was (the spin has turned back, so nothing moves).
        for carried in lookAtCarried {
            carried.container.setParent(item.container, preservingWorldTransform: true)
        }
        lookAtCarried = []
        lookAtItem = nil
        return true
    }
}
