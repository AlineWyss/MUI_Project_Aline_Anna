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
        static let title = "Welcome to the Journey of a Red Blood Cell"
        static let description = "This augmented reality experiment illustrates the life cycle of a red blood cell. It shows how a red blood cell is formed and how it moves through the human body. The shared AR space enables students to engage in interactive learning."
        static let duration = "10min"
        static let distance = "~ 1m"
        static let age = "6+"
        static let body = "To get a close-up look on a red blood cell, tap the bloodstream"
    }
    
    enum Buttons {

        static let start = "Discover the life cycle"
        static let restart = "Restart"

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
                "A biconcave disc only about 7.5 µm wide. Besides its nucleus it has also lost its mitochondria, the cell's power plants, so it uses none of the oxygen it carries and gets its energy from sugar alone. Red blood cells make up about 45 % of your blood.",
            ])

        static let youngRedBloodCell = LabelContent(
            title: "Red Blood Cell",
            subtitle: "brand new",
            facts: [
                "A brand-new red blood cell is called a reticulocyte. Under the microscope, leftovers of its RNA show up as a fine net. Only about 1 % of your red blood cells are this young.",
            ])

        static let oldRedBloodCell = LabelContent(
            title: "Red Blood Cell",
            subtitle: "about 120 days old",
            facts: [
                "Over its life a red blood cell slowly gets smaller: it loses bits of its membrane and water, but keeps its disc shape.",
            ])

        static let erythroblast = LabelContent(
            title: "Erythroblast",
            subtitle: "a developing red blood cell",
            facts: [
                "Grows up in a group of up to 30 cells around a \"nurse\" cell, a macrophage that hands them iron for hemoglobin. When oxygen is low, the kidneys release the hormone EPO to speed up production.",
            ])

        static let hemoglobin = LabelContent(
            title: "Hemoglobin",
            holdText: "Drag hemoglobin into the cell",
            facts: [
                "A protein made of 4 chains, each with an iron-containing heme that holds one oxygen molecule. It carries over 98 % of the oxygen in your blood and its heme is what makes blood red.",
            ])

        static let nucleus = LabelContent(
            title: "Nucleus",
            holdText: "Pull the nucleus out of the cell",
            facts: [
                "It holds the cell's DNA, its building plan. The ejected nucleus is eaten at once by the nurse macrophage, so its DNA can't do any harm.",
            ])

        static let capillary = LabelContent(
            title: "Bone marrow sinusoid",
            facts: [
                "Sinusoids form a dense network that runs like spokes towards a large central vein. Not only red blood cells leave here: giant cells called megakaryocytes reach through the wall and break off thousands of tiny platelets that help stop bleeding.",
            ])

                static let spleenSinus = LabelContent(
                    title: "Spleen sinus",
                    facts: [
                        "Its wall is built like a barrel: long, thin wall cells lie side by side like wooden staves, held together by ring-shaped fibres. In the spleen, blood leaves the vessels and first seeps through a sponge-like tissue before it flows back into these sinuses.",
                    ])

        static let oxygen = LabelContent(
            title: "Oxygen (O₂)",
            holdText: "Drag oxygen into the red blood cell",
            facts: [
                "About 21 % of the air you breathe is oxygen. Almost all of it rides on the iron in hemoglobin. Only a tiny part is dissolved in the blood plasma.",
            ])

        static let bodyCell = LabelContent(
            title: "Body Cell",
            holdText: "Drop the oxygen into the cell",
            facts: [
                "Body cells build your organs, muscles and nerves. Unlike a red blood cell, each one keeps its nucleus and has mitochondria - tiny power plants where the oxygen is finally used. Surprisingly, red blood cells outnumber them: about 84 % of all your cells are red blood cells.",
            ])

        static let carbonDioxide = LabelContent(
            title: "Carbon Dioxide (CO₂)",
            holdText: "Pull the carbon dioxide out of the red blood cell",
            facts: [
                "A waste product of cellular respiration. About 70% of it travels in the blood as bicarbonate, the rest bound to hemoglobin or dissolved in plasma until you breathe it out.",
            ])

        /// Same CO₂ label, shown again in the lungs with the instruction underneath.
        static let carbonDioxideExhale = LabelContent(
            title: "Carbon Dioxide (CO₂)",
            facts: [
                "Carbon dioxide controls your breathing: your brain measures how much of it builds up in the blood, not how little oxygen is left. When you hold your breath, the urge to breathe comes from the rising carbon dioxide.",
            ])
    }
   
    // MARK: - Panels

    enum Panels {
        static let welcome = PanelContent(
            id: "welcome",
            title: "Welcome to the Journey of a Red blood Cell",
            body: """
            Welcome to the Journey of ared blood cell!
            """,
            )
            
        static let meetCell = PanelContent(
            id: "meetCell",
            title: "Meet the red blood cell",
            body: """
            Right now, about 25 trillion red blood cells are racing through your body – \
            seven out of every ten cells you have. \
            While you listen to this sentence, your bone marrow is making millions of new ones. \
            Each of them has one job: carry oxygen to every corner of your body. \
            Let's follow one of them – from its very first day to its last.
            """,
            )

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
            body: "To enter the blood, the cell must pass through the wall of a tiny blood vessel. The gaps in the wall are narrower than the cell – it folds and stretches to squeeze through.",
            hint: "Squeeze the cell through the vessel wall into the blood.")

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
            hint: "Tap the heart in the anatomy model 5 times to pump the blood to the organs.")

        static let deliverOxygen = PanelContent(
            id: "deliverOxygen",
            title: "Delivering oxygen",
            body: "In the capillaries of your organs and muscles, oxygen leaves the red blood cell and moves into the body cells. They use it to release energy from food.",
            hint: "Drag the oxygen from the red blood cell into the body cell.")

        static let pickUpCO2 = PanelContent(
            id: "pickUpCO2",
            title: "Picking up carbon dioxide",
            body: "In return the body cell hands over its waste: carbon dioxide. The oxygen-poor blood is now dark red and flows back through the veins to the heart.",
            hint: "Tap the heart in the anatomy model 5 times to pump the blood back to the lungs.")

        static let exhaleCO2 = PanelContent(
            id: "exhaleCO2",
            title: "Breathing out: carbon dioxide",
            body: "Back in the lungs the exchange runs the other way: carbon dioxide leaves the blood and you breathe it out, while fresh oxygen binds to hemoglobin again.",
            hint: "Pull the carbon dioxide out of the red blood cell.")

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
            body: "In the spleen, blood has to squeeze through narrow gaps in the vessel walls. Let's see if the old cell still fits.",
            hint: "Squeeze the cell through the vessel wall.")

        static let agingTryAgain = PanelContent(
            id: "agingTryAgain",
            title: "It doesn't fit",
            body: "The old cell can only bend a little – it gets stuck in the gap.",
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
            "To experience the journey again, click \"Restart\".",
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

// VOICEGUIDE: Voice over Text


