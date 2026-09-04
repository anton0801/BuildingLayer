//
//  MainTabView.swift
//  BuildLayer
//
//  Custom themed tab bar (5 tabs) hosting the functional screens. Each tab is a
//  NavigationView so sub-screens push naturally; the floating bar matches the
//  dark-navy theme. Settings is reached from each tab's nav bar gear.
//

import SwiftUI

enum Tab: Int, CaseIterable {
    case elements, layers, uValue, insulation, reports
    var title: String {
        switch self {
        case .elements:   return "Elements"
        case .layers:     return "Layers"
        case .uValue:     return "U-Value"
        case .insulation: return "Insulation"
        case .reports:    return "Reports"
        }
    }
    var icon: String {
        switch self {
        case .elements:   return Icon.elements
        case .layers:     return Icon.layers
        case .uValue:     return Icon.uValue
        case .insulation: return Icon.insulation
        case .reports:    return Icon.reports
        }
    }
}

struct MainTabView: View {
    @State private var tab: Tab = .elements
    @EnvironmentObject var appState: AppState

    init() {
        // Theme the native navigation bar to match (adaptive dark/light).
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 1)
                                          : UIColor(red: 0.92, green: 0.95, blue: 0.99, alpha: 1)
        }
        let titleColor = UIColor { t in t.userInterfaceStyle == .dark ? .white : UIColor(red: 0.06, green: 0.16, blue: 0.29, alpha: 1) }
        nav.titleTextAttributes = [.foregroundColor: titleColor]
        nav.largeTitleTextAttributes = [.foregroundColor: titleColor]
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(red: 0.97, green: 0.48, blue: 0.11, alpha: 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .elements:   ElementsView()
                case .layers:     LayersView()
                case .uValue:     UValueView()
                case .insulation: InsulationView()
                case .reports:    ReportsView()
                }
            }
            CustomTabBar(selected: $tab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Custom tab bar

struct CustomTabBar: View {
    @Binding var selected: Tab
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                let active = t == selected
                Button {
                    appState.haptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selected = t }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if active {
                                Circle().fill(Theme.primaryGradient)
                                    .frame(width: 40, height: 40)
                                    .shadow(color: Theme.warmGlow, radius: 8, y: 3)
                            }
                            Image(systemName: t.icon)
                                .font(.system(size: active ? 17 : 18, weight: .bold))
                                .foregroundColor(active ? Theme.buttonText : Theme.titleDim)
                        }
                        .frame(height: 40)
                        Text(t.title)
                            .font(.system(size: 10, weight: active ? .bold : .semibold, design: .rounded))
                            .foregroundColor(active ? Theme.primary : Theme.titleDim)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 6)
        .padding(.horizontal, 8)
        .background(
            Theme.bgDeep
                .opacity(0.98)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 1))
                .shadow(color: Theme.shadow, radius: 16, y: -2)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Shared element picker (horizontal selector used by calc tabs)

struct ElementPicker: View {
    @EnvironmentObject var store: ElementStore
    @Binding var selectedID: UUID?

    var body: some View {
        if store.elements.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.elements) { el in
                        let active = el.id == selectedID
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selectedID = el.id }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: el.type.icon).font(.system(size: 13, weight: .bold))
                                Text(el.name).font(.bl(13, .bold)).lineLimit(1)
                            }
                            .foregroundColor(active ? Theme.buttonText : Theme.subtitle)
                            .padding(.vertical, 9).padding(.horizontal, 14)
                            .background(ZStack { if active { Theme.primaryGradient } else { Theme.bgSoft } })
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(active ? Color.clear : Theme.divider, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

// MARK: - Settings gear toolbar item

struct SettingsLink: View {
    var body: some View {
        NavigationLink(destination: SettingsView()) {
            Image(systemName: Icon.settings)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Theme.primary)
        }
    }
}

// MARK: - Number formatting helpers
//
// Unit-bearing values go through AppState.fmt (UnitFormatter) so they follow the
// Metric/Imperial setting. Only this dimensionless helper is still global.

func fmt0(_ v: Double) -> String { String(format: "%.0f", finite(v)) }
