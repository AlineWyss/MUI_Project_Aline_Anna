//
//  JourneyController+Steps.swift
//  BloodCellJourney
//
//  The story, one function per step (see JourneyStep.swift for the order).
//

import Foundation
import RealityKit
import UIKit

extension JourneyController {

    // MARK: - Intro: bloodstream on the physical model + start prompt

    func enterIntro() {
        step = .intro
        clearStage()
        showMessage(nil)
        hideFinalPanel()
        if mode == .virtualModel {
            // Re-place the virtual model in case the person moved since the last round.
            placeVirtualAnatomy()
        }
        placeFocusArea()

        overlay.reset()
        overlay.tapTarget.isEnabled = true
        overlay.setStreamVisible(true)       // the blood stream is only part of this first scene
        labelledItems.removeAll()            // every run shows each label once again
        highlight(nil)
        setStartPromptVisible(true)
    }

    /// Tap on the bloodstream of the physical model.
    func bloodstreamTapped() {
        guard step == .intro else { return }
        overlay.tapTarget.isEnabled = false
        overlay.setStreamVisible(false)      // fades out; it does not come back until "Start again"
        setStartPromptVisible(false)
        enterMeetCell()
    }

    // MARK: - Meet the red blood cell

    func enterMeetCell() {
        step = .meetCell
        let cell = library.redBloodCell()
        setColor(cell, Palette.rbcOxygenated, animated: false)

        // The cell comes out of the heart of the physical model and flies to the person.
        let heartWorld = anatomyRoot.convert(position: AnatomyMap.p(.heart), to: nil)
        place(cell, at: focusRoot.convert(position: heartWorld, from: nil))
        cell.container.scale = SIMD3<Float>(repeating: 0.05)
        var target = Transform()
        target.translation = Layout.mainSlot
        cell.container.move(to: target, relativeTo: focusRoot, duration: 1.2, timingFunction: .easeInOut)
        cell.updateMotion {
            $0.rockAngle = 0.45
            $0.hover = 0.006
        }
        redBloodCell = cell

        setMainLabel(StoryText.Labels.redBloodCell, on: cell)
        showStartButton(below: cell)
        setPanel(StoryText.Panels.meetCell)
    }

    /// Start button below the red blood cell.
    func startTapped() {
        guard step == .meetCell else { return }
        showStartButton(below: nil)
        enterBoneMarrow()
    }

    // MARK: - Bone marrow: the developing cell

    func enterBoneMarrow() {
        step = .boneMarrow
        remove(redBloodCell)
        redBloodCell = nil

        let parts = library.developingCell()
        place(parts.cell, at: Layout.mainSlot)
        popIn(parts.cell)
        developingCell = parts.cell
        nucleus = parts.nucleus

        setMainLabel(StoryText.Labels.erythroblast, on: parts.cell)
        setPanel(StoryText.Panels.boneMarrow)

        highlight(.boneMarrow)
        overlay.showMarker(at: .rMarrow)
    }

    /// "Next" button in the text panel.
    func continueTapped() {
        switch step {
        case .boneMarrow: enterAddHemoglobin()
        case .cycleRepeats: enterAging()
        default: break
        }
    }

    // MARK: - Hemoglobin into the cell

    func enterAddHemoglobin() {
        step = .addHemoglobin
        let item = library.hemoglobin()
        place(item, at: Layout.sideSlot)
        popIn(item)
        item.updateMotion {
            $0.rockAngle = 0.6
            $0.rockSpeed = 0.6
        }
        makeDraggable(item)
        hemoglobin = item

        setSecondaryLabel(StoryText.Labels.hemoglobin, on: item)
        setPanel(StoryText.Panels.addHemoglobin)
    }

    func hemoglobinDelivered() {
        guard let item = hemoglobin, let cell = developingCell else { return }
        makeStatic(item)
        setSecondaryLabel(nil, on: nil)
        interactionLocked = true

        // Hemoglobin sinks into the cell and the cell fills up red.
        move(item.container, to: cell.container.position, scale: 0.3, duration: 0.6)
        let fill = ModelEntity(mesh: .generateSphere(radius: 1),
                               materials: [MaterialTools.translucent(Palette.hemoglobinFill, opacity: 0.35)])
        fill.scale = SIMD3<Float>(repeating: 0.001)
        cell.motion.addChild(fill)
        hemoglobinFill = fill
        var grown = Transform()
        grown.scale = SIMD3<Float>(repeating: cell.radius * 0.82)
        fill.move(to: grown, relativeTo: cell.motion, duration: 1.4, timingFunction: .easeInOut)

        sequence { id in
            guard await self.pause(0.6, id) else { return }
            self.remove(item, duration: 0.4)
            self.hemoglobin = nil
            guard await self.pause(1.0, id) else { return }
            self.interactionLocked = false
            self.enterEjectNucleus()
        }
    }

