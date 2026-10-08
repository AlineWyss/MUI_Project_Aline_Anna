//
//  StoryText.swift
//  BloodCellJourney
//
//  All texts of the experience (English). Edit freely – nothing else depends on the wording.
//  Facts were checked against the sources listed in README.md.
//

import Foundation

/// Name label above a model, with optional facts behind the (i) button.
struct LabelContent: Equatable {
    var title: String
    var subtitle: String?
    /// Replaces the title while the person is holding something (instruction).
    var holdText: String?
    /// Shown in the text panel on the right when the (i) button is tapped.
    var facts: [String] = []
}

/// The text panel on the right.
struct PanelContent: Equatable {
    var id: String
    var title: String
    var body: String
    var hint: String?
    /// Title of a button that moves the story on (nil = no button).
    var continueTitle: String?
}

struct MessageContent: Equatable {
    var title: String
    var body: String
}

enum StoryText {

    enum Launch {
        static let title = "Blood Cell Journey"
        static let subtitle = "The life of a red blood cell"
        static let body = "With the anatomy model: stand so that it is slightly to your left, start, and look at it. Without it: a see-through virtual copy appears to your left instead."
        static let withModel = "Start with the anatomy model"
        static let withoutModel = "Start without the model"
        static let needsVisionPro = "Recognising the physical model needs Apple Vision Pro. Here you can start without the model."
        static let missingReferenceObject = "AnatomyModel.referenceobject is not in the app yet (see README). You can start without the model."
        static let failed = "The experience could not be opened. Please try again."
    }

    enum Messages {
        static let searching = MessageContent(
            title: "Look at the anatomy model",
            body: "Move your head slowly around the model until the bloodstream appears on it. No model here? Continue without it.")
        static let loading = MessageContent(
            title: "Loading…",
            body: "Preparing the cells.")
        static let preparingVirtual = MessageContent(
            title: "Preparing the virtual model…",
            body: "A see-through copy of the anatomy model appears to your left.")
        static let unsupported = MessageContent(
            title: "Apple Vision Pro needed",
            body: "Recognising the anatomy model (object tracking) only works on Apple Vision Pro, not in the Simulator. Continue without the model instead.")
        static let notAuthorized = MessageContent(
            title: "Permission needed",
            body: "Allow access to your surroundings in Settings › Privacy & Security so the app can recognise the anatomy model.")
        static let missingReferenceObject = MessageContent(
            title: "Reference object missing",
            body: "AnatomyModel.referenceobject is not in the app. Train it with Create ML and add it to the Resources folder (see README).")
        static func failed(_ reason: String) -> MessageContent {
            MessageContent(title: "Tracking stopped", body: reason)
        }
        static func modelsFailed(_ reason: String) -> MessageContent {
            MessageContent(title: "Models could not be loaded", body: reason)
        }
    }

    enum StartPrompt {
        static let title = "The Journey of a Red Blood Cell"
        static let body = "Tap the blood flowing through the anatomy model to start."
    }

    enum Buttons {
        static let start = "Start"
        static let next = "Next"
        static let restart = "Start again"
        static let moreAbout = "More about"
        static let closeFacts = "Close facts"
        static let continueWithoutModel = "Continue without the model"
    }

    // MARK: - Labels

    enum Labels {
        static let redBloodCell = LabelContent(
            title: "Red Blood Cell",
            subtitle: "Erythrocyte",
            facts: [
                "Shape: a flexible disc that is thinner in the middle (biconcave).",
                "Only about 6–8 micrometres wide.",
                "Has no nucleus – this leaves more room for hemoglobin.",
                "Contains about 270 million hemoglobin molecules.",
                "Oxygen-rich blood is scarlet, oxygen-poor blood is dark red."
            ])

        static let youngRedBloodCell = LabelContent(
            title: "Red Blood Cell",
            subtitle: "brand new",
            facts: redBloodCell.facts)

        static let oldRedBloodCell = LabelContent(
            title: "Red Blood Cell",
            subtitle: "about 120 days old",
            facts: [
                "Red blood cells live about 100–120 days.",
                "With age the cell membrane becomes stiffer.",
                "Old cells are removed by macrophages in the spleen, liver and lymph nodes."
            ])

