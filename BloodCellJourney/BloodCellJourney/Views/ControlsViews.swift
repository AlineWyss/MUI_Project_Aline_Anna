//
//  ControlsViews.swift
//  BloodCellJourney
//
//  Small attachments: start prompt, start button, heart, messages, location tag, final panel.
//

import SwiftUI

/// Shown in front of the person at the beginning.
/// Attachment views stay in the scene and render nothing while hidden (see JourneyController, "Attachments").
struct StartPromptView: View {
    let controller: JourneyController

    var body: some View {
        if controller.showsStartPrompt {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 30) {
            Image(systemName: "drop.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text(StoryText.StartPrompt.title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(StoryText.StartPrompt.description)
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
            HStack(spacing: 40){
                Label(StoryText.StartPrompt.duration, systemImage: "clock.arrow.circlepath")
                Label(StoryText.StartPrompt.distance, systemImage: "ruler")
                Label(StoryText.StartPrompt.age, systemImage: "person.circle")
                    
            }
            .font(.system(size: 23))
            .foregroundStyle(Color.secondary)
            
            
            
                HStack(spacing: 12) {
                    Label(StoryText.StartPrompt.body, systemImage: "hand.pinch.fill")
                        .foregroundStyle(Color(uiColor: Palette.taskHint))
                }
            .font(.title3)
            .multilineTextAlignment(.leading)
        }
        .padding(36)
        .frame(width: 560)
        .glassBackgroundEffect()
    }
}

/// Start button below the red blood cell.
struct StartButtonView: View {
    let controller: JourneyController

    var body: some View {
        if controller.showsStartButton {
            button
        }
    }

    private var button: some View {
        Button {
            controller.startTapped()
        } label: {
            Label(StoryText.Buttons.start, systemImage: "play.fill")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }
}

/// Next to the heart of the anatomy model while it has to be pumped: what to do and how often.
/// Tapping the heart in the model pumps; tapping this card works too.
struct HeartCounterView: View {
    let controller: JourneyController
    @State private var beat = 0

    var body: some View {
        if controller.showsHeart {
            card
        }
    }

    private var card: some View {
        Button {
            beat += 1
            controller.heartTapped()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.left")
                    .font(.title2.weight(.bold))
                Image(systemName: "heart.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                    .symbolEffect(.bounce, value: beat)
                VStack(alignment: .leading, spacing: 2) {
                    Text(StoryText.HeartCounter.title)
                        .font(.title3.weight(.semibold))
                    Text("\(controller.heartBeats) / \(controller.requiredHeartBeats)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .glassBackgroundEffect(in: Capsule())
        .hoverEffect()
    }
}

/// Hints while the physical model is being searched, and error messages.
struct MessageView: View {
    let controller: JourneyController

    var body: some View {
        if let message = controller.message {
            VStack(spacing: 14) {
                if controller.isLoadingMessage {
                    // One loading screen: the spinner stays, only the text below changes.
                    LoadingRing()
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                }
                Text(message.title)
                    .font(.title.weight(.bold))
                Text(message.body)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if controller.canContinueWithoutModel {
                    // The physical model is not there or not recognised: use the virtual copy instead.
                    Button {
                        controller.continueWithoutPhysicalModel()
                    } label: {
                        Label(StoryText.Buttons.continueWithoutModel, systemImage: "cube.transparent")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
                }
            }
            .padding(36)
            .frame(width: 560)
            .glassBackgroundEffect()
        }
    }
}

/// End card in front of the physical model with facts and a restart button.
struct FinalPanelView: View {
    let controller: JourneyController

    var body: some View {
        if controller.showsFinalPanel {
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(StoryText.Final.title)
                .font(.title.weight(.bold))
            ForEach(StoryText.Final.facts, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.red)
                    Text(fact)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.title3)
            }
            Button {
                controller.restartTapped()
            } label: {
                Label(StoryText.Buttons.restart, systemImage: "arrow.counterclockwise")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
        }
        .padding(36)
        .frame(width: 580, alignment: .leading)
        .glassBackgroundEffect()
    }
}

/// Loading symbol: a faint ring with a bright arc that turns around it endlessly.
struct LoadingRing: View {
    var size: CGFloat = 44
    var lineWidth: CGFloat = 5
    /// Seconds for one full turn.
    var turnDuration: Double = 1.0
    /// How much of the ring the arc covers (0…1).
    var arcLength: CGFloat = 0.28
    var color: Color = .red

    var body: some View {
        TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let angle = seconds.truncatingRemainder(dividingBy: turnDuration) / turnDuration * 360
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: arcLength)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
        }
    }
}
