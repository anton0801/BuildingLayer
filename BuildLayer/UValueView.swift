//
//  UValueView.swift
//  BuildLayer
//
//  Tab 3 — U-Value. Screen 05 R & U Calc + 07 Condensation, 08 Thermal Bridge,
//  09 Existing vs Upgraded, 10 Heat Loss.
//

import SwiftUI

// MARK: - U-Value tab

struct UValueView: View {
    @EnvironmentObject var store: ElementStore
    @State private var selectedID: UUID?

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                if store.elements.isEmpty {
                    EmptyState(icon: Icon.uValue, title: "Nothing to calculate",
                               message: "Create an element and add layers to compute R and U.")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ElementPicker(selectedID: $selectedID)
                            if let id = resolvedID {
                                // .id(id) forces a fresh subtree per element —
                                // without it the screen kept the previous
                                // element's field state while writing to the new one.
                                RUCalcBody(elementID: id).id(id)
                            }
                        }
                        .padding(.top, 10).padding(.bottom, 110)
                    }
                }
            }
            .navigationBarTitle("R & U Calc", displayMode: .inline)
            .navigationBarItems(trailing: SettingsLink())
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { if selectedID == nil { selectedID = store.elements.first?.id } }
    }
    private var resolvedID: UUID? {
        if let id = selectedID, store.elements.contains(where: { $0.id == id }) { return id }
        return store.elements.first?.id
    }
}

// MARK: - 05  R & U Calc (pushable + body)

struct RUCalcView: View {
    let elementID: UUID
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                RUCalcBody(elementID: elementID).padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("R & U Calc", displayMode: .inline)
    }
}

struct RUCalcBody: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID
    @State private var pulse = false

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let r = ThermalEngine.result(for: el)
        let pass = r.passesTarget && !el.layers.isEmpty

        return VStack(spacing: 16) {
            // Headline result
            BLCard {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("U-VALUE").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                            Text(el.layers.isEmpty ? "—" : f.uText(r.uValue))
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundColor(pass ? Theme.pass : Theme.fail)
                                .scaleEffect(pulse ? 1.06 : 1.0)
                                .minimumScaleFactor(0.5).lineLimit(1)
                            Text(f.uSuffix).font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            metric("Total R", f.rText(r.totalR))
                            metric("Target U", f.uText(el.targetU))
                            HStack(spacing: 5) {
                                Image(systemName: pass ? Icon.check : Icon.warning)
                                Text(el.layers.isEmpty ? "No layers" : (pass ? "Pass" : "Fail")).font(.bl(13, .bold))
                            }
                            .foregroundColor(.white).padding(.vertical, 5).padding(.horizontal, 11)
                            .background(el.layers.isEmpty ? Theme.progress : (pass ? Theme.pass : Theme.fail))
                            .clipShape(Capsule())
                        }
                    }
                    RScaleBar(currentR: r.totalR, targetR: 1.0 / max(el.targetU, 0.01)).frame(height: 14)
                }
            }.padding(.horizontal, 18)

            // Contribution breakdown
            if !el.layers.isEmpty {
                BLCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LAYER CONTRIBUTION TO R").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                        ForEach(r.contributions) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(c.name).font(.bl(13, .semibold)).foregroundColor(Theme.cardText).lineLimit(1)
                                    Spacer()
                                    Text("\(f.rText(c.resistance)) · \(safeInt(finite(c.fraction) * 100, min: 0, max: 100))%")
                                        .font(.bl(12, .bold)).foregroundColor(c.isInsulation ? Theme.insulation : Theme.cardSubtext)
                                }
                                GeometryReader { geo in
                                    Capsule().fill(c.isInsulation ? Theme.insulation : Theme.layer)
                                        .frame(width: max(6, safeLength(Double(geo.size.width) * finite(c.fraction))), height: 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Capsule().fill(Theme.cardBlue))
                                }.frame(height: 8)
                            }
                        }
                    }
                }.padding(.horizontal, 18)
            }

            BLCard {
                VStack(spacing: 12) {
                    BLNumberField(label: "Target U", value: UnitBinding.uValue(targetBinding, f),
                                  suffix: f.uSuffix, format: f.isMetric ? "%.2f" : "%.3f",
                                  range: InputRange.uValue)
                    Text("Sum R, get U, compare to target. Dominant layer: \(r.dominantLayer).")
                        .font(.bl(12, .medium)).foregroundColor(Theme.cardSubtext)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.horizontal, 18)

            VStack(spacing: 10) {
                PrimaryButton(title: "Calculate U", icon: Icon.uValue) {
                    store.refreshStatus(for: elementID)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pulse = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { pulse = false } }
                    appState.haptic(.medium)
                    toast.flash(el.layers.isEmpty ? "Add layers first" : "U = \(f.uText(r.uValue)) \(f.uSuffix)", icon: Icon.uValue)
                }
                HStack(spacing: 10) {
                    SecondaryButton(title: "Keep Calc", icon: Icon.doc) {
                        store.refreshStatus(for: elementID); appState.haptic(); toast.flash("Saved", icon: Icon.doc)
                    }
                    NavigationLink(destination: InsulationThicknessView(elementID: elementID)) {
                        HStack { Image(systemName: Icon.insulation); Text("Insulation").font(.bl(14, .bold)) }
                            .foregroundColor(Theme.buttonText).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(PressableStyle())
                }
                HStack(spacing: 10) {
                    subLink("Condensation", Icon.drop, Theme.cold, CondensationView(elementID: elementID))
                    subLink("Heat Loss", Icon.bolt, Theme.primary, HeatLossView(elementID: elementID))
                }
                HStack(spacing: 10) {
                    subLink("Thermal Bridge", Icon.warning, Theme.warn, ThermalBridgeView(elementID: elementID))
                    subLink("Before/After", Icon.chart, Theme.layer, ExistingVsUpgradedView(elementID: elementID))
                }
            }.padding(.horizontal, 18)
        }
    }

    private var targetBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.targetU ?? 0.3 },
                set: { v in
                    store.mutate(elementID) { $0.targetU = v; $0.dateModified = Date() }
                    store.refreshStatus(for: elementID)
                })
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.bl(11, .semibold)).foregroundColor(Theme.cardSubtext)
            Text(value).font(.bl(15, .heavy)).foregroundColor(Theme.cardText)
        }
    }
    private func subLink<D: View>(_ title: String, _ icon: String, _ color: Color, _ dest: D) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.bl(13, .bold))
            }
            .foregroundColor(color).frame(maxWidth: .infinity).padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.5), lineWidth: 1.3))
        }.buttonStyle(PressableStyle(scale: 0.98))
    }
}

