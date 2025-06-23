//
//  SpeechStreamer.swift
//  PersonalAiAgent
//
//  Created by Raj S on 22/06/25.
//

import SwiftUI
import AVFoundation
import Combine

protocol SpeechStreamerProtocol: ObservableObject {
    var spokenRange: NSRange { get set }
    func enqueueSpeechSegment(with text: String)
    func resetSpeech()
}

/// An ObservableObject that streams speech using AVSpeechSynthesizer, tracking spoken ranges for UI highlighting.
///
/// Usage: Instantiate and call `enqueueSpeechSegment(with:)` to speak new text. Bind to `spokenRange` for progress UI.
final class SpeechStreamer: NSObject, ObservableObject, SpeechStreamerProtocol, AVSpeechSynthesizerDelegate {
    /// The range of the text most recently spoken (for UI highlighting).
    @Published var spokenRange: NSRange = NSRange(location: 0, length: 0)

    private var totalSpokenCharacterCount: Int = 0 {
        didSet { print("totalSpokenCharacterCount \(totalSpokenCharacterCount)") }
    }
    private let synthesizer = AVSpeechSynthesizer()
    private var isSpeaking: Bool = false
    private var lastSpokenText: String = ""
    private var pendingText: String = "" {
        didSet { print("pendingText \(pendingText)") }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    /// Queues and streams a new segment of text to be spoken.
    /// - Parameter text: The full text sequence to be spoken. Only the new portion is spoken.
    func enqueueSpeechSegment(with text: String) {
        guard !text.isEmpty else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.lastSpokenText.isEmpty && text.hasPrefix(self.lastSpokenText) {
                let start = text.index(text.startIndex, offsetBy: self.lastSpokenText.count)
                let diff = String(text[start...])
                guard !diff.isEmpty else { return }
                if self.isSpeaking {
                    self.pendingText = diff
                } else {
                    self.isSpeaking = true
                    let utterance = AVSpeechUtterance(string: diff)
                    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                    utterance.rate = 0.5
                    utterance.volume = 1.0
                    self.synthesizer.speak(utterance)
                    self.lastSpokenText = text
                    self.pendingText = ""
                }
            } else {
                if self.isSpeaking {
                    self.pendingText = text
                } else {
                    self.isSpeaking = true
                    let utterance = AVSpeechUtterance(string: text)
                    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                    utterance.rate = 0.5
                    utterance.volume = 1.0
                    self.synthesizer.speak(utterance)
                    self.lastSpokenText = text
                    self.pendingText = ""
                }
            }
        }
    }

    /// Immediately stops speech and resets all progress state.
    func resetSpeech() {
        totalSpokenCharacterCount = 0
        synthesizer.stopSpeaking(at: .immediate)
        lastSpokenText = ""
        pendingText = ""
        isSpeaking = false
        spokenRange = NSRange(location: 0, length: 0)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            print("didFinish \(utterance.speechString)")
            self.totalSpokenCharacterCount += utterance.speechString.count
            if !self.pendingText.isEmpty {
                self.isSpeaking = true
                let utterance = AVSpeechUtterance(string: self.pendingText)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.5
                utterance.volume = 1.0
                self.synthesizer.speak(utterance)
                self.lastSpokenText += self.pendingText
                self.pendingText = ""
            } else {
                self.isSpeaking = false
                self.spokenRange = NSRange(location: 0, length: 0)
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString charRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.spokenRange = NSRange(location: charRange.location + self.totalSpokenCharacterCount, length: charRange.length)
        }
    }
}