        static let erythroblast = LabelContent(
            title: "Erythroblast",
            subtitle: "a developing red blood cell",
            facts: [
                "Develops from a stem cell in the red bone marrow.",
                "In adults, red bone marrow is found in the vertebrae, ribs, sternum, sacrum, pelvis and the upper end of the thigh bone.",
                "From stem cell to red blood cell takes about 7 days.",
                "The kidneys release the hormone erythropoietin (EPO) when oxygen is low – it speeds up production."
            ])

        static let hemoglobin = LabelContent(
            title: "Hemoglobin",
            holdText: "Drag hemoglobin into the cell",
            facts: [
                "A protein made of 4 chains, each holding an iron-containing heme group.",
                "Each hemoglobin can carry up to 4 oxygen molecules.",
                "Carries more than 98 % of the oxygen in your blood.",
                "The iron is what makes blood red."
            ])

        static let nucleus = LabelContent(
            title: "Nucleus",
            holdText: "Pull the nucleus out of the cell",
            facts: [
                "Holds the cell's DNA.",
                "Mammalian red blood cells push their nucleus out to make room for hemoglobin.",
                "The ejected nucleus is eaten by macrophages in the bone marrow."
            ])

        static let capillary = LabelContent(
            title: "Capillary",
            facts: [
                "The smallest blood vessels.",
                "Many are narrower than a red blood cell – the cell has to bend to pass.",
                "Here oxygen and carbon dioxide are exchanged."
            ])

        static let oxygen = LabelContent(
            title: "Oxygen (O₂)",
            holdText: "Drag oxygen into the red blood cell",
            facts: [
                "Every cell needs oxygen to release energy from food.",
                "It binds to the iron in hemoglobin.",
                "About 21 % of the air you breathe is oxygen."
            ])

        static let bodyCell = LabelContent(
            title: "Body Cell",
            holdText: "Drop the oxygen into this cell",
            facts: [
                "Cells in organs and muscles use oxygen for cellular respiration.",
                "This releases energy from sugar and fat.",
                "Carbon dioxide is left over as waste."
            ])

        static let carbonDioxide = LabelContent(
            title: "Carbon Dioxide (CO₂)",
            holdText: "Pull CO₂ out of the red blood cell",
            facts: [
                "Waste product of cellular respiration.",
                "About 70 % travels in the blood as bicarbonate, about 23 % bound to hemoglobin and about 7 % dissolved in plasma.",
                "You breathe it out with every breath."
            ])
    }

    // MARK: - Panels

    enum Panels {
        static let meetCell = PanelContent(
            id: "meetCell",
            title: "Meet the red blood cell",
            body: """
            You have 20–30 trillion red blood cells – about 70 % of all the cells in your body.
            Every second your bone marrow makes about 2.4 million new ones.
            One full lap around your body takes about one minute.
            Each cell lives about 100–120 days. Its job: carry oxygen from your lungs to every cell and bring carbon dioxide back.
            """,
            hint: "Press Start to follow one red blood cell through its life.")

        static let boneMarrow = PanelContent(
            id: "boneMarrow",
            title: "Born in the bone marrow",
            body: """
            Deep inside your bones – here in the pelvis – stem cells divide and slowly become red blood cells.
            This young cell, an erythroblast, still has a nucleus. Before it can carry oxygen, it has to fill itself with a special protein.
            """,
            continueTitle: "Next")

        static let addHemoglobin = PanelContent(
            id: "addHemoglobin",
            title: "Filling up with hemoglobin",
            body: "The young cell produces huge amounts of hemoglobin – about 270 million molecules per cell. Hemoglobin is the protein that will later carry the oxygen.",
            hint: "Grab the hemoglobin and drag it into the cell.")

        static let ejectNucleus = PanelContent(
            id: "ejectNucleus",
            title: "No more room",
            body: "The cell is now packed with hemoglobin and the nucleus is in the way. Red blood cells push their nucleus out – this leaves the most space for hemoglobin.",
            hint: "Pinch the nucleus and pull it out of the cell.")

        static let cellBorn = PanelContent(
            id: "cellBorn",
            title: "A red blood cell is born",
            body: "Without its nucleus the cell becomes a soft, flexible disc. Now it has to leave the bone marrow and get into the bloodstream.")

        static let squeeze = PanelContent(
            id: "squeeze",
            title: "Squeeze into the bloodstream",
            body: "To enter the blood, the cell must pass through the wall of a tiny blood vessel. Red blood cells are wider than many capillaries – they bend and stretch to squeeze through.",
            hint: "Drag the cell through the capillary.")