// MARK: - 07  Condensation Check

struct CondensationView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let interfaces = ThermalEngine.interfaceTemperatures(of: el)
        let verdict = ThermalEngine.condensation(of: el)

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: verdict.atRisk ? Icon.drop : Icon.check)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(verdict.atRisk ? Theme.cold : Theme.pass)
                                Text(verdict.atRisk ? "Condensation Risk" : "No Condensation")
                                    .font(.bl(18, .heavy)).foregroundColor(Theme.cardText)
                                Spacer()
                            }
                            if el.layers.isEmpty {
                                Text("Add layers to run the check.")
                                    .font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
                            } else {
                                Text("Worst point: \(verdict.riskLayer)")
                                    .font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
                                HStack(spacing: 14) {
                                    metricChip("PEAK RH", "\(safeInt(verdict.peakRH, min: 0, max: 999))%",
                                               verdict.atRisk ? Theme.fail : (verdict.peakRH >= 90 ? Theme.warn : Theme.pass))
                                    metricChip("HEADROOM", f.deltaTText(verdict.minMargin),
                                               verdict.minMargin <= 0 ? Theme.fail : Theme.pass)
                                }
                            }
                            if !el.layers.isEmpty {
                                WallCrossSection(layers: el.layers, showHeatArrow: true, height: 90, atRisk: verdict.atRisk)
                            }
                        }
                    }.padding(.horizontal, 18)

                    BLCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TEMPERATURE & LOCAL HUMIDITY").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                Spacer()
                                Text("100% = wet").font(.bl(10, .bold)).foregroundColor(Theme.cardInactive)
                            }
                            if interfaces.isEmpty {
                                Text("Add layers to run the check.").font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            } else {
                                Text("Vapour pressure falls across the build-up in proportion to each layer's µ value. Condensation is predicted where the local humidity reaches 100%. The outdoor face sits in outside air, so it is greyed and left out of the verdict.")
                                    .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(interfaces) { itf in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(itf.countsForRisk
                                              ? (itf.atRisk ? Theme.fail : (itf.isTight ? Theme.warn : Theme.pass))
                                              : Theme.cardInactive)
                                        .frame(width: 8, height: 8)
                                    Text(itf.label).font(.bl(12, .semibold))
                                        .foregroundColor(itf.countsForRisk ? Theme.cardText : Theme.cardInactive)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: 4)
                                    Text(f.tempText(itf.temperature)).font(.bl(13, .bold))
                                        .foregroundColor(itf.atRisk ? Theme.fail : Theme.cardText)
                                    Text("\(safeInt(itf.localRH, min: 0, max: 999))%")
                                        .font(.bl(12, .heavy))
                                        .foregroundColor(itf.countsForRisk
                                                         ? (itf.atRisk ? Theme.fail : (itf.isTight ? Theme.warn : Theme.pass))
                                                         : Theme.cardInactive)
                                        .frame(width: 44, alignment: .trailing)
                                }
                            }
                        }
                    }.padding(.horizontal, 18)

                    BLCard(tint: verdict.atRisk ? Color(hex: "FBE9E9") : Theme.cardBlue) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: Icon.info).foregroundColor(verdict.atRisk ? Theme.fail : Theme.layer)
                            Text(verdict.recommendation).font(.bl(13, .semibold)).foregroundColor(Theme.cardText)
                        }
                    }.padding(.horizontal, 18)

                    BLCard {
                        VStack(spacing: 12) {
                            Toggle(isOn: vaporBinding) {
                                Text("Vapor control layer fitted").font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                            }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                            HStack(spacing: 12) {
                                BLNumberField(label: "Inside", value: UnitBinding.temp(insideBinding, f),
                                              suffix: f.tempSuffix, format: "%.0f", range: InputRange.tempC)
                                BLNumberField(label: "Indoor RH", value: rhBinding, suffix: "%",
                                              format: "%.0f", range: InputRange.humidity)
                            }
                            HStack(spacing: 12) {
                                BLNumberField(label: "Outside", value: UnitBinding.temp(outsideBinding, f),
                                              suffix: f.tempSuffix, format: "%.0f", range: InputRange.tempC)
                                BLNumberField(label: "Outdoor RH", value: outdoorRHBinding, suffix: "%",
                                              format: "%.0f", range: InputRange.humidity)
                            }
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Run Check", icon: Icon.drop) {
                            store.refreshStatus(for: elementID); appState.haptic(.medium)
                            toast.flash(verdict.atRisk ? "Risk found" : "No condensation", icon: Icon.drop)
                        }
                        NavigationLink(destination: ThermalBridgeView(elementID: elementID)) {
                            HStack { Image(systemName: Icon.warning); Text("Open Thermal Bridge").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.warn).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.warn.opacity(0.5), lineWidth: 1.3))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Condensation Check", displayMode: .inline)
    }

    private func metricChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.bl(9, .bold)).foregroundColor(Theme.cardSubtext)
            Text(value).font(.bl(16, .heavy)).foregroundColor(color)
        }
    }

    private var vaporBinding: Binding<Bool> {
        Binding(get: { store.element(elementID)?.hasVaporControl ?? false },
                set: { v in
                    store.mutate(elementID) { $0.hasVaporControl = v; $0.dateModified = Date() }
                    store.refreshStatus(for: elementID)
                })
    }
    private var insideBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.insideTemp ?? 20 },
                set: { v in
                    store.mutate(elementID) { $0.insideTemp = v; $0.dateModified = Date() }
                    store.refreshStatus(for: elementID)
                })
    }
    private var outsideBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.outsideTemp ?? -5 },
                set: { v in
                    store.mutate(elementID) { $0.outsideTemp = v; $0.dateModified = Date() }
                    store.refreshStatus(for: elementID)
                })
    }
    private var outdoorRHBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.outdoorRH ?? 85 },
                set: { v in
                    store.mutate(elementID) { $0.outdoorRH = v; $0.dateModified = Date() }
                    store.refreshStatus(for: elementID)
                })
    }
    private var rhBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.indoorRH ?? 55 },
                set: { v in
                    store.mutate(elementID) { $0.indoorRH = v; $0.dateModified = Date() }
                    store.refreshStatus(for: elementID)
                })
    }
}

