//
//  TaskHintView.swift
//  BloodCellJourney
//
//  Die Aufgabe ("Zieh das Hämoglobin in die Zelle …") als Label UNTER dem
//  Modell, mit dem die Person gerade etwas tun soll.
//  Der Text ist derselbe wie bisher im Textfeld (panel.hint).
//  Wo das Label erscheint, entscheidet JourneyController.updateTaskHint().
//
//  NEU: Beim Herzpumpen steht hier kurz die Rückmeldung ("Too early …",
//  "In rhythm!") statt der Aufgabe (controller.pumpFeedback).
//

import SwiftUI

struct TaskHintView: View {
    let controller: JourneyController

    var body: some View {
        // Während die Person ein Objekt hält, wird die Aufgabe ausgeblendet –
        // sie weiss dann ja schon, was zu tun ist.
        if let hint = controller.panel?.hint, !controller.isHolding {
            // Rückmeldung beim Pumpen hat Vorrang vor der Aufgabe
            let text = controller.pumpFeedback ?? hint
            Label(text, systemImage: controller.pumpFeedback == nil ? "hand.pinch.fill" : "heart.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.yellow)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)                              // lange Texte umbrechen
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: controller.pumpFeedback)
                .transition(.opacity)
        }
    }
}
