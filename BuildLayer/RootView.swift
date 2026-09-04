//
//  RootView.swift
//  BuildLayer
//
//  Flow coordinator: Splash → (first launch) Onboarding → Main App.
//  Owns the app-wide environment objects and applies the chosen appearance.
//

import SwiftUI

enum AppPhase { case splash, onboarding, main }

struct RootView: View {
    @StateObject private var appState = AppState()
    @StateObject private var store = ElementStore()
    @StateObject private var toast = ToastCenter()
    @StateObject private var notifier = NotificationManager.shared

    @State private var phase: AppPhase = .splash

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                LaunchView {
                    phase = appState.hasCompletedOnboarding ? .main : .onboarding
                }
                .transition(.opacity)

            case .onboarding:
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.5)) { phase = .main }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))

            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .environmentObject(appState)
        .environmentObject(store)
        .environmentObject(toast)
        .environmentObject(notifier)
        .environment(\.unitFormatter, appState.fmt)
        .preferredColorScheme(appState.appearance.scheme)
        .overlay(ToastOverlay(center: toast))
        .onAppear { notifier.refreshAuthorization() }
        // Writes are debounced, so anything still queued has to be committed
        // before the app can be suspended and killed.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification)) { _ in
            store.flushPendingWrites()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            notifier.refreshAuthorization()
            notifier.pruneDeliveredReminders(store)
        }
    }
}
