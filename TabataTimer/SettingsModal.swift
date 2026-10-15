//
//  SettingsModal.swift
//  TabataTimer
//
//  Created by Mike Lewis on 10/14/26.
//

import SwiftUI
import AVFoundation

final class VoiceTester {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, using voice: AVSpeechSynthesisVoice) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }
}

struct SettingsModal: View {
    @Environment(\.dismiss) var dismiss
    @Binding var chosenVoice: AVSpeechSynthesisVoice?
    @State private var selection: AVSpeechSynthesisVoice?
    @State private var tester = VoiceTester()

    private static let voices = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language == "en-US" }

    init(chosenVoice: Binding<AVSpeechSynthesisVoice?>) {
        _chosenVoice = chosenVoice
        _selection = State(initialValue: chosenVoice.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.title)
                    .padding()
                Spacer()
                Button("Accept") {
                    chosenVoice = selection
                    dismiss()
                }
                    .font(.title)
                    .padding()
                    .disabled(selection == nil)
            }
            
            List(Self.voices, id: \.self, selection: $selection) { voice in
                Text("\(voice.name) - \(voice.language)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(voice as AVSpeechSynthesisVoice?)
                    .onTapGesture {
                        selection = voice
                        tester.speak("Work", using: voice)
                    }
            }


        }
    }
}

//#Preview {
//    SettingsModal(chosenVoice: <#T##Binding<AVSpeechSynthesisVoice?>#>)
//}
