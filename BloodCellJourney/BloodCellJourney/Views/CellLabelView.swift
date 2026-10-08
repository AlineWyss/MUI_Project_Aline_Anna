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

    /// Verbindet (i)-Symbol und Fakten-Karte zu einer Hover-Gruppe:
    /// Wird ein Teil angeschaut, reagieren beide.
    @Namespace private var hoverNamespace

    private var content: LabelContent? {
        slot == .main ? controller.mainLabel : controller.secondaryLabel
    }

    var body: some View {
        if let content {
            // Während ein Objekt gehalten wird, zeigt das Label einen anderen Text
            // und die Fakten werden nicht angeboten (wie bisher).
            let holdText = controller.isHolding ? content.holdText : nil
            let factsAvailable = !content.facts.isEmpty && holdText == nil

            VStack(alignment: .leading, spacing: 10) {

                // 1) Fakten-Karte (oben, unsichtbar bis zum Hinschauen)
                if factsAvailable {
                    facts(content)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 20)
                        .frame(width: 360, alignment: .leading)
                        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .hoverEffect(in: HoverEffectGroup(hoverNamespace)) { effect, isActive, _ in
                            // isActive = true, solange der Blick auf dem (i) liegt.
                            // delay: erst nach 0.3 s Hinschauen einblenden, damit die
                            // Karte bei einem flüchtigen Blick nicht aufflackert.
                            effect.animation(.easeOut(duration: 0.25).delay(isActive ? 0.3 : 0)) {
                                $0.opacity(isActive ? 1 : 0)
                                  .scaleEffect(isActive ? 1 : 0.94, anchor: .bottomLeading)
                            }
                        }
                }

                // 2) Namens-Label (unten, direkt über dem Modell)
                header(content, holdText: holdText, factsAvailable: factsAvailable)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .animation(.easeInOut(duration: 0.25), value: holdText)
        }
    }

    private func header(_ content: LabelContent, holdText: String?, factsAvailable: Bool) -> some View {
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
            if factsAvailable {
                // Das (i) bleibt ein Button, weil visionOS Hover-Effekte auf
                // Buttons zuverlässig auslöst. Die Aktion ist bewusst leer:
                // Die Fakten erscheinen durch Hinschauen, nicht durch Klicken.
                Button {
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .buttonBorderShape(.circle)
                // Gleiche Hover-Gruppe wie die Fakten-Karte, mit dem
                // üblichen Aufleuchten des Symbols
                .hoverEffect(.highlight, in: HoverEffectGroup(hoverNamespace))
                .accessibilityLabel("\(StoryText.Buttons.moreAbout) \(content.title)")
            }
        }
    }

    private func facts(_ content: LabelContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
