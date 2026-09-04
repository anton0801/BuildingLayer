//
//  SettingsView.swift
//  BuildLayer
//
//  Every control is wired: appearance recolours the whole app, units/currency
//  flow into calculations, notifications hit UNUserNotificationCenter, haptics
//  toggle real feedback, and data is erased locally on request.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var notifier: NotificationManager

    @State private var showEraseAlert = false

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Appearance
                    settingsCard(title: "Appearance", icon: Icon.circleHalf) {
                        VStack(spacing: 10) {
                            ForEach(AppearanceMode.allCases) { mode in
                                appearanceRow(mode)
                            }
                        }
                    }

                    // Units & currency
                    settingsCard(title: "Units & Currency", icon: Icon.ruler) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("UNIT SYSTEM").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                            ChipSelector(options: UnitSystem.allCases, selection: unitBinding, label: { $0.rawValue })
                            Text("Values are stored in SI and converted for display, so switching back and forth never changes your data.")
                                .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("CURRENCY").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                            ChipSelector(options: Currency.allCases, selection: currencyBinding,
                                         label: { "\($0.symbol) \($0.rawValue)" })
                        }
                    }

                    // Defaults — these actually feed the calculations now, so
                    // they are editable rather than buried constants.
                    settingsCard(title: "Calculation Defaults", icon: Icon.uValue) {
                        VStack(alignment: .leading, spacing: 14) {
                            BLNumberField(label: "Default Target U",
                                          value: UnitBinding.uValue(defaultTargetBinding, appState.fmt),
                                          suffix: appState.fmt.uSuffix,
                                          format: appState.fmt.isMetric ? "%.2f" : "%.3f",
                                          range: InputRange.uValue)
                            BLNumberField(label: "Heating hours per season",
                                          value: heatingHoursBinding, suffix: "h",
                                          format: "%.0f", range: 0...8760)
                            BLNumberField(label: "Energy price (\(appState.currency.symbol)/kWh)",
                                          value: energyPriceBinding, format: "%.2f", range: InputRange.price)
                            Text("Heating hours and energy price drive every kWh, cost and payback figure in the app. 4380 h is roughly half a year.")
                                .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Notifications
                    settingsCard(title: "Reminders", icon: Icon.bell) {
                        VStack(spacing: 12) {
                            Toggle(isOn: notificationsBinding) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable reminders").font(.bl(15, .bold)).foregroundColor(Theme.cardText)
                                    Text(notifier.authorized ? "Notifications allowed" : "Tap to request permission")
                                        .font(.bl(11, .semibold)).foregroundColor(Theme.cardSubtext)
                                }
                            }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                            Toggle(isOn: $appState.hapticsEnabled) {
                                Text("Haptic feedback").font(.bl(15, .bold)).foregroundColor(Theme.cardText)
                            }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                            GhostButton(title: "Send Test Notification", icon: Icon.bell) {
                                notifier.requestAuthorization { ok in
                                    DispatchQueue.main.async {
                                        if ok { notifier.confirm("Build Layer", "Test reminder — notifications work."); toast.flash("Test scheduled (5s)", icon: Icon.bell) }
                                        else { toast.flash("Permission denied", icon: Icon.warning) }
                                    }
                                }
                            }
                        }
                    }

                    // Data
                    settingsCard(title: "Data", icon: Icon.doc) {
                        VStack(spacing: 12) {
                            dataRow("Elements stored", "\(store.elements.count)")
                            dataRow("Layers", "\(store.elements.reduce(0) { $0 + $1.layers.count })")
                            dataRow("Materials", "\(store.materials.count) (\(store.materials.filter { $0.isCustom }.count) custom)")
                            dataRow("Reminders", "\(store.reminders.count)")
                            dataRow("Photos", "\(photoCount) · \(photoSizeText)")
                            DangerButton(title: "Erase All Data") { showEraseAlert = true }
                        }
                    }

                    // About
                    settingsCard(title: "About", icon: Icon.info) {
                        VStack(alignment: .leading, spacing: 8) {
                            dataRow("Version", Bundle.main.appVersionText)
                            dataRow("Storage", "On-device only")
                            dataRow("Units", appState.units.rawValue)
                            Divider().background(Theme.cardBorder)
                            Text("Estimative only. U-values and exact compliance follow your regional standards / project. Everything is stored locally — no account, no cloud.")
                                .font(.bl(12, .medium)).foregroundColor(Theme.cardSubtext)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 40)
            }
        }
        .navigationBarTitle("Settings", displayMode: .inline)
        .alert(isPresented: $showEraseAlert) {
            Alert(title: Text("Erase all data?"),
                  message: Text("This removes all elements, reminders and history. Materials reset to defaults. This cannot be undone."),
                  primaryButton: .destructive(Text("Erase")) {
                      notifier.cancelAll(); store.eraseAll(); appState.haptic(.heavy)
                      toast.flash("All data erased", icon: Icon.trash)
                  },
                  secondaryButton: .cancel())
        }
        .onAppear { notifier.refreshAuthorization() }
    }

    // MARK: Rows

    private func appearanceRow(_ mode: AppearanceMode) -> some View {
        let active = appState.appearance == mode
        return Button {
            appState.appearanceRaw = mode.rawValue
            appState.haptic()
            toast.flash("\(mode.rawValue) theme", icon: mode.icon)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon).font(.system(size: 17, weight: .bold))
                    .foregroundColor(active ? Theme.buttonText : Theme.primary)
                    .frame(width: 40, height: 40)
                    .background(ZStack { if active { Theme.primaryGradient } else { Theme.cardBlue } })
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                Text(mode.rawValue).font(.bl(15, .bold)).foregroundColor(Theme.cardText)
                Spacer()
                Image(systemName: active ? Icon.check : "circle")
                    .font(.system(size: 19, weight: .bold)).foregroundColor(active ? Theme.pass : Theme.cardInactive)
            }
            .padding(10)
            .background(active ? Theme.cardBlue : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(PressableStyle(scale: 0.98))
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
            Spacer()
            Text(value).font(.bl(14, .bold)).foregroundColor(Theme.cardText)
        }
    }

    private func settingsCard<C: View>(title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        BLCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.primary)
                    Text(title).font(.bl(16, .heavy)).foregroundColor(Theme.cardText)
                }
                content()
            }
        }
    }

    // MARK: Bindings

    private var unitBinding: Binding<UnitSystem> {
        Binding(get: { appState.units }, set: { system in
            appState.unitRaw = system.rawValue
            appState.haptic()
            // The setting existed but nothing consumed it — every screen printed
            // m², mm and °C regardless. It now drives all display and entry.
            toast.flash("Showing \(system == .metric ? "metric" : "imperial") units", icon: Icon.ruler)
        })
    }
    private var currencyBinding: Binding<Currency> {
        Binding(get: { appState.currency }, set: { appState.currencyRaw = $0.rawValue; appState.haptic()
            toast.flash("Currency \($0.rawValue)", icon: Icon.money) })
    }
    private var defaultTargetBinding: Binding<Double> {
        Binding(get: { appState.defaultTargetU }, set: { appState.defaultTargetU = $0 })
    }
    private var heatingHoursBinding: Binding<Double> {
        Binding(get: { appState.heatingHours }, set: { appState.heatingHours = $0 })
    }
    private var energyPriceBinding: Binding<Double> {
        Binding(get: { appState.energyPrice }, set: { appState.energyPrice = $0 })
    }

    private var photoCount: Int { store.elements.filter { $0.photoData != nil }.count }
    private var photoSizeText: String {
        let bytes = store.elements.compactMap { $0.photoData?.count }.reduce(0, +)
        return ImageStore.sizeText(bytes > 0 ? Data(count: bytes) : nil)
    }
    private var notificationsBinding: Binding<Bool> {
        Binding(get: { appState.notificationsEnabled }, set: { on in
            appState.notificationsEnabled = on
            if on {
                notifier.requestAuthorization { ok in
                    DispatchQueue.main.async { toast.flash(ok ? "Reminders on" : "Permission needed", icon: ok ? Icon.bell : Icon.warning) }
                }
            } else {
                notifier.cancelAll(); toast.flash("Reminders off", icon: Icon.bell)
            }
        })
    }
}


// MARK: - Bundle version

extension Bundle {
    /// Reads the real version from the bundle instead of the hard-coded "1.0"
    /// that would have gone stale on the first update.
    var appVersionText: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
