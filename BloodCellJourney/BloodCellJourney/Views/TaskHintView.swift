//
//  TaskHintView.swift
//  BloodCellJourney
//
//  Created by wyss aline on 11.10.2026.
//
//  Die Aufgabe ("Zieh das Hämoglobin in die Zelle …") als Label UNTER dem
//  Modell, mit dem die Person gerade etwas tun soll.
//  Der Text ist derselbe wie bisher im Textfeld rechts (panel.hint).
//

import SwiftUI

struct TaskHintView: View {
    let controller: JourneyController

    var body: some View {
        // Während die Person ein Objekt hält, wird die Aufgabe ausgeblendet –
        // sie weiss dann ja schon, was zu tun ist (das Namens-Label zeigt
        // in diesem Moment den holdText).
        if let hint = controller.panel?.hint, !controller.isHolding {
            Label(hint, systemImage: "hand.pinch.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(uiColor: Palette.taskHint))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)                              // lange Texte umbrechen
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .transition(.opacity)
        }
    }
}
