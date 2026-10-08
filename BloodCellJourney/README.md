# Blood Cell Journey – visionOS

Interaktive Apple-Vision-Pro-App über den Lebenszyklus eines roten Blutkörperchens.
Euer physisches Anatomiemodell wird per **Object Tracking** erkannt und mit Blutbahnen,
Körperregionen und einem wandernden Leuchtpunkt erweitert. Die Zellen zum Interagieren
erscheinen immer vor der Person, der Text immer rechts davon.

**Zwei Modi** (Auswahl im Startfenster):

| Modus | Wann | Was passiert |
|---|---|---|
| **Start with the anatomy model** | Physisches Modell steht im Raum, Apple Vision Pro, Reference Object ist in der App | Das echte Modell wird erkannt, die Blutbahn liegt darauf |
| **Start without the model** | Kein Modell vorhanden, oder **Simulator** | Eine halbdurchsichtige virtuelle Kopie eures Scans steht links vorne, alles andere läuft genau gleich |

Wird das echte Modell nicht gefunden, kann man während der Suche mit
**„Continue without the model“** auf die virtuelle Kopie wechseln.

> **Status:** Der Code wurde ohne Xcode geschrieben und ist **noch nie kompiliert worden**.
> Syntax und API-Aufrufe wurden geprüft, trotzdem können beim ersten Build kleine Fehler kommen.
> Siehe „Bekannte Grenzen“ unten.

---

## 1. Voraussetzungen

- Mac mit Apple Silicon, **Xcode 27** (Xcode 26 geht auch) inkl. Create ML.
  Laut Apple braucht das Training in Create ML einen Mac mit **M2 oder neuer**.
- Für den Modus **mit Modell**: **Apple Vision Pro** mit visionOS 26 oder neuer – **visionOS 27**, wenn das Reference Object mit Xcode 27 trainiert wurde. Object Tracking läuft **nicht im Simulator**.
- Für den Modus **ohne Modell**: Apple Vision Pro **oder der visionOS-Simulator** in Xcode.
- Apple-Developer-Account (kostenloser Account reicht zum Testen auf dem eigenen Gerät)

## 2. Projekt öffnen

1. `BloodCellJourney.xcodeproj` öffnen.
2. Target **BloodCellJourney › Signing & Capabilities**: euer **Team** wählen und die
   Bundle ID ändern (aktuell `com.example.BloodCellJourney`).
3. Xcode löst das lokale Paket `Packages/RealityKitContent` automatisch auf.

## 3. Reference Object trainieren (nur für den Modus mit Modell, einmalig, dauert einige Stunden)

Das Modell wird anhand eures Scans erkannt (echte Grösse: 48 × 94 × 26 cm). Der Scan liegt hier:
`Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/AnatomyModel.usdz`.
Dieselbe Datei wird im Modus ohne Modell als virtuelle Kopie angezeigt.

**Mit der Create-ML-App**
1. Xcode › Open Developer Tool › **Create ML** › neues Projekt › Vorlage **Object Tracking** (Kategorie *Spatial*).
2. `AnatomyModel.usdz` (Pfad siehe oben) in den 3D-Viewport ziehen und prüfen, dass die Masse stimmen.
3. **Viewing angles: Upright** – das Modell steht aufrecht auf dem Tisch.
4. Training mode: *Standard* reicht. *Extended* ist genauer, dauert aber mehrmals länger.
5. **Train** klicken. Danach im Tab *Output* die Datei speichern als **`AnatomyModel.referenceobject`**.

**Oder im Terminal**
```bash
cd <Projektordner>
xcrun createml objecttracker -s Packages/RealityKitContent/Sources/RealityKitContent/RealityKitContent.rkassets/AnatomyModel.usdz -o AnatomyModel.referenceobject
xcrun createml objecttracker -h   # zeigt die Optionen, z. B. für den Blickwinkel
```

Dann **`AnatomyModel.referenceobject` in den Ordner `BloodCellJourney/Resources/` kopieren**.
Der Ordner ist mit Xcode synchronisiert, die Datei ist danach automatisch im Projekt.

> Ein Reference Object, das mit Xcode 27 trainiert wurde, läuft nur auf visionOS 27 oder neuer.

## 4. Starten

