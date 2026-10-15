//
//  CellLabelView.swift
//  BloodCellJourney
//
//  Name label above a model with an (i) symbol.
//
//  NEU: Die Fakten erscheinen beim HINSCHAUEN auf das (i), nicht mehr per Klick.
//
//  So funktioniert es:
//  • Die Fakten-Karte ist immer vorhanden, aber unsichtbar (Deckkraft 0).
//  • Sie liegt ÜBER dem Namens-Label. Weil das Label unten verankert ist
//    (FollowComponent.Anchor.bottom), bleibt der Name direkt über dem Modell.
//  • (i)-Symbol und Fakten-Karte gehören zur selben "Hover-Gruppe". Schaut man
//    auf das (i), blendet visionOS die Karte ein. Schaut man weg, verschwindet sie.
//  • Die App erfährt dabei nie, wohin der Nutzer schaut. Das berechnet visionOS
//    selbst (Datenschutz). Darum geht nur ein visueller Effekt, kein Layout-Wechsel.
//

import SwiftUI

struct CellLabelView: View {
    enum Slot {
        case main, secondary
    }

    let controller: JourneyController
    let slot: Slot

    private var content: LabelContent? {
        slot == .main ? controller.mainLabel : controller.secondaryLabel
    }

    var body: some View {
        if let content {
            // Beim Greifen bleibt der Objektname stehen (kein anderer Text)
            let holdText: String? = nil
            // Hat dieses Objekt überhaupt Fakten?
            let factsAvailable = !content.facts.isEmpty && holdText == nil
            // Ist die Karte gerade offen? (per Antippen auf das (i))
            let showsFacts = factsAvailable && controller.infoCard == content

            VStack(alignment: .center, spacing: 10) {

                // 1) Fakten-Karte (oben). Sie ist IMMER da, aber unsichtbar,
                //    solange sie zu ist. So bleibt das Namens-Label immer an derselben Stelle.
                if factsAvailable {
                    facts(content)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                        .frame(width: 360, alignment: .leading)
                        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .opacity(showsFacts ? 1 : 0)                                  // ein-/ausblenden
                        .scaleEffect(showsFacts ? 1 : 0.94, anchor: .bottom)  // leicht "aufploppen"
                        .allowsHitTesting(showsFacts)                                 // unsichtbar = nicht antippbar
                }

                // 2) Namens-Label (unten, direkt über dem Modell) – bewegt sich nie
                header(content, holdText: holdText, showsFacts: showsFacts)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            // Weiches Ein- und Ausblenden der Karte (wie beim Hover)
            .animation(.easeOut(duration: 0.25), value: showsFacts)
            .animation(.easeInOut(duration: 0.25), value: holdText)
            .opacity(controller.isHolding ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: controller.isHolding)
        }
    }
    private func header(_ content: LabelContent, holdText: String?, showsFacts: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .center, spacing: 2) {
                Text(holdText ?? content.title)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                if holdText == nil, let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if !content.facts.isEmpty && holdText == nil {
                // Wenn die Fakten offen sind, schiebt der Spacer das (x) nach rechts

                Button {
                    // Antippen öffnet bzw. schliesst die Fakten
                    controller.toggleInfo(for: slot)
                } label: {
                    // (i) wenn zu, (x) wenn offen
                    Image(systemName: showsFacts ? "xmark.circle.fill" : "info.circle")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .buttonBorderShape(.circle)
                .accessibilityLabel(showsFacts
                                    ? StoryText.Buttons.closeFacts
                                    : "\(StoryText.Buttons.moreAbout) \(content.title)")
            }
        }
    }

    private func facts(_ content: LabelContent) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Divider()
            ForEach(content.facts, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                    Text(fact)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
            }
        }
    }
}
