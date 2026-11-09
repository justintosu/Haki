//
//  AssistantToolbarButton.swift
//  Haki
//
//  The sparkle "Ask Haki" button in every tab's top bar. Opens the
//  assistant in a sheet.
//

import Foundation
import SwiftUI

struct AssistantToolbarButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Ask Haki", systemImage: "sparkles")
        }
        .accessibilityLabel("Ask Haki")
        .accessibilityHint("Ask about your money, health, workouts, notes or wardrobe")
        .sheet(isPresented: $isPresented) {
            AssistantChatView()
        }
    }
}
