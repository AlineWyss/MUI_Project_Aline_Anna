//
//  AttachmentSlot.swift
//  BloodCellJourney
//
//  A place in the scene where a SwiftUI view (text panel, label, button, end screen) appears.
//
//  Why a new entity every time: on visionOS 26 a SwiftUI attachment (ViewAttachmentComponent) that
//  was hidden once ignores taps when it comes back (Apple bug FB20792470). Apple names disabling or
//  removing the entity as triggers. In this app the attachments were only emptied (their view showed
//  nothing), yet after "Start again" the Start button below the cell no longer reacted – most likely
//  the same bug. First appearances always worked, so every appearance now gets a brand-new entity and
//  hiding removes the old one for good. An entity is never disabled, re-added or shown a second time.
//

import RealityKit
import SwiftUI

@MainActor
final class AttachmentSlot {
    private let name: String
    private let parent: Entity
    private let makeView: () -> AnyView

    /// The entity while the view is shown, nil while it is hidden.
    private(set) var entity: Entity?

    /// - Parameters:
    ///   - parent: The entity the view is attached to (it moves with it).
    ///   - view: Builds the SwiftUI view. Called once per appearance.
    init<V: View>(name: String, parent: Entity, view: @escaping () -> V) {
        self.name = name
        self.parent = parent
        self.makeView = { AnyView(view()) }
    }

    var isShown: Bool { entity != nil }

    /// Shows the view and returns its entity. If it is already shown, the same entity is kept
    @discardableResult
    func show(at position: SIMD3<Float>? = nil, fadeIn: TimeInterval = 0.2) -> Entity {
        if let current = entity {
            if let position { current.position = position }
            return current
        }
        let created = Entity()
        created.name = name
        created.components.set(ViewAttachmentComponent(rootView: makeView()))
        if let position { created.position = position }
        // Fade-in. FadeSystem removes the OpacityComponent again when it reaches 1.
        // (Changing the opacity does not affect taps – only disabling/removing does.)
        created.components.set(OpacityComponent(opacity: 0))
        created.components.set(FadeComponent(target: 1, speed: Float(1 / max(fadeIn, 0.05)),
                                             disableWhenHidden: false))
        parent.addChild(created)
        entity = created
        return created
    }

    /// Hides the view (fadeOut > 0: it fades out first). Its entity is removed and never used again.
    func hide(fadeOut: TimeInterval = 0) {
        guard let old = entity else { return }
        entity = nil
        old.components.remove(FollowComponent.self)
        if fadeOut > 0 {
            old.components.set(FadeComponent(target: 0, speed: Float(1 / fadeOut), disableWhenHidden: false))
        }
        // Removed afterwards (at the earliest on the next run-loop turn, so a button inside it can finish
        // its action first).
        Task { @MainActor in
            if fadeOut > 0 { try? await Task.sleep(for: .seconds(fadeOut)) }
            old.removeFromParent()
        }
    }

    /// True if `candidate` is the entity of this slot.
    func owns(_ candidate: Entity) -> Bool {
        entity === candidate
    }
}
