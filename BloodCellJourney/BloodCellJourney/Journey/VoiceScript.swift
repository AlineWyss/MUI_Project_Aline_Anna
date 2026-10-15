//
//  VoiceScript.swift
//  BloodCellJourney
//
//  Created by wyss aline on 14.10.2026.
//
import Foundation

extension StoryText {

    enum Voice {        static let lines: [String: String] = [
        
        // Willkommen
        "welcome": """
        Welcome to the journey of a red blood cell! \
        To begin, tap the bloodstream on the anatomy model.
        """,

        // Start
        "meetCell": """
        This is a red blood cell. \
        About 25 trillion of them are travelling through your body right now. \
        Their main job is to carry oxygen from your lungs to every part of your body, \
        and on the way back, they help to carry carbon dioxide to your lungs, so you can breathe it out. \
        Let's follow one of them and discover its life cycle. \
        Press the button when you are ready.
        """,

        // Knochenmark
        "boneMarrow": """
        It all starts inside your bones, in the soft red bone marrow. \
        Here, our cell begins its life as a young cell called an erythroblast. \
        It still has a nucleus, and it cannot carry oxygen yet.
        """,

        // Hemoglobin
        "addHemoglobin": """
        During its development, the young cell produces hemoglobin and fills itself up with it. \
        It gives blood its red colour and enables the cell to carry oxygen through the body. \
        Drag the hemoglobin into the cell to help it fill up.
        """,

        // Zellkern
        "ejectNucleus": """
        The cell is now full of hemoglobin, and the nucleus is in the way. \
        So the cell pushes its nucleus out. \
        This leaves more room for hemoglobin and in turn enables the cell to carry more oxygen. \
        Pull the nucleus out of the cell.
        """,

        // Rotes Blutkörperchen entsteht
        "cellBorn": """
        Without its nucleus, our cell is now a young red blood cell. \
        It has taken about a week to get this far. \
        The cell is soft and flexible, which will help it pass through narrow spaces.
        """,

        // Squeeze
        "squeeze": """
        Now that it is ready, the cell leaves the bone marrow and enters the bloodstream. \
        To do this, it passes through the wall of a bone marrow sinusoid, \
        a wide blood vessel with a very thin wall. \
        The openings in this wall are smaller than the cell, so it has to fold and squeeze through. \
        Help it through the vessel wall.
        """,

        // Im Blut
        "travelToLungs": """
        Our cell is now in the blood! \
        Have a look at the anatomy model. The glowing light shows where our cell is. \
        The blood carries it to the heart, and the heart pumps it to the lungs.
        """,

        // In der Lunge
        "lungsOxygen": """
        Our cell has arrived in the lungs. \
        When you breathe in, oxygen moves from the air into the blood and into our cell. \
        There, the oxygen binds to the hemoglobin, which carries it through the body. \
        One red blood cell can carry about a billion oxygen molecules. \
        Drag the oxygen into the cell.
        """,

        // Herz pumpen
        "pumpToOrgans": """
        Full of oxygen, our cell is now bright red. \
        It flows back to the heart, which pumps it out into the body. \
        Tap the heart five times to send our cell through the body.
        """,

        // O2 Abgabe
        "deliverOxygen": """
        We have arrived in the organs. \
        Here, in the tiniest blood vessels, our cell hands over its oxygen to the body cells. \
        They need oxygen to get energy from food. \
        Drag the oxygen over to the body cell.
        """,

        // CO2 Aufnahme
        "pickUpCO2": """
        In return, the body cell gives off its waste: carbon dioxide. \
        Our cell helps to carry it to the lungs. \
        Without its oxygen, our cell is now dark red. \
        Tap the heart again to pump it back to the lungs.
        """,

        // In die Lunge zurück
        "exhaleCO2": """
        Back in the lungs, the carbon dioxide leaves the blood, and you breathe it out. \
        At the same time, our cell picks up fresh oxygen again. \
        Pull the carbon dioxide out of the cell.
        """,

        // Cycle Animation
        "cycleRepeats": """
        That was one complete lap, and it took our cell only about a minute. \
        In its lifetime, our cell will make this lap about 170,000 times.
        """,

        // Squeeze nicht mehr möglich
        "agingIntro": """
        Over time, our cell gradually loses its flexibility. \
        Without a nucleus, it cannot repair itself, \
        and after about 120 days, all that bending and squeezing has taken its toll. \
        Our cell has grown old and stiff, and its path now leads to the spleen.
        """,

        // Erster Versuch
        "agingTry": """
        The spleen works like a quality check for the blood. \
        Inside it, blood cells have to squeeze through tiny slits in the walls of its vessels. \
        These slits are less than one micrometre wide, which is much narrower than the cell itself. \
        Young, flexible cells slip through easily, but old, stiff cells get stuck. \
        Let's see whether our old cell can still make it. Try to squeeze it through the vessel wall.
        """,

        // Zweiter Versuch
        "agingTryAgain": """
        It does not fit. The old cell can only bend a little. \
        Give it one more try.
        """,

        // Geht nicht mehr
        "tooStiff": """
        Our cell has become too stiff to pass, so it stays behind in the spleen. \
        There, clean-up cells called macrophages take it apart. \
        But nothing goes to waste. \
        The iron from its hemoglobin is carried back to the bone marrow, \
        where it is used to build brand-new red blood cells. \
        Every second, your bone marrow makes about two million of them. \
        So while our cell's journey ends here, countless new ones are just beginning.
        """
    ]}
}

