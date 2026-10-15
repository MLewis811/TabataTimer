import SwiftUI
import Playgrounds
import AVFoundation

// MARK: - Reusable pieces

struct Tile: View {
    let title: String
    let value: String
    let color: Color
    var valueSize: CGFloat = 72
    var subtitle: String? = nil
    var isSelected = false
    var selectedBorderColor: Color? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(color)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .opacity(0.9)
                Text(value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .opacity(0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(.white)
            .padding(16)

            if isSelected {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(selectedBorderColor ?? .white, lineWidth: 8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct PanelButton: View {
    let label: String
    var color: Color = Color(.systemGray)
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Main screen

struct ContentView: View {
    @StateObject private var model = TabataModel()
    
    @State private var showingSettings = false

    private let gap: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - gap * 3   // two outer margins + one middle gap
            HStack(spacing: gap) {
                leftPanel
                    .frame(width: available * 2 / 3)
                rightPanel
                    .frame(width: available / 3)
            }
            .padding(gap)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Left two-thirds

    private var leftPanel: some View {
        VStack(spacing: gap) {
            Tile(title: "WORKOUT",
                 value: TabataModel.format(model.remainingSeconds),
                 color: workoutColor,
                 valueSize: 220,
                 subtitle: workoutSubtitle)
                .frame(maxHeight: .infinity)

            HStack(spacing: gap) {
                Tile(title: "CYCLES",
                     value: "\(model.cycles)",
                     color: .purple,
                     valueSize: 90,
                     isSelected: model.selected == .cycles,
                     selectedBorderColor: .black)
                    .onTapGesture { model.select(.cycles) }

                Tile(title: "TABATAS",
                     value: "\(model.tabatas)",
                     color: .pink,
                     valueSize: 90,
                     isSelected: model.selected == .tabatas,
                     selectedBorderColor: .pink)
                    .onTapGesture { model.select(.tabatas) }
            }
            .frame(height: 220)
        }
    }

    private var workoutColor: Color {
        if let position = model.currentPosition { return position.phase.color }
        return model.isFinished ? .gray : .indigo
    }

    private var workoutSubtitle: String {
        if let p = model.currentPosition {
            var parts = [p.phase.title]
            if p.phase != .prepare { parts.append("Cycle \(p.cycle)/\(model.cycles)") }
            if model.tabatas > 1 { parts.append("Tabata \(p.tabata)/\(model.tabatas)") }
            return parts.joined(separator: " · ")
        }
        return model.isFinished ? "Done!" : " "
    }

    // MARK: Right third

    private var rightPanel: some View {
        VStack(spacing: gap) {
            Tile(title: "PREPARE",
                 value: TabataModel.format(model.prepare),
                 color: Phase.prepare.color,
                 isSelected: model.selected == .prepare,
                 selectedBorderColor: Phase.prepare.color)
                .onTapGesture { model.select(.prepare) }
                .frame(maxHeight: .infinity)

            Tile(title: "WORK",
                 value: TabataModel.format(model.work),
                 color: Phase.work.color,
                 isSelected: model.selected == .work,
                 selectedBorderColor: Phase.work.color)
                .onTapGesture { model.select(.work) }
                .frame(maxHeight: .infinity)

            Tile(title: "REST",
                 value: TabataModel.format(model.rest),
                 color: Phase.rest.color,
                 isSelected: model.selected == .rest,
                 selectedBorderColor: Phase.rest.color)
                .onTapGesture { model.select(.rest) }
                .frame(maxHeight: .infinity)

            HStack(spacing: gap) {
                PanelButton(label: "-", isEnabled: !model.isRunning) { model.adjust(-1) }
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: "gear")
                        .resizable()
                        .scaledToFit()
                        .padding(13)
                        .foregroundStyle(.white)
                        .background(.gray)
                        .clipShape(Circle())
                        .padding(.vertical, 17)
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsModal(chosenVoice: $model.voice)
                }
                PanelButton(label: "+", isEnabled: !model.isRunning) { model.adjust(+1) }

            }
            .frame(height: 90)



            if model.isRunning {
                SlideToStopSlider {
                    model.stop()
                }
            } else {
                PanelButton(label: "Start",
                            color: Color(red: 0.1, green: 0.6, blue: 0.3)) {
                    model.start()
                }
                .frame(height: 90)
            }
        }
    }
}

#Preview(traits: .landscapeLeft) {
    ContentView()
}

#Playground {
    _ = 1 + 2
}

struct SlideToStopSlider: View {
    var onStop: () -> Void
    @State private var offset: CGFloat = 0
    @GestureState private var isDragging = false
    let sliderWidth: CGFloat = 320
    let sliderHeight: CGFloat = 68
    let knobWidth: CGFloat = 68

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: sliderHeight / 2, style: .continuous)
                .fill(Color(.systemGray6))
                .frame(width: sliderWidth, height: sliderHeight)
                .shadow(radius: 2)
            Text("Slide to Stop")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundColor(.gray)
                .frame(width: sliderWidth, height: sliderHeight)
                .opacity(offset < sliderWidth - knobWidth ? 1 : 0)
            RoundedRectangle(cornerRadius: knobWidth / 2, style: .continuous)
                .fill(Color.red)
                .frame(width: knobWidth, height: knobWidth)
                .overlay(Image(systemName: "power"), alignment: .center)
                .foregroundColor(.white)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            let limited = min(max(0, value.translation.width), sliderWidth - knobWidth)
                            offset = limited
                        }
                        .onEnded { value in
                            if offset > sliderWidth - knobWidth - 12 {
                                // Trigger stop if fully slid
                                onStop()
                            }
                            // Snap back regardless
                            withAnimation { offset = 0 }
                        }
                )
        }
        .frame(width: sliderWidth, height: sliderHeight)
        .padding(.vertical, 16)
    }
}
