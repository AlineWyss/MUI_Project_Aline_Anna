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

    // Grösse des unsichtbaren Rahmens, in dem die Karte unten steht.
    // Breite = Breite der offenen Karte. Höhe = Platz nach oben für den Text.
    // Ist ein Text länger, einfach die Höhe vergrössern.
    private static let openWidth: CGFloat = 360
    private static let frameHeight: CGFloat = 420

    var body: some View {
        if let content {
            // Beim Greifen bleibt der Objektname stehen (kein anderer Text)
            let holdText: String? = nil
            let factsAvailable = !content.facts.isEmpty && holdText == nil
            let showsFacts = factsAvailable && controller.infoCard == content

            // EINE Karte: oben Name + Knopf, darunter (nur wenn offen) der Text
            VStack(alignment: .leading, spacing: 12) {
                header(content, holdText: holdText, showsFacts: showsFacts)
                if showsFacts {
                    facts(content)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, showsFacts ? 20 : 12)
            .frame(width: showsFacts ? Self.openWidth : nil, alignment: .leading)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .animation(.easeInOut(duration: 0.3), value: showsFacts)
            // Beim Greifen eines Objekts: Label ausblenden
            .opacity(controller.isHolding ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: controller.isHolding)
            // FESTER RAHMEN: Die Karte steht unten in der Mitte und wächst nur nach oben.
            // Der Rahmen selbst ist unsichtbar und ändert seine Grösse nie → die Unterkante springt nicht.
            .frame(width: Self.openWidth, height: Self.frameHeight, alignment: .bottom)
        }
    }
    
    private func header(_ content: LabelContent, holdText: String?, showsFacts: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
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
                if showsFacts {
                    Spacer(minLength: 0)
                }
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

    /// Der Text in der offenen Karte – ohne Aufzählungspunkt und ohne Trennlinie.
    private func facts(_ content: LabelContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(content.facts, id: \.self) { fact in
                Text(fact)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)   // Text darf umbrechen
            }
        }
    }
}