        static let travelToLungs = PanelContent(
            id: "travelToLungs",
            title: "Off to the lungs",
            body: "Watch the anatomy model: your cell is the yellow light. It flows with the blood through the veins to the heart, and the right side of the heart pumps it straight to the lungs.")

        static let lungsOxygen = PanelContent(
            id: "lungsOxygen",
            title: "Breathing in: oxygen",
            body: "Your lungs contain about 480 million tiny air sacs (alveoli), wrapped in capillaries. Oxygen moves from the air into the red blood cell and binds to hemoglobin – up to 4 O₂ per hemoglobin, about a billion per cell.",
            hint: "Drag the oxygen into the red blood cell.")

        static let pumpToOrgans = PanelContent(
            id: "pumpToOrgans",
            title: "Your heart takes over",
            body: "Full of oxygen, the cell is now bright scarlet. It flows back to the heart, and the left side pumps it through the aorta into the body. At rest your heart pumps about 5–6 litres of blood per minute and beats about 100,000 times a day.",
            hint: "Tap the glowing heart in the anatomy model 5 times to pump the blood to the organs.")

        static let deliverOxygen = PanelContent(
            id: "deliverOxygen",
            title: "Delivering oxygen",
            body: "In the capillaries of your organs and muscles, oxygen leaves the red blood cell and moves into the body cells. They use it to release energy from food.",
            hint: "Drag the oxygen from the red blood cell into the body cell.")

        static let pickUpCO2 = PanelContent(
            id: "pickUpCO2",
            title: "Picking up carbon dioxide",
            body: "In return the body cell hands over its waste: carbon dioxide. The oxygen-poor blood is now dark red and flows back through the veins to the heart.",
            hint: "Tap the glowing heart in the anatomy model 5 times to pump the blood back to the lungs.")

        static let exhaleCO2 = PanelContent(
            id: "exhaleCO2",
            title: "Breathing out: carbon dioxide",
            body: "Back in the lungs the exchange runs the other way: carbon dioxide leaves the blood and you breathe it out, while fresh oxygen binds to hemoglobin again.",
            hint: "Pull the CO₂ out of the red blood cell.")

        static let cycleRepeats = PanelContent(
            id: "cycleRepeats",
            title: "Again and again",
            body: "Watch your cell on the anatomy model: lungs, heart, body, heart, lungs – one lap takes about one minute. Over its life of about 120 days, a red blood cell repeats this journey roughly 170,000 times.",
            continueTitle: "Next")

        static let agingIntro = PanelContent(
            id: "agingIntro",
            title: "120 days later",
            body: "After months of bending and squeezing, the cell is worn out. Watch the anatomy model: its journey now leads to the spleen.")

        static let agingTry = PanelContent(
            id: "agingTry",
            title: "120 days later",
            body: "In the spleen, blood has to pass through very narrow gaps. Let's see if the old cell still fits.",
            hint: "Drag the cell into the capillary.")

        static let agingTryAgain = PanelContent(
            id: "agingTryAgain",
            title: "It doesn't fit",
            body: "The old cell gets stuck at the entrance.",
            hint: "Try once more.")

        static let tooStiff = PanelContent(
            id: "tooStiff",
            title: "Too stiff to pass",
            body: "Old red blood cells lose their flexibility. In the spleen, blood must pass through gaps only about 2 micrometres wide – stiff cells get stuck there and are eaten by macrophages. The iron from their hemoglobin is recycled to build new red blood cells.")
    }

    // MARK: - Final panel

    enum Final {
        static let title = "The journey of a red blood cell"
        static let facts = [
            "About 2.4 million new red blood cells are made every second – and about as many old ones are removed.",
            "A red blood cell lives about 100–120 days.",
            "It travels around your body about once a minute – roughly 170,000 laps in its life.",
            "Old cells are broken down in the spleen and liver; their iron is used again for new cells."
        ]
    }

    // MARK: - Body regions (shown on the physical model)

    static func title(of zone: AnatomyMap.Zone) -> String {
        switch zone {
        case .boneMarrow: return "Bone marrow"
        case .lungs: return "Lungs"
        case .heart: return "Heart"
        case .organs: return "Organs"
        case .spleen: return "Spleen"
        }
    }

    enum HeartCounter {
        static let title = "Tap the heart"
    }
}