    // MARK: - Pull the nucleus out

    func enterEjectNucleus() {
        step = .ejectNucleus
        guard let nucleus, let cell = developingCell else { return }
        nucleus.updateMotion { $0.wiggle = 0.0045 }
        makeDraggable(nucleus)

        setMainLabel(nil, on: nil)
        setSecondaryLabel(StoryText.Labels.nucleus, on: nucleus, height: cell.halfHeight + Layout.labelGap)
        setPanel(StoryText.Panels.ejectNucleus)
    }

    func nucleusRemoved() {
        guard let nucleus, let cell = developingCell else { return }
        makeStatic(nucleus)
        nucleus.updateMotion { $0.wiggle = 0 }
        setSecondaryLabel(nil, on: nil)
        interactionLocked = true

        // The nucleus drifts away (it is eaten by macrophages).
        var away = nucleus.container.position
        if simd_length(away) > 0.001 { away += simd_normalize(away) * 0.12 }
        away.y += 0.05
        move(nucleus.container, to: away, scale: 0.6, duration: 1.2)
        remove(nucleus, duration: 1.2)
        self.nucleus = nil

        sequence { id in
            guard await self.pause(0.6, id) else { return }
            // The developing cell turns into a red blood cell.
            let newCell = self.library.redBloodCell()
            self.setColor(newCell, Palette.rbcDeoxygenated, animated: false)
            self.place(newCell, at: Layout.mainSlot)
            self.remove(cell, duration: 0.8)
            self.developingCell = nil
            self.hemoglobinFill = nil
            self.popIn(newCell, duration: 0.9)
            self.redBloodCell = newCell
            self.setMainLabel(StoryText.Labels.youngRedBloodCell, on: newCell)
            self.setPanel(StoryText.Panels.cellBorn)

            guard await self.pause(Timing.afterBirth, id) else { return }
            self.interactionLocked = false
            self.enterSqueezeIntoBlood()
        }
    }

    // Step "squeeze" (into the bloodstream): see JourneyController+Squeeze.swift

    // MARK: - Lungs: oxygen in

    func enterLungsOxygen() {
        step = .lungsOxygen
        setPanel(StoryText.Panels.travelToLungs)
        guard let cell = redBloodCell else { return }
        interactionLocked = true

        sequence { id in
            // Attention moves to the anatomy model: the cell flies into it and travels on as the yellow marker.
            await self.flyIntoModel(cell, at: self.overlay.startPosition(of: .marrowToLungs))
            guard id == self.runID else { return }
            self.highlight(nil)
            await self.overlay.travel(.marrowToLungs, duration: Timing.travelToLungs)
            guard id == self.runID else { return }
            self.highlight(.lungs)
            await self.flyOutOfModel(cell, from: self.overlay.markerWorldPosition, to: Layout.mainSlot,
                                     label: StoryText.Labels.youngRedBloodCell)
            guard id == self.runID else { return }
            self.interactionLocked = false

            let molecule = self.library.oxygen()
            self.place(molecule, at: Layout.sideSlot)
            self.popIn(molecule)
            molecule.updateMotion {
                $0.rockAngle = 0.5
                $0.hover = 0.008
            }
            self.makeDraggable(molecule)
            self.oxygen = molecule
            self.setSecondaryLabel(StoryText.Labels.oxygen, on: molecule)
            self.setPanel(StoryText.Panels.lungsOxygen)
        }
    }

    func oxygenBound() {
        guard let molecule = oxygen, let cell = redBloodCell else { return }
        makeStatic(molecule)
        molecule.stopIdleMotion()
        setSecondaryLabel(nil, on: nil)
        bind(molecule, to: cell, at: oxygenSlot(on: cell))
        setColor(cell, Palette.rbcOxygenated, animated: true)
        interactionLocked = true

        sequence { id in
            guard await self.pause(1.4, id) else { return }
            self.interactionLocked = false
            self.enterPump(toOrgans: true)
        }
    }

    // MARK: - Heart pumps (5 taps)

    /// The cell flies into the anatomy model; the heart of the model has to be pumped 5 times.
    func enterPump(toOrgans: Bool) {
        step = toOrgans ? .pumpToOrgans : .pumpToLungs
        heartBeats = 0
        let route: AnatomyMap.Route = toOrgans ? .lungsToOrgans : .organsToLungs
        overlay.prepareSteps(along: route)
        guard let cell = redBloodCell else { return }
        interactionLocked = true
        if !toOrgans {
            remove(bodyCell, duration: 0.6)
            bodyCell = nil
            setSecondaryLabel(nil, on: nil)
        }
        setPanel(toOrgans ? StoryText.Panels.pumpToOrgans : StoryText.Panels.pickUpCO2)

        sequence { id in
            await self.flyIntoModel(cell, at: self.overlay.startPosition(of: route))
            guard id == self.runID else { return }
            // The heart of the anatomy model becomes the button; it only beats when tapped.
            self.overlay.stream.autoBeat = false
            self.highlight(.heart)
            self.overlay.setHeartTappable(true)
            self.showHeartCounter()
            self.interactionLocked = false
        }
    }