**Auf der Vision Pro mit Modell:** Vision Pro als Ziel wählen, **Run**.
1. Vor das Modell stellen, sodass es **leicht links** vor euch steht.
2. **Start with the anatomy model** drücken und das Modell anschauen, bis die Blutbahnen darauf erscheinen.
3. Beim ersten Start fragt visionOS nach der Erlaubnis, die Umgebung zu erkennen → erlauben.

**Ohne Modell (Vision Pro oder Simulator):** **Start without the model** drücken. Die virtuelle
Kopie erscheint links vorne (etwa 1,3 m vor euch, 0,75 m nach links), halb durchsichtig, damit
die Blutbahnen darin sichtbar bleiben.

**Im Simulator testen:** Als Ziel *Apple Vision Pro* (Simulator) wählen, **Run**, dann
**Start without the model**. Der Knopf „with the anatomy model“ ist im Simulator ausgegraut.
Bedienung mit der Maus: Klick = Antippen, Klicken und Ziehen = Greifen und Ziehen.
Die Kamera bewegt ihr mit den Steuerelementen unten rechts im Simulator-Fenster.

---

## Ablauf der App

| # | Schritt | Interaktion | Am physischen Modell |
|---|---|---|---|
| 1 | Start | Den Blutstrom am Modell antippen | ~8000 winzige rote Blutkörperchen (≈ 2 mm, dicht gepackt, wirkt wie fliessendes Blut) im echten Kreislauf: Herz → Arterien (pulsierend) → Kapillaren (langsam, werden dunkelrot) → Venen → Herz → Lunge (werden hellrot) → Herz. **Nur in dieser ersten Szene:** nach dem Antippen blendet der Blutstrom aus und kommt erst bei **Start again** wieder. |
| 2 | Rotes Blutkörperchen | Name + (i) (einziges Mal mit Label, siehe unten) – (i) öffnet die Fakten **im Label selbst**; allgemeiner Text rechts, **Start** | Zelle fliegt aus dem Herz des Modells |
| 3 | Knochenmark | Entwickelnde Zelle (Shell + Nucleus), **Next** | Umriss des Beckens leuchtet |
| 4 | Hämoglobin | In die Zelle ziehen (Label wechselt beim Halten) | |
| 5 | Zellkern | Kern wackelt, herausziehen → wird zum roten Blutkörperchen | |
| 6 | In die Blutbahn | Zelle durch die Kapillare ziehen, sie verformt sich | |
| 7 | Lunge | Zelle fliegt ins Modell, wandert als gelber Punkt mit Leuchtspur Knochenmark → Herz → Lunge, fliegt wieder heraus; dann O₂ in die Zelle ziehen | Umriss der Lunge |
| 8 | Herz | Zelle fliegt ins Modell; **das Herz im Modell** 5× antippen (Zähler daneben) | Herz-Umriss schlägt, gelber Punkt wandert pro Schlag durchs Herz zu den Organen |
| 9 | Organe | Zelle fliegt heraus; O₂ in die Körperzelle ziehen, CO₂ kommt automatisch zurück | Umriss von Leber, Magen, Darm |
| 10 | Herz | Zelle fliegt ins Modell; Herz im Modell 5× antippen | Punkt wandert durchs Herz zurück zur Lunge |
| 11 | Lunge | Zelle fliegt heraus; CO₂ herausziehen → frischer Sauerstoff bindet | Umriss der Lunge |
| 12 | Kreislauf | Zelle fliegt ins Modell; Text: ~1 Runde pro Minute, ~170 000 Runden, **Next** | Gelber Punkt kreist |
| 13 | Alterung | Punkt wandert zur Milz, Zelle fliegt gealtert heraus; in die Kapillare ziehen – passt nicht; nach 2 Versuchen Erklärung | Umriss der Milz |
| 14 | Recycling | Zelle löst sich auf | |
| 15 | Ende | Fakten + **Start again** in der Mitte vor der Person (wo vorher die Zellen waren) | |

**Labels nur beim ersten Auftritt:** Jedes Objekt bekommt sein Namens-Label nur, wenn es in einem
Durchlauf zum ersten Mal erscheint (rotes Blutkörperchen in Schritt 2, Erythroblast, Hämoglobin, Zellkern,
Kapillare, O₂, Körperzelle, CO₂ in Schritt 9). Danach erscheint dasselbe Objekt ohne Label – z. B. das
rote Blutkörperchen nach dem Zellkern, nach den Herz-Schritten und gealtert. Erkannt wird ein Objekt am
`title` seines Labels in `StoryText.Labels`. **Start again** setzt das zurück.

