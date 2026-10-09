//
//  JourneyController.swift
//  BloodCellJourney
//
//  Owns the scene and runs the story. The steps are in JourneyController+Steps.swift,
//  drag & tap handling in JourneyController+Interaction.swift.
//
//  Scene graph (world space):
//    root
//     ├ anatomyRoot  – follows the physical model (object tracking) or holds the virtual copy:
//     │   ├ overlay      blood stream, organ outlines, yellow marker
//     │   └ heartCounter "Tap the heart" counter next to the model's heart while pumping
//     └ focusRoot    – the stage for the cells, labels, Start button, text panel and end screen.
//                      It sits at a fixed spot next to the anatomy model (Layout.focusOffsetFromModel),
//                      not where the person happened to stand when the experience started.
//

import Foundation
import Observation
import RealityKit
import Spatial
import SwiftUI
import UIKit

@MainActor
@Observable
final class JourneyController {

    // MARK: - UI state (read by the SwiftUI views)

    var step: JourneyStep = .searching
    var panel: PanelContent?
    var mainLabel: LabelContent?
    var secondaryLabel: LabelContent?
    /// The label whose facts are open (tapped (i)); the facts appear inside that label.
    var infoCard: LabelContent?
    /// True while the person holds a model.
    var isHolding = false
    var heartBeats = 0
    let requiredHeartBeats = Timing.requiredHeartBeats
    var message: MessageContent? = StoryText.Messages.loading
    var showsStartPrompt = false
    var showsStartButton = false
    var showsHeart = false
    var showsFinalPanel = false

    // MARK: - Scene

    let root = Entity()
    let anatomyRoot = Entity()
    let focusRoot = Entity()
    let overlay = AnatomyOverlay()
    let library = ModelLibrary()
    let tracking = TrackingService()

    // SwiftUI views in the scene (created in init, see AttachmentSlot for why each appearance
    // gets a new entity).
    @ObservationIgnored var panelSlot: AttachmentSlot!
    @ObservationIgnored var mainLabelSlot: AttachmentSlot!
    @ObservationIgnored var secondaryLabelSlot: AttachmentSlot!
    @ObservationIgnored var startButtonSlot: AttachmentSlot!
    @ObservationIgnored var heartSlot: AttachmentSlot!
    @ObservationIgnored var startPromptSlot: AttachmentSlot!
    @ObservationIgnored var messageSlot: AttachmentSlot!
    @ObservationIgnored var finalPanelSlot: AttachmentSlot!

    // MARK: - Stage items

    @ObservationIgnored var redBloodCell: StageItem?
    @ObservationIgnored var developingCell: StageItem?
    @ObservationIgnored var nucleus: StageItem?
    @ObservationIgnored var hemoglobin: StageItem?
    @ObservationIgnored var oxygen: StageItem?
    @ObservationIgnored var carbonDioxide: StageItem?
    @ObservationIgnored var bodyCell: StageItem?
    @ObservationIgnored var capillary: StageItem?
    @ObservationIgnored var hemoglobinFill: Entity?

    // MARK: - Interaction state

    struct DragSession {
        let item: StageItem
        let startPosition: SIMD3<Float>
        let startLocation: SIMD3<Float>
        /// Identifies the gesture; a new start location means the old gesture was cancelled.
        let gestureStart: Point3D
        var blocked = false
    }

    @ObservationIgnored var draggables: [ObjectIdentifier: StageItem] = [:]
    @ObservationIgnored var drag: DragSession?
    /// The squeeze animation from Blender while a cell is pushed into the capillary (young and old cell).
    @ObservationIgnored var squeezeScene: SqueezeScene?
    @ObservationIgnored var squeezeDone = false
    @ObservationIgnored var agingAttempts = 0
    @ObservationIgnored var interactionLocked = false
    /// Titles of the items whose label was already shown in this run (labels appear only once per item).
    @ObservationIgnored var labelledItems: Set<String> = []

