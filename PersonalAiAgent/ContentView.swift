//
//  ContentView.swift
//  PersonalAiAgent
//
//  Created by Raj S on 23/06/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: PersonalAssistantView()) {
                    Label("Personal Assistant", systemImage: "person.crop.circle")
                }
            }
            .navigationTitle("Features")
        }
    }
}

#Preview {
    ContentView()
}
