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

    @Published var voice: AVSpeechSynthesisVoice?
    private var ticker: Task<Void, Never>?
    private var whistle: AVAudioPlayer?

    private let synth = AVSpeechSynthesizer()
    
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.3
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }
    
    private func prewarmSpeech() {
        let utterance = AVSpeechUtterance(string: " ")
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 0
        
        synth.speak(utterance)
    }
    
    private lazy var beepPlayer: AVAudioPlayer? = Self.makeBeepPlayer()
    
    private func playBeep() {
            self.beepPlayer?.currentTime = 0
            self.beepPlayer?.play()
    }
    
    /// 1...3 if the position changes within the next three seconds, otherwise nil.
    private func secondsUntilChange(from t: Int) -> Int? {
        let current = position(at: t)
        for k in 1...3 where position(at: t + k) != current {
            return k   // also true when t + k is past the end (position is nil)
        }
        return nil
    }
    
    private static func makeBeepPlayer() -> AVAudioPlayer? {
        let sampleRate = 44100
        let frequency = 880.0
        let count = sampleRate * 15 / 100
        let fadeSamples = Double(sampleRate) / 100
        
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        
        let dataSize = UInt32(count * 2)
        
        data.append(contentsOf: Array("RIFF".utf8)); put(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(sampleRate)); put(UInt32(sampleRate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(dataSize)

        for i in 0..<count {
            let envelope = min(1.0, Double(min(i, count - i)) / fadeSamples)
            let wave = sin(2 * .pi * frequency * Double(i) / Double(sampleRate))
            put(Int16(wave * envelope * 0.6 * Double(Int16.max)))
        }

        let player = try? AVAudioPlayer(data: data)
        player?.prepareToPlay()
        return player
    }
    
    init() {
//        if let url = Bundle.main.url(forResource: "whistle", withExtension: "wav") {
//            whistle = try? AVAudioPlayer(contentsOf: url)
//            whistle?.prepareToPlay()
//        }
    }

//    private func playWhistle() {
//        activateAudioSessionIfNeeded { [weak self] in
//            guard let self = self, let whistle = self.whistle else { return }
//            whistle.currentTime = 0   // restart if it's still playing from the last phase change
//            whistle.play()
//        }
//    }

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
        prewarmSpeech()

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
            speak(position(at: newElapsed)?.phase.speak ?? "")
        } else if secondsUntilChange(from: newElapsed) != nil {
            playBeep()
        }
    }

    private func finish() {
        ticker?.cancel()
        ticker = nil
        elapsed = totalSeconds
        isRunning = false
        isFinished = true
        UIApplication.shared.isIdleTimerDisabled = false
//        playWhistle()   // workout complete
    }
}