// MARK: - 08  Thermal Bridge Note

struct ThermalBridgeView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    @State private var source = "Timber studs"
    @State private var severity = 2.0
    @State private var fix = ""

    private let sources = ["Timber studs", "Steel lintel", "Balcony", "Junction", "Fixings"]

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let baseU = ThermalEngine.uValue(of: el)
        let uplift = severity * 0.06          // each severity step ≈ +6% effective U
        let realU = baseU * (1 + uplift)

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SMOOTH U").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                                Text(f.uText(baseU)).font(.bl(24, .heavy)).foregroundColor(Theme.cardText)
                                    .minimumScaleFactor(0.6).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: Icon.arrowR).foregroundColor(Theme.warn)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("REAL U (w/ bridge)").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                                Text(f.uText(realU)).font(.bl(24, .heavy)).foregroundColor(Theme.warn)
                                    .minimumScaleFactor(0.6).lineLimit(1)
                            }
                        }
                    }.padding(.horizontal, 18)

                    BLCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Flag thermal bridges in the buildup.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("BRIDGE SOURCE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                ChipSelector(options: sources, selection: $source, label: { $0 })
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text("EFFECT ON U").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext); Spacer()
                                    Text("+\(safeInt(uplift * 100, min: 0, max: 999))%").font(.bl(14, .heavy)).foregroundColor(Theme.warn) }
                                Slider(value: $severity, in: 1...5, step: 1).accentColor(Theme.warn)
                            }
                            BLField(label: "Fix", placeholder: "e.g. insulated dpc / thermal break", text: $fix)
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Save Bridge", icon: Icon.check) { save(realU: realU) }
                        NavigationLink(destination: ExistingVsUpgradedView(elementID: elementID)) {
                            HStack { Image(systemName: Icon.chart); Text("Open Existing vs Upgraded").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.layer).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.layer.opacity(0.5), lineWidth: 1.3))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Thermal Bridge", displayMode: .inline)
    }

    private func save(realU: Double) {
        guard let e = store.element(elementID) else { return }
        let action = fix.trimmingCharacters(in: .whitespaces)
        let note = "Bridge [\(source)] +\(safeInt(severity * 6))% → real U \(appState.fmt.uText(realU)) \(appState.fmt.uSuffix)"
            + (action.isEmpty ? "" : ". Fix: \(action)")
        store.appendNote(note, to: elementID)
        // Held as a manual status so the next recalculation does not drop it.
        if safeInt(severity) >= 4 {
            store.mutate(elementID) { $0.manualStatus = .attention }
        }
        store.mutate(elementID) { $0.dateModified = Date() }
        store.refreshStatus(for: elementID)
        store.log("Thermal bridge noted", "\(e.name): \(source)", Icon.warning)
        appState.haptic(.medium); toast.flash("Bridge saved", icon: Icon.check)
    }
}