    /// Increases on every restart; running sequences stop when it changes.
    @ObservationIgnored var runID = 0
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private var hasAnatomyPose = false
    private var modelLoadError: String?
    @ObservationIgnored private var isStartingVirtualModel = false
    @ObservationIgnored private var virtualAnatomy: Entity?

    /// Where the focus area was placed, relative to the anatomy model (see placeFocusArea).
    private struct FocusPlacement {
        /// The model's pose when the focus area was placed.
        var modelPosition: SIMD3<Float>
        var modelYaw: Float
        /// The focus area in the model's directions (turn around the vertical axis only).
        var offset: SIMD3<Float>
        var relativeYaw: Float
    }
    @ObservationIgnored private var focusPlacement: FocusPlacement?
    @ObservationIgnored private var isWaitingToFollowModel = false

    /// With the physical model (object tracking) or with a virtual copy of it.
    private(set) var mode: ExperienceMode

    init(mode: ExperienceMode) {
        self.mode = mode
        root.name = "JourneyRoot"
        anatomyRoot.name = "AnatomyAnchor"
        focusRoot.name = "FocusArea"
        root.addChild(anatomyRoot)
        root.addChild(focusRoot)
        anatomyRoot.addChild(overlay.root)
        anatomyRoot.isEnabled = false
        // Until the head position is known, put the focus area roughly in front of the person.
        focusRoot.position = SIMD3<Float>(0, 1.25, -0.8)
        makeAttachmentSlots()
    }

    // MARK: - Lifecycle

    /// Builds the scene. Called once from the RealityView.
    func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true

        overlay.build()
        showMessage(StoryText.Messages.loading)
        keepMessageInFrontWhileSearching()

        do {
            try await library.load()
            // Read the baked squeeze animation now, so the squeeze step starts without a hitch.
            _ = try? SqueezeAnimation.shared()
        } catch {
            modelLoadError = error.localizedDescription
            showMessage(StoryText.Messages.modelsFailed(error.localizedDescription))
            return
        }

