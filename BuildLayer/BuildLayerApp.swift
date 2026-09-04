//
//  BuildLayerApp.swift
//  BuildLayer
//
//  App entry point. Launches straight into the flow coordinator:
//  Splash → Onboarding (first launch only) → Main App. No auth, no account.
//

import SwiftUI

@main
struct BuildLayerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
