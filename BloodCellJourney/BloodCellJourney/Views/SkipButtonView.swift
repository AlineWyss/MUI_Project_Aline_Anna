//
//  SkipButtonView.swift
//  BloodCellJourney
//
//  Created by wyss aline on 15.10.2026.
//
import SwiftUI

struct SkipButtonView: View {
    let controller: JourneyController

    var body: some View {
        Button {
            controller.skipTapped()
        } label: {
            // Text und Symbol – hier anpassen, z. B. "Continue" statt "Skip"
            Label("Skip", systemImage: "forward.fill")
                .font(.title3)
                .padding(.horizontal, 6)
        }
        .buttonBorderShape(.capsule)   // runde Pillenform wie die anderen Knöpfe in visionOS
    }
}

