//
//  MyProfileView.swift
//  Haki
//
//  The Profile tab: your own profile, with Activity and Settings in the
//  toolbar.
//

import Foundation
import SwiftUI

struct MyProfileView: View {
    @Environment(AuthService.self) private var auth

    @State private var showingSettings = false

    init() {}

    var body: some View {
        NavigationStack {
            Group {
                if let userID = auth.userID {
                    ProfileView(userID: userID, isTabRoot: true)
                } else {
                    signedOut
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        ActivityView()
                    } label: {
                        Image(systemName: "heart")
                    }
                    .accessibilityLabel("Activity")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var signedOut: some View {
        ContentUnavailableView(
            "You're signed out",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Sign in to see your profile, posts and portfolio.")
        )
        .navigationTitle("Profile")
    }
}

#Preview {
    MyProfileView()
        .previewEnvironment()
}
