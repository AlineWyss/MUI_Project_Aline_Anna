//
//  CellLabelView.swift
//  BloodCellJourney
//
//  Name label above a model with an (i) button. Tapping (i) opens the facts inside the same box;
//  the box grows upwards (its bottom edge stays above the model, see FollowComponent.Anchor.bottom).
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
            let holdText = controller.isHolding ? content.holdText : nil
            let showsFacts = holdText == nil && controller.infoCard == content
            VStack(alignment: .leading, spacing: 14) {
                header(content, holdText: holdText, showsFacts: showsFacts)
                if showsFacts {
                    facts(content)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, showsFacts ? 20 : 12)
            .frame(width: showsFacts ? 360 : nil, alignment: .leading)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: holdText)
            .animation(.easeInOut(duration: 0.3), value: showsFacts)
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
                Button {
                    controller.toggleInfo(for: slot)
                } label: {
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
        VStack(alignment: .leading, spacing: 10) {
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