// MARK: - 09  Existing vs Upgraded

struct ExistingVsUpgradedView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let upgraded = ThermalEngine.uValue(of: el)
        // 1.6 is a stand-in for "uninsulated masonry" until a real figure is
        // entered; it is now labelled as an assumption rather than presented as
        // if the user had supplied it.
        let usingDefault = !(el.existingU > 0)
        let existing = usingDefault ? 1.6 : el.existingU
        let improvement = ThermalEngine.improvementPercent(existingU: existing, upgradedU: upgraded)

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(spacing: 14) {
                            Text("Compare the U before and after upgrade.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(alignment: .bottom, spacing: 24) {
                                barColumn("Existing", existing, max(existing, upgraded), Theme.fail)
                                barColumn("Upgraded", upgraded, max(existing, upgraded), Theme.pass)
                            }
                            .frame(height: 170).frame(maxWidth: .infinity)
                            HStack {
                                Image(systemName: Icon.arrowUpR).foregroundColor(Theme.pass)
                                Text("\(safeInt(improvement, min: 0, max: 100))% better")
                                    .font(.bl(18, .heavy)).foregroundColor(Theme.pass)
                                Spacer()
                            }
                            if usingDefault {
                                Text("Using an assumed 1.6 \(f.uSuffix) for the existing build-up. Enter the real value below.")
                                    .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding(.horizontal, 18)

                    BLCard {
                        BLNumberField(label: "Existing U (before)",
                                      value: UnitBinding.uValue(existingBinding, f),
                                      suffix: f.uSuffix, format: f.isMetric ? "%.2f" : "%.3f",
                                      range: InputRange.uValue)
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Compare", icon: Icon.chart) {
                            appState.haptic(.medium); toast.flash("\(Int(improvement))% improvement", icon: Icon.chart)
                        }
                        NavigationLink(destination: HeatLossView(elementID: elementID)) {
                            HStack { Image(systemName: Icon.bolt); Text("Open Heat Loss").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.primary).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.primary.opacity(0.5), lineWidth: 1.3))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Existing vs Upgraded", displayMode: .inline)
    }

    private var existingBinding: Binding<Double> {
        Binding(get: { let e = store.element(elementID); return (e?.existingU ?? 0) > 0 ? e!.existingU : 1.6 },
                set: { v in store.mutate(elementID) { $0.existingU = v; $0.dateModified = Date() } })
    }
    private func barColumn(_ label: String, _ value: Double, _ maxVal: Double, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Text(appState.fmt.uText(value)).font(.bl(15, .heavy)).foregroundColor(color)
                .minimumScaleFactor(0.6).lineLimit(1)
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 56, height: max(12, safeLength(finite(value) / max(finite(maxVal), 0.01) * 120, max: 130)))
            Text(label).font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
        }
    }
}

