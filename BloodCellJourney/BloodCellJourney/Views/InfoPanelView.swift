//
//  InfoPanelView.swift
//  BloodCellJourney
//
//  The text panel on the right: what is happening and what to do next.
//  (The facts behind (i) open inside the label itself, see CellLabelView.)
//

import SwiftUI

struct InfoPanelView: View {
    let controller: JourneyController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let panel = controller.panel {
                VStack(alignment: .leading, spacing: 14) {
                    Text(panel.title)
                        .font(.title.weight(.bold))
                    Text(panel.body)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = panel.hint {
                        Label(hint, systemImage: "hand.pinch.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let title = panel.continueTitle {
                        Button {
                            controller.continueTapped()
                        } label: {
                            Label(title, systemImage: "arrow.right")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .padding(.top, 4)
                    }
                }
                .padding(32)
                .frame(width: 520, alignment: .leading)
                .glassBackgroundEffect()
                .id(panel.id)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: controller.panel)
    }
}
