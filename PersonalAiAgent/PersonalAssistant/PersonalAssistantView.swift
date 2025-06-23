//
//  PersonalAssistantView.swift
//  PersonalAiAgent
//
//  Created by Raj S on 22/06/25.
//

import SwiftUI
import Foundation
import FoundationModels
import AVFoundation
import Combine

struct PersonalAssistantView: View {
    @EnvironmentObject var speechRecognizer: SpeechRecognizer
    /// Controls live speech streaming and spoken range tracking.
    @EnvironmentObject var speechStreamer: SpeechStreamer
    @State private var userPrompt: String = ""
    @State private var llmAnswer: String = ""
    @State private var isListening: Bool = false
    @State private var animatePulse: Bool = false
    
    let session = LanguageModelSession {
        Self.personalAssistantPrompt
    }
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color.purple.opacity(0.7), Color.blue, Color.cyan]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // User's question / prompt area
                promptView
                
                // LLM scrolling output area
                if !llmAnswer.isEmpty {
                    responseView
                } else {
                    Spacer(minLength: 90)
                }

                Spacer()
                
                // Mic/stop button remains at the bottom
                micButtonView
                    .padding(.bottom, 28)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .animation(.smooth, value: isListening)
        .onChange(of: speechRecognizer.recognizedText) {  _, newValue in
            guard !newValue.isEmpty else { return }
            userPrompt = newValue
        }
        .onChange(of: speechRecognizer.isListening) { _, newValue in
            self.isListening = newValue
        }
        .onChange(of: llmAnswer) { _, newValue in
            speechStreamer.enqueueSpeechSegment(with: newValue)
        }
    }
}

private extension PersonalAssistantView {
    var promptView: some View {
        Text(userPrompt.isEmpty ? "Say something!" : userPrompt)
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 1)
    }
    
    var responseView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let (before, spoken, after): (String, String, String) = splitAnswer(for: llmAnswer, range: speechStreamer.spokenRange)
                    let beforeAttr = AttributedString(before, attributes: AttributeContainer().foregroundColor(.white))
                    let spokenAttr = AttributedString(spoken, attributes: AttributeContainer().foregroundColor(.yellow))
                    let afterAttr = AttributedString(after, attributes: AttributeContainer().foregroundColor(Color.white.opacity(0.4)))
                    let composed = beforeAttr + spokenAttr + afterAttr
                    Text(composed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("llmText")
                .font(.title2)
                .multilineTextAlignment(.leading)
                .padding(28)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.18), Color.blue.opacity(0.28)]), startPoint: .top, endPoint: .bottom)
                        .cornerRadius(28)
                )
                .cornerRadius(28)
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)
            .onChange(of: speechStreamer.spokenRange) { _, _ in
                withAnimation(.easeOut(duration: 0.35)) {
                    scrollProxy.scrollTo("llmText", anchor: .bottom)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    var micButtonView: some View {
        ZStack {
            // Animated pulsing ring effect when listening
            if isListening {
                Circle()
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 12)
                    .frame(width: 148, height: 148)
                    .scaleEffect(animatePulse ? 1.15 : 0.95)
                    .opacity(animatePulse ? 0.45 : 0.25)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: animatePulse)
                    .onAppear { animatePulse = true }
                    .onDisappear { animatePulse = false }
            }
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 120, height: 120)
                .shadow(radius: 16)
            Image(systemName: "mic.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(isListening ? Color.red : Color.accentColor)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isListening {
                        speechStreamer.resetSpeech()
                        userPrompt = ""
                        Task { await speechRecognizer.startListening() }
                    }
                }
                .onEnded { _ in
                    if isListening {
                        speechStreamer.resetSpeech()
                        llmAnswer = ""
                        Task { await askLLM(with: speechRecognizer.recognizedText) }
                        speechRecognizer.stopListening()
                    }
                }
        )
    }
}

private extension PersonalAssistantView {
    func askLLM(with prompt: String) async {
        guard !session.isResponding else {
            return
        }
        
        let response = session.streamResponse(to: prompt, generating: PersonalAssistantData.self)
        
        do {
            for try await result in response {
                if let response = result.response {
                    await MainActor.run {
                        self.llmAnswer = response
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.llmAnswer = "LanguageModel error: \(error.localizedDescription)"
            }
        }
    }
    
    func splitAnswer(for answer: String, range: NSRange) -> (String, String, String) {
        let utf16View = answer.utf16
        let startUtf16 = utf16View.index(utf16View.startIndex, offsetBy: range.location, limitedBy: utf16View.endIndex) ?? utf16View.startIndex
        let endUtf16 = utf16View.index(startUtf16, offsetBy: range.length, limitedBy: utf16View.endIndex) ?? startUtf16
        let start = String.Index(startUtf16, within: answer) ?? answer.startIndex
        let end = String.Index(endUtf16, within: answer) ?? start
        let before = String(answer[..<start])
        let spoken = String(answer[start..<end])
        // Limit after to the next 3 words only
        let afterFull = String(answer[end...])
        let words = afterFull.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        var shown = words.prefix(3).joined(separator: " ")
        if afterFull.first == Character(" ") {
            shown = " " + shown
        }
        return (before, spoken, shown)
    }
}

extension PersonalAssistantView {
    static let personalAssistantPrompt: String =   """
    You are a friendly, reliable assistant. Keep tone warm and casual. Make user feel comfortable and understood. All responses must be polite, supportive, and under 200 characters.
    """
}

@Generable
struct PersonalAssistantData {
    let response: String
}