    /// Tap on the heart of the anatomy model (or on the counter next to it).
    func heartTapped() {
        guard step == .pumpToOrgans || step == .pumpToLungs, showsHeart, heartBeats < requiredHeartBeats else { return }
        heartBeats += 1
        overlay.beatHeart()
        overlay.advance(to: Float(heartBeats) / Float(requiredHeartBeats), duration: Timing.heartStep)

        guard heartBeats == requiredHeartBeats else { return }
        let toOrgans = step == .pumpToOrgans
        overlay.setHeartTappable(false)
        sequence { id in
            guard await self.pause(Timing.heartStep + 0.3, id) else { return }
            self.hideHeartCounter()
            self.overlay.stream.autoBeat = true
            self.highlight(toOrgans ? .organs : .lungs)
            guard let cell = self.redBloodCell else { return }
            await self.flyOutOfModel(cell, from: self.overlay.markerWorldPosition, to: Layout.mainSlot,
                                     label: StoryText.Labels.redBloodCell)
            guard id == self.runID else { return }
            if toOrgans {
                self.enterOrgansExchange()
            } else {
                self.enterLungsCarbonDioxide()
            }
        }
    }

    // MARK: - Organs: oxygen out, carbon dioxide in

    func enterOrgansExchange() {
        step = .organsExchange
        highlight(.organs)

        let cell = library.bodyCell()
        place(cell, at: Layout.sideSlot)
        popIn(cell)
        cell.updateMotion { $0.hover = 0.005 }
        bodyCell = cell
        setSecondaryLabel(StoryText.Labels.bodyCell, on: cell)
        if let molecule = oxygen { makeDraggable(molecule) }
        setPanel(StoryText.Panels.deliverOxygen)
    }

    func oxygenDelivered() {
        guard let molecule = oxygen, let cell = redBloodCell, let target = bodyCell else { return }
        makeStatic(molecule)
        interactionLocked = true

        // Oxygen moves into the body cell and is used up.
        move(molecule.container, to: target.container.position, scale: 0.3, duration: 0.7)
        sequence { id in
            guard await self.pause(0.7, id) else { return }
            self.remove(molecule, duration: 0.4)
            self.oxygen = nil
            guard await self.pause(0.5, id) else { return }

            // Carbon dioxide comes out of the body cell and travels to the red blood cell by itself.
            let waste = self.library.carbonDioxide()
            self.place(waste, at: target.container.position)
            self.popIn(waste, duration: 0.5)
            self.carbonDioxide = waste
            self.setSecondaryLabel(StoryText.Labels.carbonDioxide, on: waste)
            guard await self.pause(0.7, id) else { return }

            let slot = cell.container.position + self.carbonDioxideSlot(on: cell)
            self.move(waste.container, to: slot, duration: 1.1)
            guard await self.pause(1.15, id) else { return }
            self.bind(waste, to: cell, at: self.carbonDioxideSlot(on: cell), duration: 0.2)
            self.setColor(cell, Palette.rbcDeoxygenated, animated: true, duration: 1.6)
            self.interactionLocked = false
            self.enterPump(toOrgans: false)
        }
    }

    // MARK: - Lungs: carbon dioxide out

    func enterLungsCarbonDioxide() {
        step = .lungsCarbonDioxide
        highlight(.lungs)
        guard let waste = carbonDioxide else { return }
        makeDraggable(waste)
        setMainLabel(nil, on: nil)
        setSecondaryLabel(StoryText.Labels.carbonDioxide, on: waste)
        setPanel(StoryText.Panels.exhaleCO2)
    }

    func carbonDioxideReleased() {
        guard let waste = carbonDioxide, let cell = redBloodCell else { return }
        makeStatic(waste)
        setSecondaryLabel(nil, on: nil)
        interactionLocked = true

        // CO2 is breathed out …
        let up = waste.container.position + SIMD3<Float>(0.05, 0.25, -0.15)
        move(waste.container, to: up, duration: 1.2)
        remove(waste, duration: 1.2)
        carbonDioxide = nil

        // … and fresh oxygen binds again.
        sequence { id in
            guard await self.pause(0.5, id) else { return }
            let fresh = self.library.oxygen()
            self.place(fresh, at: cell.container.position + SIMD3<Float>(0.25, 0.18, 0))
            self.popIn(fresh, duration: 0.4)
            self.oxygen = fresh
            guard await self.pause(0.4, id) else { return }
            self.bind(fresh, to: cell, at: self.oxygenSlot(on: cell), duration: 0.8)
            self.setColor(cell, Palette.rbcOxygenated, animated: true)
            guard await self.pause(1.4, id) else { return }
            self.interactionLocked = false
            self.enterCycleRepeats()
        }
    }

