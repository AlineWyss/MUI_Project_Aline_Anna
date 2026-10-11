//
//  InfoPanelView.swift
//  BloodCellJourney
//
//  NEU: Hier wird nichts mehr angezeigt.
//  • Die Textbox ist weg; die gelbe Aufgabe steht unter dem 3D-Objekt (TaskHintView).
//  • Der "Weiter"-Knopf ist weg; der Ablauf geht automatisch weiter
//    (siehe JourneyController.setPanel).
//  Die Datei bleibt bestehen, weil JourneyController sie noch verwendet.
//

import SwiftUI

struct InfoPanelView: View {
    let controller: JourneyController

    var body: some View {
        EmptyView()
    }
}