// MARK: - 10  Heat Loss Estimate

struct HeatLossView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let u = ThermalEngine.uValue(of: el)
        let dT = ThermalEngine.deltaT(of: el)
        let loss = ThermalEngine.heatLoss(uValue: u, area: el.area, deltaT: dT)
        let annual = ThermalEngine.annualEnergyKWh(uValue: u, area: el.area, deltaT: dT,
                                                   heatingHours: appState.heatingHours)
        let annualCost = annual * appState.energyPrice
        // Arrow count is a visual only; it must never be derived straight from a
        // user-entered number — `Int(loss/40)` traps once the area gets large.
        let arrows = safeCount(loss / 40, cap: 8)

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(spacing: 10) {
                            Text("HEAT LOSS").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                            Text(f.powerText(loss)).font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundColor(Theme.primary)
                                .minimumScaleFactor(0.5).lineLimit(1)
                            Text("U \(f.uText(u)) × \(f.areaText(el.area)) × \(f.deltaTText(dT))")
                                .font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
                                .multilineTextAlignment(.center)
                            if dT <= 0 {
                                Text("Outside is not colder than inside, so there is no heating loss to report.")
                                    .font(.bl(11, .medium)).foregroundColor(Theme.warn)
                                    .multilineTextAlignment(.center)
                            }
                            Divider().background(Theme.cardBorder)
                            HStack {
                                Image(systemName: Icon.bolt).foregroundColor(Theme.secondary)
                                Text("≈ \(f.energyText(annual)) / season")
                                    .font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                                Spacer()
                                Text(appState.money(annualCost))
                                    .font(.bl(14, .heavy)).foregroundColor(Theme.secondary)
                            }
                            Text("\(safeInt(appState.heatingHours)) heating hours at \(appState.money(appState.energyPrice))/kWh — both editable in Settings.")
                                .font(.bl(10, .medium)).foregroundColor(Theme.cardInactive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 18)

                    // Heat-flow visual
                    BLCard(tint: Theme.cardBlue) {
                        HStack(spacing: 4) {
                            Image(systemName: Icon.cold).foregroundColor(Theme.cold)
                            ForEach(0..<arrows, id: \.self) { _ in
                                Image(systemName: "arrow.left").foregroundColor(Theme.primaryHi)
                            }
                            Spacer()
                            Image(systemName: Icon.heat).font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.primary)
                        }.font(.system(size: 15, weight: .bold))
                    }.padding(.horizontal, 18)

                    BLCard {
                        VStack(spacing: 12) {
                            BLNumberField(label: "Area", value: UnitBinding.area(areaBinding, f),
                                          suffix: f.areaSuffix, format: "%.1f", range: InputRange.area)
                            HStack(spacing: 12) {
                                BLNumberField(label: "Inside", value: UnitBinding.temp(insideBinding, f),
                                              suffix: f.tempSuffix, format: "%.0f", range: InputRange.tempC)
                                BLNumberField(label: "Outside", value: UnitBinding.temp(outsideBinding, f),
                                              suffix: f.tempSuffix, format: "%.0f", range: InputRange.tempC)
                            }
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Calc Loss", icon: Icon.bolt) {
                            store.refreshStatus(for: elementID); appState.haptic(.medium)
                            toast.flash("\(f.powerText(loss)) loss", icon: Icon.bolt)
                        }
                        NavigationLink(destination: CostPaybackView(elementID: elementID)) {
                            HStack { Image(systemName: Icon.money); Text("Open Cost & Payback").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.buttonText).frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Heat Loss Estimate", displayMode: .inline)
    }

    private var areaBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.area ?? 0 },
                set: { v in store.mutate(elementID) { $0.area = v; $0.dateModified = Date() } })
    }
    private var insideBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.insideTemp ?? 20 },
                set: { v in store.mutate(elementID) { $0.insideTemp = v; $0.dateModified = Date() } })
    }
    private var outsideBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.outsideTemp ?? -5 },
                set: { v in store.mutate(elementID) { $0.outsideTemp = v; $0.dateModified = Date() } })
    }
}
