//
//  JourneyController+Squeeze.swift
//  BloodCellJourney
//
//  The squeeze animation from claudeAniamtion.blend in the story:
//    - step "squeeze": the young red blood cell is pushed into the capillary wall. How far it is pushed
//      decides the animation frame – the cell folds through its shape keys and the wall bulges –
//      until the cell is inside the capillary.
//    - step "aging": the same animation, but the old stiff cell only gets as far as
//      Timing.agingStopFrame, shakes and springs back.
//  Everything for the squeeze lives in this file, SqueezeScene and SqueezeAnimation; the models and their
//  materials are in Reality Composer Pro (scene "SqueezeScene").
//

import Foundation
import RealityKit
import UIKit

extension JourneyController {

    // MARK: - Setting up and ending the squeeze

    /// Shows the capillary and swaps the cell's model for the morphing one; the cell moves to the
    /// start of the animated path. Returns nil if the baked animation can't be loaded (logged) or the story
    /// was restarted meanwhile (`id` is the sequence id).
    func beginSqueeze(with cell: StageItem, _ id: Int) async -> SqueezeScene? {
        let scene: SqueezeScene
        do {
            scene = try await SqueezeScene(animation: SqueezeAnimation.shared(),
                                           start: Layout.squeezeStart,
                                           cellSize: Layout.Size.redBloodCell,
                                           cellColor: cell.currentColor.map { UIColor(rgba: $0) })
        } catch {
            print("Squeeze animation unavailable: \(error.localizedDescription)")
            return nil
        }
        guard id == runID else { return nil }

        place(scene.capillary, at: scene.capillary.container.position)
        popIn(scene.capillary)
        capillary = scene.capillary

        cell.stopIdleMotion()
        cell.container.stopAllAnimations()
        cell.container.scale = SIMD3<Float>(repeating: 1)
        scene.attach(to: cell, duration: 0.8)
        move(cell.container, to: scene.start, duration: 0.8)
        squeezeScene = scene
        return scene
    }

    /// The cell moves to `slot`, relaxes into its normal shape and gets its normal model back.
    func endSqueeze(of cell: StageItem, scene: SqueezeScene?, moveTo slot: SIMD3<Float>) async {
        move(cell.container, to: slot, duration: Timing.squeezeRelax)
        guard let scene else { return }
        scene.restoreSize(duration: Timing.squeezeRelax)
        // The cell relaxes; the capillary (fading out) keeps its shape.
        await scene.animate(to: scene.firstFrame, duration: Timing.squeezeRelax, includeCapillary: false)
        scene.detach(from: cell)
        if squeezeScene === scene {
            squeezeScene = nil
        }
    }

    // MARK: - Step "squeeze": into the bloodstream

    func enterSqueezeIntoBlood() {
        step = .squeezeIntoBlood
        squeezeDone = false
        guard let cell = redBloodCell else { return }
        setPanel(StoryText.Panels.squeeze)

        sequence { id in
            guard let scene = await self.beginSqueeze(with: cell, id) else {
                guard id == self.runID else { return }
                // Without the baked animation the story simply goes on.
                self.squeezeDone = true
                guard await self.pause(0.5, id) else { return }
                self.enterLungsOxygen()
                return
            }
            guard id == self.runID, self.step == .squeezeIntoBlood else { return }
            self.makeDraggable(cell)
            self.setSecondaryLabel(StoryText.Labels.capillary, on: scene.capillary, height: scene.labelHeight)
        }
    }

    /// The cell has been pushed all the way into the capillary.
    func squeezeCompleted() {
        guard step == .squeezeIntoBlood, !squeezeDone, let cell = redBloodCell else { return }
        squeezeDone = true
        makeStatic(cell)
        interactionLocked = true
        let scene = squeezeScene

        sequence { id in
            self.setSecondaryLabel(nil, on: nil)
            // The cell is inside the capillary now: the capillary fades, the cell comes to the centre
            // and relaxes into its normal shape.
            self.remove(self.capillary, duration: 0.6)
            self.capillary = nil
            await self.endSqueeze(of: cell, scene: scene, moveTo: Layout.mainSlot)
            guard id == self.runID else { return }
            self.interactionLocked = false
            self.enterLungsOxygen()
        }
    }

    // MARK: - Step "aging": the old cell can't get through

    /// Called once the old cell has flown out of the anatomy model.
    func startAgingSqueeze(_ cell: StageItem, _ id: Int) async {
        guard await beginSqueeze(with: cell, id) != nil else {
            guard id == runID else { return }
            // Without the baked animation: straight to the explanation.
            setPanel(StoryText.Panels.tooStiff)
            guard await pause(Timing.readTooStiff, id) else { return }
            enterRecycling()
            return
        }
        interactionLocked = false
        makeDraggable(cell)
        setPanel(StoryText.Panels.agingTry)
    }

    /// The stiff cell springs back into its old shape and position after it was let go.
    func springBack(_ item: StageItem) {
        guard let scene = squeezeScene else {
            move(item.container, to: Layout.squeezeStart, duration: Timing.springBack)
            return
        }
        sequence { _ in
            await scene.animate(to: scene.firstFrame, duration: Timing.springBack, moving: item)
        }
    }

    // MARK: - Dragging (called from constrain in JourneyController+Interaction.swift)

    /// The cell follows the path from the Blender animation; how far it is pushed decides the animation
    /// frame (its shape and the bulge of the capillary wall).
    func constrainSqueeze(_ item: StageItem, _ proposed: SIMD3<Float>) -> SIMD3<Float> {
        guard let scene = squeezeScene else { return proposed }
        let hit = scene.path.closest(to: proposed)
        scene.show(frame: scene.frame(atDistance: hit.along))
        if hit.along >= scene.path.length - 0.004 {
            squeezeCompleted()
        }
        return hit.point
    }

    /// Same animation, but the stiff old cell only gets as far as Timing.agingStopFrame.
    func constrainAging(_ item: StageItem, _ proposed: SIMD3<Float>, session: inout DragSession) -> SIMD3<Float> {
        guard let scene = squeezeScene else { return proposed }
        let limit = scene.distance(atFrame: Timing.agingStopFrame)
        var along = scene.path.closest(to: proposed).along
        if along >= limit - 0.002 {
            along = limit
            if !session.blocked {
                session.blocked = true
                item.shake()
            }
        }
        scene.show(frame: scene.frame(atDistance: along))
        return scene.path.locate(distance: along).point
    }
}
