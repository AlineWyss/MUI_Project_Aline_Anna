//
//  VoiceScript.swift
//  BloodCellJourney
//
//  Created by wyss aline on 14.10.2026.
//
import Foundation

extension StoryText {

    enum Voice {
        static let lines: [String: String] = [
            
            //Willkommen
            "welcome": """
            Welcome to the Journey of a red blood cell!
""",

            //Start
            "meetCell":"""
            There are about 25 trillion red blood cells moving through our body, \
            which make up 70% of our blood cells. \
            Every second our bone marrow produces 20-30 million new red blood cells and sends them in to the blood flow. 
            """,
// For one cycle, the red blood cell needs one minute and transports oxygen to every corner in our body. \



         //Knochenmark
            "boneMarrow": """
            It all starts in the bone marrow, where the Erythroblast develops and matures. \
            In the soft red marrow, stem cells divide again and again. \
            One of them is about to become our red blood cell that we are going to follow.
            """,
            
            //Hemoglobin
            "addHemoglobin": """
            To help develop to a red blood cell the Hemoglobin comes and needs to get in to the Erythroblast. \
            It will help to hold on to oxygin on it's way through the blood flow
            """,

            //Hemoglobin in die Zelle
            "ejectNucleus": """
            Because of the hemoglobin, the nucleus dosn't have enough space anymore. \
            So the cell needs to throws the nucleuse out.
            """, 

            //Rotes Blutkörperchen entsteht
            "cellBorn": """
            After some days a red blood cell has been developed. \
            Without the nucleus it becomes a soft and flexible disc, wich is thinner on the inside then on the outside.
            """,

            //Squeeze
            "squeeze": """
            Now the red blood cell has to leaf the bone marrow in to the bloood flow. 
            The only way is through the wall of a tiny vessel \
            and the gaps are narrower than the cell itself.
            """,

            //Im Blut
            "travelToLungs": """
            It made it through! \
            If you now take a look on the anatomy model, you see a glowing red blood cell \
            wich shows to you where you are. \
            It starts in the lungs.
            """,

            // In der Lunge
            "lungsOxygen": """
            Welcome to the lungs. \
            Every time you breathe in, oxygen slips into the blood. \
            Thanks tho the homoglobin, the red blood cell can then hold on to four oxygens.
            """,

            // Herz pumpen
            "pumpToOrgans": """
            Loaded with oxygen, our cell now glows bright scarlet. \
            But to get through the body to deliver the oxygin the heart needs to pump and get the blood flowing. \
            At rest, your heart moves five to six litres of blood every minute \
            and beats about 100,000 times a day. 
            """,

            // CO2 Aufnahme
            "deliverOxygen": """
            We've arrived in the organs. In the smallest vessels, and the body cells are waiting. \
            They need oxygen to turn food into energy. 
            """,

            //O2 Aufnahme und CO2 Abgabe
            "pickUpCO2": """
            In return, the body cell passes on its waste: carbon dioxide. \
            Without the oxygen, our cell turns dark red. \
            To finish one lap, it needs to go back in to the lung. 
            """,

            // In die Lunge zurück
            "exhaleCO2": """
            Back in the lungs, everything runs the other way. \
            With your next breath, you'll breathe the carbon dioxid out, \
            and at the same moment, fresh oxygen is already binding again.
            """,

            //Cycle Animation
            "cycleRepeats": """
            That was one full lap and it took only about a minute. \
            Lungs, heart, body, heart, lungs, over and over again. \
            In its lifetime, our cell will make this journey about 170,000 times.
            """,

            //Squeeze nicht mehr möglich
            "agingIntro": """
            After 120 days all that bending and squeezing has taken its toll. \
            Our cell has grown old and stiff and this time, its path leads to the spleen.
            """,

            //First try
            "agingTry": """
            The spleen is the body's quality check. \
            Here, blood has to squeeze through gaps only about two micrometres wide. \
            Let's see if our old cell can still make it.
            """,

            //Zweiter versuch
            "agingTryAgain": """
            Dosn't work. It can only bend a little. Give it one more try.
            """,
        
//Geht nicht mehr
            "tooStiff": """
            It wont work the cell is simply too stiff. \
            Here in the spleen, the body cleans-up cells and take it apart. \
            But nothing is wasted. The iron from its hemoglobin is recycled into brand-new red blood cells. \
            And somewhere deep in your bones, the journey begins again.
            """
        ]
    }
}

