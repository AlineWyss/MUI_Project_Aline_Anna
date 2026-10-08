//
//  JourneyController+Interaction.swift
//  BloodCellJourney
//
//  Drag and tap handling. Every draggable model is a StageItem whose container has a
//  DraggableComponent, a collision sphere and an input target (see makeDraggable).
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
        } else if entity.isInside(overlay.tapTarget) {
            bloodstreamTapped()
        }
    }

    // MARK: - Drag

    func dragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        guard !interactionLocked else { return }

        // SwiftUI does not call onEnded when a gesture is cancelled (e.g. hand tracking lost).
        // A different start location means a new gesture: drop the stale session.
        if let stale = drag, stale.gestureStart != value.startLocation3D {
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
                               gestureStart: value.startLocation3D)
        }

        guard var session = drag, let parent = session.item.container.parent else { return }
        let location = value.convert(value.location3D, from: .local, to: parent)
        let proposed = session.startPosition + (location - session.startLocation)
        let position = constrain(session.item, proposed, session: &session)
        session.item.container.position = position
        // `constrain` may have finished the step (and ended the drag) – only keep a running session.
        if drag != nil {
            drag = session
        }
    }

    func dragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        guard let session = drag else { return }
        drag = nil
        isHolding = false
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

    private func beginDrag(_ item: StageItem) {
        item.container.stopAllAnimations()
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
        switch step {
        case .addHemoglobin where item === hemoglobin:
            guard let cell = developingCell else { return }
            if simd_distance(item.container.position, cell.container.position) < cell.radius * 0.9 {
                hemoglobinDelivered()
            } else {
                move(item.container, to: Layout.sideSlot, duration: 0.4)
            }

        case .ejectNucleus where item === nucleus:
            guard let cell = developingCell else { return }
            // The nucleus position is relative to the centre of its cell.
            if simd_length(item.container.position) > cell.radius * 0.95 {
                nucleusRemoved()
            } else {
                move(item.container, to: SIMD3<Float>(0, 0, 0), duration: 0.35)
            }

        case .lungsOxygen where item === oxygen:
            guard let cell = redBloodCell else { return }
            if simd_distance(item.container.position, cell.container.position) < cell.radius * 1.1 {
                oxygenBound()
            } else {
                move(item.container, to: Layout.sideSlot, duration: 0.4)
            }

        case .organsExchange where item === oxygen:
            guard let cell = redBloodCell, let target = bodyCell else { return }
            if simd_distance(item.container.position, target.container.position) < target.radius * 0.9 {
                oxygenDelivered()
            } else {
                bind(item, to: cell, at: oxygenSlot(on: cell), duration: 0.4)
            }

        case .lungsCarbonDioxide where item === carbonDioxide:
            guard let cell = redBloodCell else { return }
            if simd_distance(item.container.position, cell.container.position) > cell.radius * 1.5 {
                carbonDioxideReleased()
            } else {
                bind(item, to: cell, at: carbonDioxideSlot(on: cell), duration: 0.4)
            }

        case .aging where item === redBloodCell:
            springBack(item)
            if session.blocked {
                agingAttemptFailed()
            }

        default:
            // Squeezing: the cell simply stays where it was released.
            break
        }
    }
}