**Fakten im Label:** (i) öffnet die Fakten im selben Kasten wie der Name. Der Kasten wächst nach oben,
seine Unterkante bleibt über dem Modell. Das ✕ schliesst ihn wieder. Der Text rechts bleibt unverändert.

Die Biologie folgt Teil 1 des Briefings (O₂ in der Lunge rein, in den Organen raus;
sauerstoffreich = hellrot, sauerstoffarm = dunkelrot). Aus Teil 2 übernommen: wackelnder Kern,
2 Versuche an der Kapillare, Schlusstext mit Neustart.

---

## Was ihr wo anpasst

| Was | Datei |
|---|---|
| Alle Texte, Labels, Fakten (Englisch) | `BloodCellJourney/Content/StoryText.swift` |
| Positionen vor der Person, Grössen, Farben, Zeiten | `BloodCellJourney/Config/Config.swift` |
| Blutbahnen, Organe, Wege am **physischen** Modell | `BloodCellJourney/Scene/AnatomyMap.swift` |
| Position und Durchsichtigkeit der **virtuellen** Kopie | `Config.swift`: `Layout.virtualModel…`, `Config.virtualModelOpacity` |
| Blutstrom am Modell: Anzahl, Grösse, Breite, Tempo, Herzfrequenz, Röhren an/aus | `Config.swift`: `flowCellCount` (8000), `flowCellDiameter` (2,2 mm), `flowCellSpread`, `flowSpeed`, `restingHeartRate`, `showVesselTubes`. Echte Grösse (7–8 µm) wäre unsichtbar. Ruckelt es, `flowCellCount` senken. |
| Position des Endbildschirms, Abstand der Labels/Start-Knopf zum Modell | `Config.swift`: `Layout.finalPanelSlot`, `Layout.labelGap`, `Layout.buttonGap` |
| Neues SwiftUI-Panel in der Szene | `JourneyController.swift`: `makeAttachmentSlots()` – immer über `AttachmentSlot` (siehe Bekannte Grenzen) |
| Kreislauf-Wege und Organ-Umrisse | `AnatomyMap.swift`: `systemicBranches`, `outlines(for:)` |
| In welchen Szenen der Blutstrom läuft | `JourneyController+Steps.swift`: `overlay.setStreamVisible(true)` in `enterIntro()`, `setStreamVisible(false)` in `bloodstreamTapped()`. Für eine weitere Szene dort `setStreamVisible(true)` aufrufen. |
| Labels nur beim ersten Auftritt / jedes Mal | `JourneyController.swift`: `firstAppearance(_:current:)`. Sollen Labels wieder bei jedem Auftritt erscheinen, dort als erste Zeile `return content` einfügen. |
| Flug der Zelle ins Modell, Herz-Zähler | `Config.swift`: `Timing.flyToModel`, `Layout.cellScaleInModel`, `Layout.heartCounterSideOffset` |
| Modelle, Materialien | Reality Composer Pro: `Packages/RealityKitContent/Package.realitycomposerpro` öffnen, Szene `BloodCellModels` |
| Ablauf der Schritte | `BloodCellJourney/Journey/JourneyController+Steps.swift` |
| Ziehen / Ablegen / Grenzen | `BloodCellJourney/Journey/JourneyController+Interaction.swift` |

**Overlay justieren:** In `Config.swift` `showAlignmentGhost = true` setzen. Dann liegt eine
durchsichtige Kopie des Scans über dem echten Modell. Wenn sie sauber sitzt, stimmt das Tracking,
und ihr könnt Punkte in `AnatomyMap.swift` verschieben (Meter, Ursprung = Mitte des Sockels,
+y oben, die Figur schaut nach +z, ihr rechter Arm ist −x).

**Transparenz von O₂/CO₂:** Die exportierten Materialien haben nur 10–14 % Deckkraft und sind in
der Brille kaum sichtbar. `Config.opacityOverrides` setzt sie auf 85 %. Eintrag löschen = Originallook.

**Modelle tauschen:** In Reality Composer Pro die USDZ ersetzen. Der **Name des Objekts in der Szene**
(`RedBloodCell`, `DevelopingShell`, `DevelopingNucleus`, `Hemoglobin`, `Oxygen`, `CarbonDioxide`,
`BodyCellOuter`, `BodyCellInner`, `Capillary`) muss gleich bleiben. Grösse und Ausrichtung
rechnet der Code selbst aus. Die Zielgrössen stehen in `Layout.Size`.

