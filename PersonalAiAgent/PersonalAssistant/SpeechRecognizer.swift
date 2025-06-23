import Foundation
import Speech
import AVFoundation
import Combine

protocol SpeechRecognizerProtocol: ObservableObject {
    var recognizedText: String { get set }
    var isListening: Bool { get set }
    func startListening() async
    func stopListening()
}

@MainActor
class SpeechRecognizer: ObservableObject, SpeechRecognizerProtocol {
    @Published var recognizedText: String = ""
    @Published var isListening: Bool = false
    
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier))
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    func startListening() async {
        guard !audioEngine.isRunning else { return }
        
        isListening = true
        recognizedText = ""
        await withCheckedContinuation { continuation in
            requestAuthorization { [weak self] authorized in
                guard let self, authorized else {
                    self?.recognizedText = "Speech recognition not authorized."
                    self?.isListening = false
                    continuation.resume()
                    return
                }
                self.startRecording()
                continuation.resume()
            }
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isListening = false
    }
    
    private func startRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            recognizedText = "Audio session setup failed."
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            recognizedText = "Unable to create recognition request."
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            recognizedText = "Audio engine failed to start."
            return
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.recognizedText = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.isListening = false
            }
        }
    }
}
