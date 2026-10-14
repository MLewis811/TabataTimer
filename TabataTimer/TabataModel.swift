import SwiftUI
import Combine
import AVFoundation

/// Which tile the +/- buttons currently act on.
enum Field {
    case prepare, work, rest, cycles, tabatas
}

enum Phase {
    case prepare, work, rest

    var title: String {
        switch self {
        case .prepare: return "Prepare"
        case .work:    return "Work"
        case .rest:    return "Rest"
        }
    }

    var color: Color {
        switch self {
        case .prepare: return .yellow
        case .work:    return .green
        case .rest:    return .red
        }
    }
    
    var speak: String {
        switch self {
        case .prepare: return "Ready"
        case .work: return "Work"
        case .rest: return "Rest"
        }
    }
}

/// Where the workout is at a given moment.
struct Position: Equatable {
    var phase: Phase
    var cycle: Int    // 1-based; 0 during Prepare
    var tabata: Int   // 1-based
}



@MainActor
final class TabataModel: ObservableObject {
    // Configurable values (times in seconds)
    @Published var prepare = 5
    @Published var work = 20
    @Published var rest = 10
    @Published var cycles = 8
    @Published var tabatas = 1

    @Published var selected: Field = .prepare

    // Run state
    @Published private(set) var elapsed = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isFinished = false

    private var ticker: Task<Void, Never>?
    private var whistle: AVAudioPlayer?

    init() {
        if let url = Bundle.main.url(forResource: "whistle", withExtension: "wav") {
            whistle = try? AVAudioPlayer(contentsOf: url)
            whistle?.prepareToPlay()
        }
        // .playback lets the sound play even when the mute switch/setting is on;
        // .mixWithOthers avoids interrupting music the user may be playing.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func playWhistle() {
        guard let whistle else { return }
        whistle.currentTime = 0   // restart if it's still playing from the last phase change
        whistle.play()
    }

    private let timeStep = 1
    private let maxTime = 99 * 60 + 55
    private let maxCount = 99

    // MARK: - Derived values

    /// [(Prepare) + Cycles * (Work + Rest)] * Tabatas
    var totalSeconds: Int {
        (prepare + cycles * (work + rest)) * tabatas
    }

    var remainingSeconds: Int {
        max(0, totalSeconds - elapsed)
    }

    var currentPosition: Position? {
        guard isRunning else { return nil }
        return position(at: elapsed)
    }

    private func position(at t: Int) -> Position? {
        guard t >= 0, t < totalSeconds else { return nil }
        let cycleLen = work + rest
        let tabataLen = prepare + cycles * cycleLen
        let tabataIndex = t / tabataLen
        let r = t % tabataLen

        if r < prepare {
            return Position(phase: .prepare, cycle: 0, tabata: tabataIndex + 1)
        }
        let r2 = r - prepare
        let cycleIndex = r2 / cycleLen
        let r3 = r2 % cycleLen
        return Position(phase: r3 < work ? .work : .rest,
                        cycle: cycleIndex + 1,
                        tabata: tabataIndex + 1)
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Editing

    func select(_ field: Field) {
        selected = field
    }

    func adjust(_ direction: Int) {
        guard !isRunning else { return }
        if isFinished { resetRun() }

        switch selected {
        case .prepare:
            prepare = clamp(prepare + direction * timeStep, 0, maxTime)
        case .work:
            work = clamp(work + direction * timeStep, timeStep, maxTime)
        case .rest:
            rest = clamp(rest + direction * timeStep, 0, maxTime)
        case .cycles:
            cycles = clamp(cycles + direction, 1, maxCount)
        case .tabatas:
            tabatas = clamp(tabatas + direction, 1, maxCount)
        }
    }

    private func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(value, lo), hi)
    }

    // MARK: - Running

    func start() {
        guard !isRunning else { return }
        resetRun()
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true

        let startDate = Date()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                self.tick(since: startDate)
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
        resetRun()
    }

    private func resetRun() {
        elapsed = 0
        isFinished = false
    }

    private func tick(since startDate: Date) {
        let newElapsed = Int(Date().timeIntervalSince(startDate))
        guard newElapsed != elapsed else { return }

        let oldPosition = position(at: elapsed)
        elapsed = newElapsed

        if newElapsed >= totalSeconds {
            finish()
        } else if position(at: newElapsed) != oldPosition {
            let synth = AVSpeechSynthesizer()
            let speakIt = AVSpeechUtterance(string: self.currentPosition?.phase.speak ?? "")
            speakIt.rate = 0.3
            speakIt.voice = AVSpeechSynthesisVoice(identifier: "com.apple.speech.synthesis.voice.Ralph")
            synth.speak(speakIt)
        }
    }

    private func finish() {
        ticker?.cancel()
        ticker = nil
        elapsed = totalSeconds
        isRunning = false
        isFinished = true
        UIApplication.shared.isIdleTimerDisabled = false
        playWhistle()   // workout complete
    }
}