---

## Projektstruktur

```
BloodCellJourney.xcodeproj
BloodCellJourney/
  App/           Start-Fenster, App, AppModel
  Config/        Config.swift (Grössen, Positionen, Farben, Zeiten)
  Content/       StoryText.swift (alle Texte)
  Journey/       Ablauf (Steps), Interaktion, ImmersiveView
  Scene/         Modelle laden, Overlay am physischen Modell, Animationen (ECS-Systeme)
  Tracking/      ARKit: Object Tracking + Kopfposition
  Views/         SwiftUI-Panels (Labels mit Fakten, Text rechts, Herz, Endkarte)
  Resources/     ← hier AnatomyModel.referenceobject ablegen
Packages/RealityKitContent/   Reality-Composer-Pro-Paket: Szene BloodCellModels (9 Modelle)
                              und Szene VirtualAnatomy (zeigt euren Scan im Modus ohne Modell).
                              Die Datei AnatomyModel.usdz daneben ist auch die Vorlage fürs Create-ML-Training.
```

---

## Bekannte Grenzen

- **visionOS-26-Fehler (FB20792470):** Knöpfe in SwiftUI-Panels reagieren nicht mehr, wenn ihr Panel-Entity
  einmal ausgeblendet war und wieder erscheint. Apple nennt Deaktivieren und Entfernen; bei uns reichte es
  offenbar, dass das Panel zwischendurch leer war (nach **Start again** reagierte der Start-Knopf nicht mehr).
  Lösung: `AttachmentSlot` legt bei **jedem** Erscheinen ein neues Entity an und entfernt es beim Ausblenden
  endgültig. **Bei eigenen Erweiterungen: neue Panels immer über `AttachmentSlot` zeigen/verstecken,
  nie ein Panel-Entity deaktivieren, umhängen oder wiederverwenden.**

- **Die letzte Änderung (feiner Blutstrom mit GPU-Instancing, Fakten im Label, Endbildschirm in der Mitte,
  neue Panel-Logik für Start again) ist nicht kompiliert und nicht auf dem Gerät getestet.** Die Version
  davor wurde bei euch gebaut und gestartet.
- Der Blutstrom nutzt `MeshInstancesComponent` (visionOS 26). Nicht geprüft: ob das Ein-/Ausblenden per
  Deckkraft damit weich überblendet (sonst erscheint/verschwindet er einfach) und wie flüssig 8000 Zellen
  im Debug-Build laufen.
- Die Positionen der Organe und Gefässe sind aus dem Scan **gemessen, aber nicht am echten Modell
  überprüft**. Mit `showAlignmentGhost` kontrollieren.
- Labels und Panels sind SwiftUI. Ihre echte Grösse im Raum hängt vom Umrechnungsfaktor
  Punkt → Meter ab. Falls etwas überlappt, `Layout.panelSlot` oder `sideSlot` anpassen.
- Die Verformung in der Kapillare ist eine Stauchung im Code (die Modelle haben keine Blendshapes).
- **Simulator:** Ob die Kopfposition dort verfügbar ist, ist nicht geprüft (ein Apple-Forum-Beitrag von
  2023 sagt ja). Falls nicht, stehen virtuelles Modell und Zellen an festen Positionen im Raum
  (`Layout.fallbackHeadPosition`). Die App funktioniert trotzdem.

## Quellen der Fakten

- Red blood cell – Wikipedia: Anzahl (20–30 Billionen, ~70 % aller Zellen), 2,4 Mio./s, 100–120 Tage, ~1 Minute pro Kreislauf, ~270 Mio. Hämoglobin, Farbe, Abbau
- Carbaminohemoglobin – Wikipedia: CO₂-Transport 70 % / 23 % / 7 %
- TeachMePhysiology – Erythropoiesis: Orte des roten Knochenmarks, EPO aus der Niere
- Frontiers in Physiology (2021), Clearance alter Erythrozyten: Milz-Spalten ~2 µm, Makrophagen
- Cleveland Clinic – Heart facts: ~100 000 Schläge/Tag, ~5,7 l/min (im Text: „5–6 Liter“)
- Simple Wikipedia – Air sac: ~480 Mio. Alveolen
- „~170 000 Runden“ ist gerechnet: 120 Tage × 1 440 Minuten
