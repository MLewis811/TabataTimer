//
//  SettingsModal.swift
//  TabataTimer
//
//  Created by Mike Lewis on 10/14/26.
//

import SwiftUI
import AVFoundation

struct SettingsModal: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var selection: AVSpeechSynthesisVoice?
    
    private let synth = AVSpeechSynthesizer()
    private let allVoices = AVSpeechSynthesisVoice.speechVoices()
    
    var body: some View {
        List(allVoices, id: \.self, selection: $selection) { voice in
            Text(voice.name)
//                .tag(voice as AVSpeechSynthesisVoice?)
                .onTapGesture {
                    selection = voice
                    speakTestWord(using: voice)
                }
        }
        
        Button("Press to dismiss") {
            dismiss()
        }
        .font(.title)
        .padding()
        .foregroundStyle(.white)
        .background(.black)
    }
    
    private func speakTestWord(using voice: AVSpeechSynthesisVoice) {
        let utterance = AVSpeechUtterance(string: "Work")
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }
}

#Preview {
    SettingsModal()
}