        switch mode {
        case .physicalModel:
            updateSearchMessage()
        case .virtualModel:
            await startVirtualModel()
        }
    }

    /// Runs ARKit until the immersive space closes.
    /// Without the physical model only world tracking runs (head position), and this returns right away.
    func runTracking() async {
        await tracking.startWorldTracking()
        guard mode == .physicalModel else { return }
        await tracking.runObjectTracking { [weak self] transform, isTracked in
            self?.objectPoseChanged(transform, isTracked: isTracked)
        }
        updateSearchMessage()
    }

    func shutDown() {
        runID += 1
        tracking.stop()
        // The SwiftUI views hold the controller; removing them lets the closed scene be freed.
        attachmentSlots.forEach { $0.hide() }
    }

    /// Message while looking for the physical model (or why it can't be found).
    private func updateSearchMessage() {
        guard mode == .physicalModel, step == .searching else { return }
        if let modelLoadError {
            showMessage(StoryText.Messages.modelsFailed(modelLoadError))
            return
        }
        guard library.isLoaded else {
            showMessage(StoryText.Messages.loading)
            return
        }
        switch tracking.status {
        case .unsupported: showMessage(StoryText.Messages.unsupported)
        case .notAuthorized: showMessage(StoryText.Messages.notAuthorized)
        case .missingReferenceObject: showMessage(StoryText.Messages.missingReferenceObject)
        case .failed(let reason): showMessage(StoryText.Messages.failed(reason))
        case .idle, .running: showMessage(StoryText.Messages.searching)
        }
    }

    // MARK: - Without the physical model

    /// The "Continue without the model" button is offered while searching, unless the models failed to load.
    var canContinueWithoutModel: Bool {
        mode == .physicalModel && step == .searching && modelLoadError == nil
    }

    /// Button in the search message: the physical model is not there or not recognised.
    func continueWithoutPhysicalModel() {
        guard canContinueWithoutModel else { return }
        mode = .virtualModel
        tracking.stopObjectTracking()
        // If the models are still loading, prepare() starts the virtual model when it is done.
        if library.isLoaded {
            Task { await self.startVirtualModel() }
        }
    }

    /// Shows a see-through copy of the anatomy model front-left of the person and starts the story.
    private func startVirtualModel() async {
        guard !isStartingVirtualModel, step == .searching else { return }
        isStartingVirtualModel = true
        showMessage(StoryText.Messages.preparingVirtual)

        do {
            let model = try await library.virtualAnatomy()
            // See-through, and drawn after the bloodstream so the vessels inside stay visible.
            model.forEachModelEntity { $0.components.set(OpacityComponent(opacity: Config.virtualModelOpacity)) }
            overlay.drawAfterOverlay(model)
            anatomyRoot.addChild(model)
            virtualAnatomy = model
        } catch {
            modelLoadError = error.localizedDescription
            showMessage(StoryText.Messages.modelsFailed(error.localizedDescription))
            isStartingVirtualModel = false
            return
        }

        // Give world tracking up to two seconds to report the head position.
        for _ in 0..<20 where tracking.devicePose() == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        hasAnatomyPose = true
        anatomyRoot.isEnabled = true
        if step == .searching {
            enterIntro()   // also places the virtual model
        }
    }

    /// Puts the virtual copy where the physical model would stand: the stage (focus area) ends up right
    /// in front of the person, and the copy sits at Layout.focusOffsetFromModel from it – slightly to the
    /// left and further back. Same arrangement as with the physical model.
    func placeVirtualAnatomy() {
        let stage = focusPoseInFrontOfPerson()
        // The scan faces +z; it faces the same way as the stage (towards the person).
        let rotation = Self.yawRotation(stage.yaw)
        var transform = Transform()
        transform.rotation = rotation
        transform.translation = stage.position - rotation.act(Layout.focusOffsetFromModel)
        anatomyRoot.transform = transform
    }

    // MARK: - With the physical model

    private func objectPoseChanged(_ transform: simd_float4x4, isTracked: Bool) {
        // Ignore the physical model once the person chose to continue without it.
        // Keep the last good pose when the model is briefly lost.
        guard mode == .physicalModel, isTracked else { return }
        anatomyRoot.transform = Transform(matrix: transform)
        followModelIfMoved()
        if !hasAnatomyPose {
            hasAnatomyPose = true
            anatomyRoot.isEnabled = true
            Task { await self.addAlignmentGhostIfNeeded() }
        }
        if step == .searching && library.isLoaded {
            enterIntro()
        }
    }

    private func addAlignmentGhostIfNeeded() async {
        guard Config.showAlignmentGhost,
              let url = tracking.referenceObject?.usdzFile,
              let ghost = try? await Entity(contentsOf: url) else { return }
        MaterialTools.makeGhost(ghost)
        overlay.drawAfterOverlay(ghost)
        overlay.root.addChild(ghost)
    }

    /// While searching, the hint follows the person's view (there is no model to place it next to yet).
    private func keepMessageInFrontWhileSearching() {
        let id = runID
        Task { @MainActor in
            var placedOnce = false
            while self.step == .searching && id == self.runID {
                let placed = self.placeFocusAreaInFrontOfPerson(animated: placedOnce)
                placedOnce = placedOnce || placed
                try? await Task.sleep(for: .seconds(placedOnce ? 1.0 : 0.2))
            }
        }
    }

    // MARK: - Focus area

    /// Head position and horizontal viewing direction. Without head tracking (e.g. Simulator)
    /// it assumes a person standing at the origin, looking forward.
    func viewpoint() -> (head: SIMD3<Float>, forward: SIMD3<Float>, isTracked: Bool) {
        guard let pose = tracking.devicePose() else {
            return (Layout.fallbackHeadPosition, SIMD3<Float>(0, 0, -1), false)
        }
        let head = SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
        var forward = SIMD3<Float>(-pose.columns.2.x, 0, -pose.columns.2.z)
        if simd_length(forward) < 0.001 { forward = SIMD3<Float>(0, 0, -1) }
        return (head, simd_normalize(forward), true)
    }

    /// Places the focus area (the stage for cells, labels and text) straight in front of the person,
    /// facing them, so the 3D models and text are centred in the view and easy to read – not off to the
    /// side. It still stays attached to the anatomy model: the spot is remembered in the model's own
    /// directions, so the stage follows if the model is bumped (followModelIfMoved). It is turned
    /// towards the person once, when it is placed (start of every round); it does not keep turning while
    /// the person moves.
    /// Needs the model's pose (anatomyRoot): called from enterIntro, after the model was found
    /// (or the virtual copy was placed).
    func placeFocusArea(animated: Bool = false) {
        let stage = focusPoseInFrontOfPerson()
        let model = modelPose()
        // Remember where the stage sits relative to the model (in the model's own directions), so it can
        // follow the model if someone bumps it.
        let offset = Self.yawRotation(-model.yaw).act(stage.position - model.position)
        moveFocusArea(to: stage.position, yaw: stage.yaw, animated: animated)
        focusPlacement = FocusPlacement(modelPosition: model.position,
                                        modelYaw: model.yaw,
                                        offset: offset,
                                        relativeYaw: stage.yaw - model.yaw)
    }

    /// The physical model moved (someone bumped it): the focus area moves with it, keeping the same
    /// position and turn relative to the model. Small changes are tracking noise and are ignored
    /// (Layout.modelMoveTolerance / modelTurnTolerance). Never moves the stage while something is
    /// being dragged – it waits until the person lets go.
    private func followModelIfMoved() {
        guard step != .searching, let placement = focusPlacement else { return }
        let model = modelPose()
        let moved = simd_distance(model.position, placement.modelPosition) > Layout.modelMoveTolerance
        let turned = abs(Self.angleBetween(model.yaw, placement.modelYaw))
            > Layout.modelTurnTolerance * .pi / 180
        guard moved || turned else { return }
        guard drag == nil else {
            followModelAfterDrag()
            return
        }
        let position = model.position + Self.yawRotation(model.yaw).act(placement.offset)
        moveFocusArea(to: position, yaw: model.yaw + placement.relativeYaw, animated: true)
        focusPlacement?.modelPosition = model.position
        focusPlacement?.modelYaw = model.yaw
    }

    private func followModelAfterDrag() {
        guard !isWaitingToFollowModel else { return }
        isWaitingToFollowModel = true
        Task { @MainActor in
            while self.drag != nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            self.isWaitingToFollowModel = false
            self.followModelIfMoved()
        }
    }

    /// Places the focus area in front of the person, facing them. Only used while searching for the
    /// physical model (the hint must be visible before the model is known).
    /// Returns false if the head position is unknown (a default position is used then).
    @discardableResult
    func placeFocusAreaInFrontOfPerson(animated: Bool = false) -> Bool {
        let stage = focusPoseInFrontOfPerson()
        moveFocusArea(to: stage.position, yaw: stage.yaw, animated: animated)
        return stage.isTracked
    }

    /// Layout.focusDistance in front of the person's eyes, Layout.focusDrop below them, facing the person.
    private func focusPoseInFrontOfPerson() -> (position: SIMD3<Float>, yaw: Float, isTracked: Bool) {
        let view = viewpoint()
        let position = view.head + view.forward * Layout.focusDistance - SIMD3<Float>(0, Layout.focusDrop, 0)
        return (position, atan2(-view.forward.x, -view.forward.z), view.isTracked)
    }

    /// The anatomy model's position (centre of its base) and its turn around the vertical axis.
    /// Any tilt from tracking is ignored, so the stage always stays level.
    private func modelPose() -> (position: SIMD3<Float>, yaw: Float) {
        let matrix = anatomyRoot.transform.matrix
        let position = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        // The scan faces +z.
        let front = SIMD3<Float>(matrix.columns.2.x, 0, matrix.columns.2.z)
        let yaw = simd_length(front) > 0.0001 ? atan2(front.x, front.z) : 0
        return (position, yaw)
    }

    private func moveFocusArea(to position: SIMD3<Float>, yaw: Float, animated: Bool) {
        var transform = Transform()
        transform.translation = position
        transform.rotation = Self.yawRotation(yaw)
        // Only the stage itself – models on it may be in the middle of their own animations.
        focusRoot.stopAllAnimations(recursive: false)
        if animated {
            focusRoot.move(to: transform, relativeTo: root, duration: 0.6, timingFunction: .easeInOut)
        } else {
            focusRoot.transform = transform
        }
    }

    private static func yawRotation(_ yaw: Float) -> simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }

    /// Smallest difference between two angles (radians), -π…π.
    private static func angleBetween(_ a: Float, _ b: Float) -> Float {
        var difference = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if difference > .pi { difference -= 2 * .pi }
        if difference < -.pi { difference += 2 * .pi }
        return difference
    }

    // MARK: - Attachments
    //
    // visionOS 26 bug (FB20792470): a SwiftUI attachment that was hidden once ignores taps when it
    // comes back. Each slot therefore creates a new entity every time its view appears and removes it
    // when it hides (see AttachmentSlot). Labels and the Start button follow their model with
    // FollowComponent.

    private func makeAttachmentSlots() {
        panelSlot = AttachmentSlot(name: "Panel", parent: focusRoot) { [unowned self] in
            InfoPanelView(controller: self)
        }
        mainLabelSlot = AttachmentSlot(name: "MainLabel", parent: focusRoot) { [unowned self] in
            CellLabelView(controller: self, slot: .main)
        }
        secondaryLabelSlot = AttachmentSlot(name: "SecondaryLabel", parent: focusRoot) { [unowned self] in
            CellLabelView(controller: self, slot: .secondary)
        }
        startButtonSlot = AttachmentSlot(name: "StartButton", parent: focusRoot) { [unowned self] in
            StartButtonView(controller: self)
        }
        // On the anatomy model, so it stays next to the model's heart.
        heartSlot = AttachmentSlot(name: "HeartCounter", parent: anatomyRoot) { [unowned self] in
            HeartCounterView(controller: self)
        }
        startPromptSlot = AttachmentSlot(name: "StartPrompt", parent: focusRoot) { [unowned self] in
            StartPromptView(controller: self)
        }
        messageSlot = AttachmentSlot(name: "Message", parent: focusRoot) { [unowned self] in
            MessageView(controller: self)
        }
        finalPanelSlot = AttachmentSlot(name: "FinalPanel", parent: focusRoot) { [unowned self] in
            FinalPanelView(controller: self)
        }
    }

    var attachmentSlots: [AttachmentSlot] {
        [panelSlot, mainLabelSlot, secondaryLabelSlot, startButtonSlot, heartSlot, startPromptSlot,
         messageSlot, finalPanelSlot]
    }

    // MARK: - UI helpers

    func showMessage(_ content: MessageContent?) {
        message = content
        if content != nil {
            messageSlot.show()
        } else {
            messageSlot.hide()
        }
    }

    func setPanel(_ content: PanelContent?) {
        panel = content
        if content != nil {
            panelSlot.show(at: Layout.panelSlot)
        } else {
            panelSlot.hide()
        }
    }

    func setMainLabel(_ content: LabelContent?, on item: StageItem?, height: Float? = nil) {
        let content = firstAppearance(content, current: mainLabel)
        mainLabel = content
        placeLabel(mainLabelSlot, shown: content != nil, on: item, height: height)
        dropStaleInfoCard()
    }

    func setSecondaryLabel(_ content: LabelContent?, on item: StageItem?, height: Float? = nil) {
        let content = firstAppearance(content, current: secondaryLabel)
        secondaryLabel = content
        placeLabel(secondaryLabelSlot, shown: content != nil, on: item, height: height)
        dropStaleInfoCard()
    }

    /// The label sits above its model with its bottom edge fixed, so it grows upwards when (i) opens the facts.
    private func placeLabel(_ slot: AttachmentSlot, shown: Bool, on item: StageItem?, height: Float?) {
        guard shown, let item else {
            slot.hide()
            return
        }
        let entity = slot.show()
        follow(entity, item.container,
               offset: SIMD3<Float>(0, height ?? (item.halfHeight + Layout.labelGap), 0),
               anchor: .bottom)
    }

    /// Each item's name label appears only the first time the item shows up in a run.
    /// Items are identified by the label title, so e.g. every "Red Blood Cell" label after the first is skipped.
    private func firstAppearance(_ content: LabelContent?, current: LabelContent?) -> LabelContent? {
        guard let content else { return nil }
        if content.title == current?.title { return content }   // same appearance, label already showing
        if labelledItems.contains(content.title) { return nil }
        labelledItems.insert(content.title)
        return content
    }

    /// Shows the Start button below a model (nil hides it).
    func showStartButton(below item: StageItem?) {
        showsStartButton = item != nil
        if let item {
            let entity = startButtonSlot.show()
            follow(entity, item.container,
                   offset: SIMD3<Float>(0, -(item.halfHeight + Layout.buttonGap), 0),
                   anchor: .top)
        } else {
            startButtonSlot.hide()
        }
    }

    /// Keeps an attachment (child of the focus area) next to `target` every frame.
    func follow(_ attachment: Entity, _ target: Entity, offset: SIMD3<Float>,
                anchor: FollowComponent.Anchor = .center) {
        let component = FollowComponent(target: target, offset: offset, anchor: anchor)
        attachment.components.set(component)
        if let parent = attachment.parent {
            attachment.position = FollowSystem.position(of: attachment, following: component, in: parent)
        }
    }

    func setStartPromptVisible(_ visible: Bool) {
        showsStartPrompt = visible
        if visible {
            startPromptSlot.show(at: Layout.startPromptSlot)
        } else {
            startPromptSlot.hide()
        }
    }

    private func dropStaleInfoCard() {
        guard let card = infoCard else { return }
        if card != mainLabel && card != secondaryLabel {
            infoCard = nil
        }
    }

    /// (i) button on a label.
    func toggleInfo(for slot: CellLabelView.Slot) {
        let content = slot == .main ? mainLabel : secondaryLabel
        if infoCard != nil && infoCard == content {
            infoCard = nil
        } else {
            infoCard = content
        }
    }

    /// Outlines an organ or body region on the anatomy model (nil = none).
    func highlight(_ zone: AnatomyMap.Zone?) {
        overlay.setZone(zone)
    }

    /// Shows the "Tap the heart" counter next to the heart of the anatomy model, on the side
    /// facing the person and the focus area, so it never covers the heart.
    func showHeartCounter() {
        showsHeart = true
        let heartWorld = anatomyRoot.convert(position: AnatomyMap.p(.heart), to: nil)
        let toPerson = horizontalDirectionToPerson(from: heartWorld)
        let personRight = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), toPerson))
        let position = heartWorld + toPerson * 0.08 + personRight * Layout.heartCounterSideOffset
            + SIMD3<Float>(0, 0.02, 0)
        let counter = heartSlot.show(at: anatomyRoot.convert(position: position, from: nil))
        counter.components.set(BillboardComponent())   // always turned towards the person
    }

    func hideHeartCounter() {
        showsHeart = false
        heartSlot.hide()
    }

    // MARK: - Attention: the cell travels inside the anatomy model

    /// The red blood cell in front of the person shrinks and flies into the anatomy model,
    /// where it continues as the yellow marker. Labels hide while it is away.
    func flyIntoModel(_ cell: StageItem, at worldPoint: SIMD3<Float>) async {
        setMainLabel(nil, on: nil)
        cell.stopIdleMotion()
        cell.container.stopAllAnimations()
        cell.container.components.remove(FadeComponent.self)
        cell.container.components.set(OpacityComponent(opacity: 1))
        move(cell.container, to: focusRoot.convert(position: worldPoint, from: nil),
             scale: Layout.cellScaleInModel, duration: Timing.flyToModel)
        try? await Task.sleep(for: .seconds(Timing.flyToModel * 0.8))
        cell.container.components.set(FadeComponent(target: 0, speed: 4, disableWhenHidden: false))
        try? await Task.sleep(for: .seconds(Timing.flyToModel * 0.25))
    }

    /// The red blood cell comes back out of the anatomy model to the focus area.
    func flyOutOfModel(_ cell: StageItem, from worldPoint: SIMD3<Float>, to slot: SIMD3<Float>,
                       label: LabelContent?) async {
        cell.container.stopAllAnimations()
        cell.container.position = focusRoot.convert(position: worldPoint, from: nil)
        cell.container.scale = SIMD3<Float>(repeating: Layout.cellScaleInModel)
        cell.container.components.set(OpacityComponent(opacity: 0))
        cell.container.components.set(FadeComponent(target: 1, speed: 4, disableWhenHidden: false))
        move(cell.container, to: slot, scale: 1, duration: Timing.flyToModel)
        try? await Task.sleep(for: .seconds(Timing.flyToModel + 0.05))
        if let label {
            setMainLabel(label, on: cell)
        }
    }

    func horizontalDirectionToPerson(from point: SIMD3<Float>) -> SIMD3<Float> {
        let head = viewpoint().head
        var direction = head - point
        direction.y = 0
        return simd_length(direction) > 0.01 ? simd_normalize(direction) : SIMD3<Float>(0, 0, 1)
    }

    // MARK: - Stage helpers

    func place(_ item: StageItem, at position: SIMD3<Float>) {
        focusRoot.addChild(item.container)
        item.container.position = position
    }

    func popIn(_ item: StageItem, duration: TimeInterval = Timing.pop) {
        var target = item.container.transform
        target.scale = SIMD3<Float>(repeating: 1)
        item.container.scale = SIMD3<Float>(repeating: 0.01)
        item.container.move(to: target, relativeTo: item.container.parent, duration: duration, timingFunction: .easeOut)
    }

    func move(_ entity: Entity, to position: SIMD3<Float>, scale: Float? = nil, duration: TimeInterval) {
        var target = entity.transform
        target.translation = position
        if let scale { target.scale = SIMD3<Float>(repeating: scale) }
        entity.move(to: target, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut)
    }

    /// Fades an item out and removes it.
    func remove(_ item: StageItem?, duration: TimeInterval = 0.5) {
        guard let item else { return }
        detachUI(from: item)
        makeStatic(item)
        fadeOutAndRemove(item.container, duration: duration)
    }

    func fadeOutAndRemove(_ entity: Entity, duration: TimeInterval) {
        entity.components.set(FadeComponent(target: 0, speed: Float(1 / max(duration, 0.05)), disableWhenHidden: true))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.15))
            entity.removeFromParent()
        }
    }

    /// Stops labels and the Start button from following an item that is about to be removed.
    func detachUI(from item: StageItem) {
        for entity in [mainLabelSlot.entity, secondaryLabelSlot.entity, startButtonSlot.entity].compactMap({ $0 }) {
            if let target = entity.components[FollowComponent.self]?.target, target.isInside(item.container) {
                entity.components.remove(FollowComponent.self)
            }
        }
    }

    func makeDraggable(_ item: StageItem) {
        let radius = max(item.radius, 0.035)
        item.container.components.set(CollisionComponent(shapes: [ShapeResource.generateSphere(radius: radius)]))
        item.container.components.set(InputTargetComponent())
        item.container.components.set(HoverEffectComponent())
        item.container.components.set(DraggableComponent())
        draggables[ObjectIdentifier(item.container)] = item
    }

    func makeStatic(_ item: StageItem) {
        item.container.components.remove(DraggableComponent.self)
        item.container.components.remove(InputTargetComponent.self)
        item.container.components.remove(CollisionComponent.self)
        item.container.components.remove(HoverEffectComponent.self)
        draggables[ObjectIdentifier(item.container)] = nil
        if drag?.item === item {
            drag = nil
            isHolding = false
        }
    }

    func setColor(_ item: StageItem, _ color: UIColor, animated: Bool, duration: Float = 1.2) {
        let target = color.rgba
        if animated, let from = item.currentColor {
            item.body.components.set(ColorTweenComponent(from: from, to: target, duration: duration))
        } else {
            item.body.components.remove(ColorTweenComponent.self)
            MaterialTools.setBaseColor(item.body, color)
        }
        item.currentColor = target
    }

    /// Attaches a molecule to the red blood cell so it travels with it.
    func bind(_ molecule: StageItem, to cell: StageItem, at offset: SIMD3<Float>, duration: TimeInterval = 0.5) {
        molecule.container.setParent(cell.motion, preservingWorldTransform: true)
        var target = Transform()
        target.translation = offset
        molecule.container.move(to: target, relativeTo: cell.motion, duration: duration, timingFunction: .easeOut)
    }

    func oxygenSlot(on cell: StageItem) -> SIMD3<Float> {
        SIMD3<Float>(cell.radius * 0.8, cell.radius * 0.55, 0.03)
    }

    func carbonDioxideSlot(on cell: StageItem) -> SIMD3<Float> {
        SIMD3<Float>(-cell.radius * 0.8, cell.radius * 0.55, 0.03)
    }

    /// Removes everything from the focus area and resets the interaction state.
    func clearStage() {
        let items: [StageItem?] = [redBloodCell, developingCell, nucleus, hemoglobin, oxygen, carbonDioxide, bodyCell, capillary]
        for case let item? in items {
            detachUI(from: item)
            makeStatic(item)
        }
        // Remove the models, but leave the SwiftUI views to their slots (hidden below).
        for child in Array(focusRoot.children) where !attachmentSlots.contains(where: { $0.owns(child) }) {
            child.removeFromParent()
        }
        redBloodCell = nil
        developingCell = nil
        nucleus = nil
        hemoglobin = nil
        oxygen = nil
        carbonDioxide = nil
        bodyCell = nil
        capillary = nil
        hemoglobinFill = nil

        draggables.removeAll()
        drag = nil
        isHolding = false
        interactionLocked = false
        squeezeScene = nil
        squeezeDone = false
        agingAttempts = 0
        heartBeats = 0

        setMainLabel(nil, on: nil)
        setSecondaryLabel(nil, on: nil)
        infoCard = nil
        setPanel(nil)
        showStartButton(below: nil)
        hideHeartCounter()
        setStartPromptVisible(false)
    }

    // MARK: - Sequences

    /// Runs timed story code. It stops at the next `pause` after a restart.
    func sequence(_ work: @escaping @MainActor (_ id: Int) async -> Void) {
        let id = runID
        Task { @MainActor in
            await work(id)
        }
    }

    /// Waits and returns false if the story was restarted in the meantime.
    func pause(_ seconds: Double, _ id: Int) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return id == runID
    }
}

extension Entity {
    /// Calls `body` for this entity and every descendant that renders a model.
    func forEachModelEntity(_ body: (Entity) -> Void) {
        if components.has(ModelComponent.self) {
            body(self)
        }
        for child in children {
            child.forEachModelEntity(body)
        }
    }

    /// True if this entity is `ancestor` or somewhere below it.
    func isInside(_ ancestor: Entity) -> Bool {
        var current: Entity? = self
        while let entity = current {
            if entity === ancestor { return true }
            current = entity.parent
        }
        return false
    }
}