    // MARK: - The cycle repeats

    func enterCycleRepeats() {
        step = .cycleRepeats
        highlight(nil)
        guard let cell = redBloodCell else { return }
        interactionLocked = true

        sequence { id in
            // The cell goes back into the body and runs round and round.
            await self.flyIntoModel(cell, at: self.overlay.startPosition(of: .fullCircuit))
            guard id == self.runID, self.step == .cycleRepeats else { return }
            self.overlay.loop(.fullCircuit, lapDuration: Timing.lapDuration)
            self.interactionLocked = false
            self.setPanel(StoryText.Panels.cycleRepeats)
        }
    }

    // MARK: - Aging: the old cell no longer fits

    func enterAging() {
        step = .aging
        agingAttempts = 0
        guard let cell = redBloodCell else { return }
        interactionLocked = true
        setPanel(StoryText.Panels.agingIntro)
        remove(oxygen, duration: 0.8)
        oxygen = nil
        // The cell ages while it is inside the body.
        setColor(cell, Palette.rbcAged, animated: false)

        sequence { id in
            await self.overlay.travel(.lungsToSpleen, duration: Timing.travelToSpleen)
            guard id == self.runID else { return }
            self.highlight(.spleen)
            await self.flyOutOfModel(cell, from: self.overlay.markerWorldPosition, to: Layout.squeezeStart,
                                     label: StoryText.Labels.oldRedBloodCell)
            guard id == self.runID else { return }
            // The same squeeze as before – but the old cell can't get through (JourneyController+Squeeze.swift).
            await self.startAgingSqueeze(cell, id)
        }
    }

    func agingAttemptFailed() {
        agingAttempts += 1
        if agingAttempts < Timing.requiredAgingAttempts {
            setPanel(StoryText.Panels.agingTryAgain)
            return
        }
        guard let cell = redBloodCell else { return }
        makeStatic(cell)
        interactionLocked = true

        // The text fades out and the explanation fades in.
        sequence { id in
            self.setPanel(nil)
            guard await self.pause(0.6, id) else { return }
            self.setPanel(StoryText.Panels.tooStiff)
            guard await self.pause(Timing.readTooStiff, id) else { return }
            self.enterRecycling()
        }
    }

    // MARK: - Recycling: the cell dissolves

    func enterRecycling() {
        step = .recycling
        guard let cell = redBloodCell else {
            enterFinished()
            return
        }
        setMainLabel(nil, on: nil)
        setSecondaryLabel(nil, on: nil)
        setPanel(nil)
        dissolve(cell)
        remove(capillary, duration: 1.0)
        capillary = nil
        squeezeScene = nil

        sequence { id in
            guard await self.pause(2.4, id) else { return }
            self.enterFinished()
        }
    }

    private func dissolve(_ cell: StageItem) {
        let emitter = Entity()
        emitter.position = cell.container.position
        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.emitterShapeSize = SIMD3<Float>(repeating: cell.radius)
        particles.speed = 0.05
        particles.mainEmitter.birthRate = 1500
        particles.mainEmitter.lifeSpan = 1.4
        particles.mainEmitter.size = 0.004
        particles.mainEmitter.color = .evolving(start: .single(Palette.rbcAged),
                                                end: .single(Palette.rbcAged.withAlphaComponent(0)))
        particles.isEmitting = true
        emitter.components.set(particles)
        focusRoot.addChild(emitter)

        // The cell shrinks and fades while the particles drift apart.
        move(cell.container, to: cell.container.position, scale: 0.2, duration: 1.2)
        remove(cell, duration: 1.2)
        redBloodCell = nil

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            if var component = emitter.components[ParticleEmitterComponent.self] {
                component.isEmitting = false
                emitter.components.set(component)
            }
            try? await Task.sleep(for: .seconds(2.0))
            emitter.removeFromParent()
        }
    }

    // MARK: - Finished: facts + restart in the middle, in front of the person

    func enterFinished() {
        step = .finished
        clearStage()
        highlight(nil)
        overlay.hideMarker()

        // Where the cells were – the centre of the focus area, facing the person.
        showsFinalPanel = true
        finalPanelSlot.show(at: Layout.finalPanelSlot)
    }

    func hideFinalPanel() {
        showsFinalPanel = false
        finalPanelSlot.hide()
    }

    /// "Start again" on the end screen.
    func restartTapped() {
        guard step == .finished, showsFinalPanel else { return }
        // Ignore a second tap; the panel itself is removed once the button action has finished.
        showsFinalPanel = false
        Task { @MainActor in
            guard self.step == .finished else { return }
            self.runID += 1
            self.enterIntro()
        }
    }
}

