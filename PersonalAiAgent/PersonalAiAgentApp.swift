//
//  PersonalAiAgentApp.swift
//  PersonalAiAgent
//
//  Created by Raj S on 22/06/25.
//

import SwiftUI

@main
struct PersonalAiAgentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SpeechRecognizer())
                .environmentObject(SpeechStreamer())
        }
    }
}
