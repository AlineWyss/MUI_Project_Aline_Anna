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
        VoiceGuide.shared.stop()
        clearStage()
        showMessage(nil)
        hideFinalPanel()
        if mode == .virtualModel {
            // Re-place the virtual model in case the person moved since the last round.
            placeVirtualAnatomy()
        }
        placeFocusArea()
        if !anatomyRoot.isEnabled {
            // First appearance: the bloodstream (already flowing) and the virtual copy fade in gently.
            anatomyRoot.components.set(OpacityComponent(opacity: 0))
            anatomyRoot.components.set(FadeComponent(target: 1, speed: Float(1 / Timing.introFadeIn),
                                                     disableWhenHidden: false))
            anatomyRoot.isEnabled = true
        }

        overlay.reset()
        overlay.tapTarget.isEnabled = true
        overlay.setStreamVisible(true)       // fades in, already flowing; only part of this first scene
        labelledItems.removeAll()            // every run shows each label once again
        highlight(nil)
        warmUpRedBloodCell()

        // A short calm moment with just the flowing bloodstream, then the start prompt and the welcome voice.
        sequence { id in
            guard await self.pause(Timing.introVoiceDelay, id), self.step == .intro else { return }
            self.setStartPromptVisible(true)
            self.setPanel(StoryText.Panels.welcome)
        }
    }

    /// Tap on the bloodstream of the physical model.
    func bloodstreamTapped() {
        guard step == .intro else { return }
        overlay.tapTarget.isEnabled = false
        overlay.setStreamVisible(false)      // fades out; it does not come back until "Start again"
        setStartPromptVisible(false)
        if let jump = Config.debugJumpTo, debugJump(to: jump) { return }   // TESTING ONLY (Config.debugJumpTo)
        enterMeetCell()
    }

    /// TESTING ONLY (Config.debugJumpTo): puts a red blood cell on the stage and jumps to a later scene.
    private func debugJump(to target: JourneyStep) -> Bool {
        guard target == .aging || target == .recycling else { return false }
        warmUpCell?.container.removeFromParent()
        warmUpCell = nil
        let cell = library.redBloodCell()
        setLook(cell, .withoutOxygen, animated: false)
        place(cell, at: Layout.mainSlot)
        redBloodCell = cell
        if target == .aging {
            // Hidden for now: enterAging lets it travel to the spleen and fly out of the model there.
            cell.container.components.set(OpacityComponent(opacity: 0))
            overlay.showMarker(at: .lLung)
            enterAging()
        } else {
            calmIdle(cell)
            enterRecycling()
        }
        return true
    }
    /// Draws one red blood cell, far too small to see (about 0.3 mm), inside the model's heart while the
    /// intro runs. The first time a model is drawn, the Vision Pro prepares it on the GPU – that stall
    /// used to swallow the first flight. enterMeetCell removes it again.
    func warmUpRedBloodCell() {
        warmUpCell?.container.removeFromParent()
        let cell = library.redBloodCell()
        CellTextures.apply(.withOxygen, to: cell.body)   // same texture as the real cell
        let heartWorld = anatomyRoot.convert(position: AnatomyMap.p(.heart), to: nil)
        focusRoot.addChild(cell.container)               // not place(): it must not affect the task hint
        cell.container.position = focusRoot.convert(position: heartWorld, from: nil)
        cell.container.scale = SIMD3<Float>(repeating: 0.002)
        warmUpCell = cell
    }
    // MARK: - Meet the red blood cell

    func enterMeetCell() {
        step = .meetCell
        warmUpCell?.container.removeFromParent()   // the real cell takes over now
        warmUpCell = nil
        let cell = library.redBloodCell()
        setLook(cell, .withOxygen, animated: false)

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
        makeDraggable(cell)

        setMainLabel(StoryText.Labels.redBloodCell, on: cell)
        setPanel(StoryText.Panels.meetCell)   // startet das Voiceover

        // Start-Knopf erst zeigen, wenn das Voiceover fertig ist
        sequence { id in
            // kurz warten, bis die Stimme sicher angefangen hat
            guard await self.pause(0.5, id) else { return }
            // warten, solange gesprochen wird (bricht ab bei Neustart oder anderem Schritt)
            while VoiceGuide.shared.isSpeaking {
                guard await self.pause(0.2, id), self.step == .meetCell else { return }
            }
            guard self.step == .meetCell, let cell = self.redBloodCell else { return }
            self.showStartButton(below: cell)
        }
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
        let first = redBloodCell
        redBloodCell = nil
        if let first {
            detachUI(from: first)
            makeStatic(first)
        }
        // The pelvis lights up while the first cell flies into its bone marrow.
        highlight(.boneMarrow)
        speakEarly(StoryText.Panels.boneMarrow)   // ← NEU: Stimme startet jetzt, während die Zelle hineinfliegt
        let marrowWorld = anatomyRoot.convert(position: AnatomyMap.p(.rMarrow), to: nil)

        sequence { id in
            if let first {
                // The first red blood cell flies back into the body – into the bone marrow in the pelvis …
                await self.flyIntoModel(first, at: marrowWorld)
                first.container.removeFromParent()
                guard id == self.runID, self.step == .boneMarrow else { return }
            }
            // … and the developing cell comes out of the same spot.
            self.bringOutDevelopingCell(from: marrowWorld)
        }
    }

    /// The developing cell flies out of the bone marrow in the pelvis to the person and grows on the way.
    private func bringOutDevelopingCell(from marrowWorld: SIMD3<Float>) {
        let parts = library.developingCell()
        place(parts.cell, at: focusRoot.convert(position: marrowWorld, from: nil))
        var arrival = parts.cell.container.transform
        arrival.translation = Layout.mainSlot
        if parts.development == nil {
            // No development animation: the cell grows during the flight instead.
            parts.cell.container.scale = SIMD3<Float>(repeating: 0.01)
            arrival.scale = SIMD3<Float>(repeating: 1)
        }
        parts.cell.container.move(to: arrival, relativeTo: focusRoot,
                                  duration: Timing.developingCellFlight, timingFunction: .easeInOut)
        developingCell = parts.cell
        nucleus = parts.nucleus
        // Very subtle idle movement of the nucleus inside the cell.
        parts.nucleus.updateMotion {
            $0.rockAngle = 0.08    // turns about ±5° back and forth
            $0.rockSpeed = 0.45    // slowly, about one sway every 14 seconds
            $0.hover = 0.0015      // floats 1.5 mm up and down
        }
        overlay.showMarker(at: .rMarrow)

        // The label appears once the cell has arrived, so it doesn't fly along from the pelvis.
        let arrivingCell = parts.cell
        sequence { id in
            guard await self.pause(Timing.developingCellFlight, id),
                  self.step == .boneMarrow, self.developingCell === arrivingCell else { return }
            self.setMainLabel(StoryText.Labels.erythroblast, on: arrivingCell)
        }

        if let development = parts.development {
            // The cell develops (grows) during and after its flight; the story continues once its shell has settled.
            develop(development, nucleus: parts.nucleus) { [weak self] in
                guard let self else { return }
                // Settled: the cell (with its nucleus) can be held and turned until the story goes on.
                self.allowLookAt(arrivingCell, returningTo: Layout.mainSlot, carrying: [parts.nucleus])
                self.setPanel(StoryText.Panels.boneMarrow)
            }
        } else {
            allowLookAt(parts.cell, returningTo: Layout.mainSlot, carrying: [parts.nucleus])
            setPanel(StoryText.Panels.boneMarrow)
        }
    }

    /// The cell develops: the shell and its nucleus grow together from nothing to full size (same time,
    /// same curve) and fade in, while the shell plays its development from Blender. When that is done,
    /// the shell's subtle endless wobble takes over and `done` runs.
    private func develop(_ development: ShellDevelopment, nucleus: StageItem,
                         then done: @escaping @MainActor () -> Void) {
        // Both grow until the pop frame of the (faster) development, so they reach full size – and pop –
        let grow = Float((Timing.shellPopFrame - Timing.shellStartFrame)
                         / (Timing.shellAnimationFPS * Timing.shellEarlySpeed))
        // The shell grows calmly and turns half a round. The nucleus tumbles one and a half times the
        // other way, grows in soft pulses and squashes and stretches a little. Both come to rest exactly
        // at full size.
        let shellGrow = GrowComponent(target: development.growing.scale, duration: grow,
                                      finalOrientation: development.growing.orientation, spin: .pi)
        var nucleusGrow = GrowComponent(target: nucleus.container.scale, duration: grow,
                                        finalOrientation: nucleus.container.orientation, spin: -.pi * 3)
        nucleusGrow.axis = simd_normalize(SIMD3<Float>(0.6, 1, -0.3))
        nucleusGrow.pulses = 3
        nucleusGrow.pulseAmount = 0.12
        nucleusGrow.squash = 0.08

        for (entity, growth) in [(development.growing, shellGrow), (nucleus.container, nucleusGrow)] {
            entity.components.set(growth)
            entity.scale = entity.scale * 0.001
            entity.components.set(OpacityComponent(opacity: 0))
            entity.components.set(FadeComponent(target: 1, speed: 1 / 0.4, disableWhenHidden: false))
        }
        // The nucleus jiggles while the shell is still wobbling and calms down as the shell settles.
        nucleus.updateMotion { $0.wiggle = Float(Timing.nucleusDevelopJiggle) }
        let calmStart = max(development.duration - Timing.shellSettleSeconds, 0)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(calmStart))
            let steps = 40
            for step in 1...steps {
                try? await Task.sleep(for: .seconds(Timing.shellSettleSeconds / Double(steps)))
                guard self.step == .boneMarrow else { return }
                let left = 1 - Double(step) / Double(steps)
                nucleus.updateMotion { $0.wiggle = Float(Timing.nucleusDevelopJiggle * left * left) }
            }
        }
        let id = runID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(development.duration))
            // Back in its rest shape with the same material and normals: the normal shell with its
            // subtle endless wobble takes over, invisibly.
            development.shell.isEnabled = true
            if let animated = development.loopAnimated, let loop = development.loopAnimation {
                animated.playAnimation(loop.repeat())
            }
            development.growing.removeFromParent()
            guard id == self.runID, self.step == .boneMarrow else { return }
            done()
        }
    }

    /// "Next" button in the text panel.
    func continueTapped() {
        switch step {
        case .boneMarrow:
            // If the cell is being held, the story waits until it is let go and back in its place.
            sequence { id in
                guard await self.endLookAt(id), self.step == .boneMarrow else { return }
                self.enterAddHemoglobin()
            }
        case .cycleRepeats:
            showSkipButton(false)   // SKIP: Knopf weg, egal ob übersprungen oder automatisch weiter
            enterAging()
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
            self.setLook(newCell, .withoutOxygen, animated: false)
            self.place(newCell, at: Layout.mainSlot)
            self.remove(cell, duration: 0.8)
            self.developingCell = nil
            self.hemoglobinFill = nil
            self.popIn(newCell, duration: 0.9)
            self.calmIdle(newCell)
            self.redBloodCell = newCell
            // Born and facing the person: it can be held and turned until the vessel scene starts.
            self.allowLookAt(newCell, returningTo: Layout.mainSlot)
            self.setMainLabel(StoryText.Labels.youngRedBloodCell, on: newCell)
            self.setPanel(StoryText.Panels.cellBorn)

            guard await self.pause(Timing.afterBirth, id) else { return }
            // Only change to the vessel scene once the voice has finished the "cellBorn" line, so the vessel
            // appears exactly when the next line begins ("Now that it is ready …").
            while VoiceGuide.shared.isSpeaking {
                guard await self.pause(0.2, id) else { return }
            }
            // If the cell is being held, wait until it is let go and back in its place.
            guard await self.endLookAt(id) else { return }
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
            // Inside the anatomy model, out of sight: the cell gets its normal model back.
            if let scene = self.squeezeScene {
                scene.detach(from: cell)
                self.squeezeScene = nil
            }
            guard id == self.runID else { return }
            self.highlight(nil)
            await self.overlay.travel(.marrowToLungs, duration: Timing.travelToLungs,
                                      speed: Timing.marrowToLungsSpeed)
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
        setLook(cell, .withOxygen, animated: true)
        interactionLocked = true

        sequence { id in
            guard await self.pause(1.4, id) else { return }
            self.interactionLocked = false
            self.enterPump(toOrgans: true)
        }
    }

    // MARK: - Heart pumps (5 taps)
    /// Waits until the recording `clip` has played `cue` seconds (e.g. the moment it says "bright red").
    /// If earlier lines are still in the voice queue, it first waits for this recording to start.
    /// With the synthetic voice (no recording) it waits until everything has been spoken.
    /// Returns false if the story was restarted meanwhile.
    func waitForVoice(clip: String, cue: TimeInterval, _ id: Int) async -> Bool {
        guard await pause(0.3, id) else { return false }   // let the voice start first
        var heard = false
        while VoiceGuide.shared.isSpeaking {
            if let time = VoiceGuide.shared.clipTime(of: clip) {
                heard = true
                if time >= cue { return true }
            } else if heard {
                return true   // this recording has already ended
            }
            guard await pause(0.1, id) else { return false }
        }
        return true
    }
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
        }
        setPanel(toOrgans ? StoryText.Panels.pumpToOrgans : StoryText.Panels.pickUpCO2)

        sequence { id in
            // The cell stays until the recording says "…now bright red." (to the organs) or "…now dark red."
            // (back to the lungs, with the CO₂) – Timing.brightRedCue / darkRedCue in the recordings.
            guard await self.waitForVoice(clip: toOrgans ? "voice_pumpToOrgans" : "voice_pickUpCO2",
                                          cue: toOrgans ? Timing.brightRedCue : Timing.darkRedCue,
                                          id) else { return }
            if !toOrgans { self.setSecondaryLabel(nil, on: nil) }   // the CO₂ label stays until the cell flies off
            await self.flyIntoModel(cell, at: self.overlay.startPosition(of: route))
            guard id == self.runID else { return }
            // The heart of the anatomy model becomes the button; it only beats when tapped.
            self.overlay.stream.autoBeat = false
            self.highlight(nil)
            self.overlay.showHeartModel(at: self.heartPopOutPosition())
            self.overlay.setHeartTappable(true)
            self.showHeartCounter()
            self.interactionLocked = false
        }
    }

    /// Tap on the heart of the anatomy model (or on the counter next to it).
    func heartTapped() {
        guard step == .pumpToOrgans || step == .pumpToLungs, showsHeart, heartBeats < requiredHeartBeats,
              !waitingForVoice else { return }   // erst pumpen, wenn der TaskHint da ist
        heartBeats += 1
        overlay.beatHeart()
        overlay.advance(to: Float(heartBeats) / Float(requiredHeartBeats), duration: Timing.heartStep)

        guard heartBeats == requiredHeartBeats else { return }
        let toOrgans = step == .pumpToOrgans
        overlay.setHeartTappable(false)
        sequence { id in
            await self.overlay.waitForMarker()   // constant speed: wait until the cell has arrived
            guard await self.pause(0.3, id) else { return }
            self.hideHeartCounter()
            self.overlay.hideHeartModel()
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
            // The oxygen has left the red blood cell: it turns dark red now, while the CO₂ is on its way.
            self.setLook(cell, .withoutOxygen, animated: true, duration: 1.6)
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
        labelledItems.remove(StoryText.Labels.carbonDioxide.title)   // shown in the organs already – show it again here
        setSecondaryLabel(StoryText.Labels.carbonDioxideExhale, on: waste)
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
            self.setLook(cell, .withOxygen, animated: true)
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
            //self.overlay.loop(.fullCircuit, lapDuration: Timing.lapDuration)
            // The lap plus the way to the spleen takes as long as the two voice lines: cycleRepeats (at least
            // 5 s – the auto-continue delay) and agingIntro, which ends with "…leads to the spleen."
            let cycleVoice = VoiceGuide.shared.clipDuration("voice_cycleRepeats") ?? 9
            let agingVoice = VoiceGuide.shared.clipDuration("voice_agingIntro") ?? 16
            self.overlay.loopFinalBodyCycle(lapDuration: max(cycleVoice, 5) + agingVoice - Timing.agingEarlyArrival)
            self.interactionLocked = false
            self.setPanel(StoryText.Panels.cycleRepeats)
            //self.showSkipButton(true)   // SKIP: wer nicht warten will, kann hier weiter tippen
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
        setLook(cell, .withoutOxygen, animated: false)

        sequence { id in
            // The light finishes its lap through the body and reaches the spleen a little BEFORE the voice ends
            // ("…its path now leads to the spleen."), so the cell is already out when the next line starts.
            guard await self.pause(0.3, id) else { return }   // let the recording start
            let remaining = VoiceGuide.shared.clipRemaining(of: "voice_agingIntro") ?? Timing.travelToSpleen
            await self.overlay.finishLapAndTravel(.lungsToSpleen,
                                                  arrivingIn: remaining - Timing.agingEarlyArrival)
            guard id == self.runID else { return }
            // Should the voice be behind, wait until it is at the same point. Synthetic voice (no recording):
            // wait for "spleen" as before.
            let intro = VoiceGuide.shared.clipDuration("voice_agingIntro")
            let cue = intro.map { $0 - Timing.agingEarlyArrival } ?? .infinity
            guard await self.waitForVoice(clip: "voice_agingIntro", cue: cue, id) else { return }
            self.highlight(.spleen)

            // The old cell flies out of the model. On the way the spleen sinus grows in and the cell already
            // turns into its place in it – it lands ready to squeeze, with no stop-and-turn afterwards.
            let flight = Task { @MainActor in
                await self.flyOutOfModel(cell, from: self.overlay.markerWorldPosition, to: Layout.squeezeStart,
                                         label: StoryText.Labels.oldRedBloodCell)
            }
            guard await self.pause(Timing.flyToModel * 0.3, id) else { return }
            let scene = await self.showSqueezeVessel(for: cell, id, grow: false)   // hidden until the cell has landed
            if let scene {
                scene.attach(to: cell, duration: Timing.flyToModel * 0.75)
                // The next line follows "…leads to the spleen." with only the short gap between clips.
                self.speakEarly(StoryText.Panels.agingTry)
            }
            await flight.value
            guard id == self.runID else { return }
            // Landed at the entrance: only now the spleen sinus grows in around it.
            if let scene { self.growVessel(scene) }
            // The same squeeze as before – but the old cell can't get through (JourneyController+Squeeze.swift).
            await self.startAgingSqueeze(cell, scene: scene, id)
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
        makeStatic(cell)
        cell.stopIdleMotion()

        // 1. The capillary shrinks a little and fades away.
        if let capillary {
            move(capillary.container, to: capillary.container.position, scale: 0.85,
                 duration: Timing.recycleCapillaryFade)
            remove(capillary, duration: Timing.recycleCapillaryFade)
        }
        capillary = nil
        let scene = squeezeScene
        squeezeScene = nil

        sequence { id in
            // 2. The cell relaxes out of its squeezed shape and turns smoothly to face the person,
            //    then blends into its normal model (which faces the person the same way).
            if let scene {
                scene.faceFront(duration: 0.9)
                await scene.animate(to: scene.firstFrame, duration: 0.9, includeCapillary: false)
                guard id == self.runID else { return }
            }
            guard await self.pause(0.3, id) else { return }

            // 3. It dissolves (unchanged animation, see dissolve).
            self.dissolve(cell)
            guard await self.pause(Double(Config.dissolveDuration) + 0.4, id) else { return }
            self.enterFinished()
        }
    }

    private func dissolve(_ cell: StageItem) {
        detachUI(from: cell)
        makeStatic(cell)
        cell.container.stopAllAnimations()
        redBloodCell = nil

        let duration = Config.dissolveDuration
        // Dust in the cell's own colour (the old cell is tinted with Palette.rbcAged).
        let color = cell.currentColor.map {
            UIColor(red: CGFloat($0.x), green: CGFloat($0.y), blue: CGFloat($0.z), alpha: 1)
        } ?? Palette.rbcAged

        // The pieces drift around the cell and then fly into the spleen of the anatomy model,
        // where macrophages recycle old red blood cells.
        let spleen = anatomyRoot.convert(position: AnatomyMap.p(.spleen), to: nil)
        if Disintegrate.start(on: cell.container, duration: duration, into: spleen) {
            Disintegrate.addDust(for: cell, in: focusRoot, color: color, duration: duration, towards: spleen)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Double(duration) + 0.2))
                cell.container.removeFromParent()
            }
        } else {
            // The mesh can't be split: shrink and fade as before.
            move(cell.container, to: cell.container.position, scale: 0.2, duration: 1.2)
            remove(cell, duration: 1.2)
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

