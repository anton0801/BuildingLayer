//
//  InsulationView.swift
//  BuildLayer
//
//  Tab 4 — Insulation. Screen 06 Insulation Thickness + 11 Cost & Payback,
//  12 Material List, 13 Cost Estimate.
//

import SwiftUI

// MARK: - Insulation tab

struct InsulationView: View {
    @EnvironmentObject var store: ElementStore
    @State private var selectedID: UUID?

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                if store.elements.isEmpty {
                    EmptyState(icon: Icon.insulation, title: "No element yet",
                               message: "Create an element and set a target U to solve insulation thickness.")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ElementPicker(selectedID: $selectedID)
                            // .id(id) so the solver's own state (chosen
                            // insulation, λ) resets with the selected element.
                            if let id = resolvedID { InsulationThicknessBody(elementID: id).id(id) }
                        }
                        .padding(.top, 10).padding(.bottom, 110)
                    }
                }
            }
            .navigationBarTitle("Insulation", displayMode: .inline)
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

// MARK: - 06  Insulation Thickness (pushable + body)

struct InsulationThicknessView: View {
    let elementID: UUID
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                InsulationThicknessBody(elementID: elementID).padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Insulation Thickness", displayMode: .inline)
    }
}

struct InsulationThicknessBody: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    @State private var insName: String = ""
    @State private var lambda: Double = 0.035
    @State private var roundUp = true
    @State private var didLoad = false

    private var insulationMaterials: [Material] { store.materials.filter { $0.isInsulation } }

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let baseR = ThermalEngine.resistanceWithoutInsulation(of: el)
        let raw = ThermalEngine.requiredInsulationThicknessMM(element: el,
                                                              existingRWithoutInsulation: baseR,
                                                              lambda: lambda)
        let thickness = (roundUp ? ThermalEngine.roundUpToBoard(raw) : raw).clamped(InputRange.thicknessMM)
        let insR = (thickness / 1000.0) / max(lambda, 0.001)
        let resultU = ThermalEngine.resultingU(element: el, addingInsulationR: insR)
        // A target that needs more than the field allows is a real answer, and
        // silently clamping it to 2 m would have been a lie.
        let exceedsPractical = raw > InputRange.thicknessMM.upperBound

        return VStack(spacing: 16) {
            // Headline
            BLCard {
                VStack(spacing: 12) {
                    Text("NEEDED THICKNESS").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                    Text(raw <= 0 ? "Met" : f.thicknessText(thickness))
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.insulation)
                        .minimumScaleFactor(0.4).lineLimit(1)
                    Text(headlineDetail(raw: raw, resultU: resultU, el: el, f: f,
                                        exceeds: exceedsPractical))
                        .font(.bl(13, .semibold)).foregroundColor(exceedsPractical ? Theme.warn : Theme.cardSubtext)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    // Visual thickness bar
                    GeometryReader { geo in
                        let usable = max(10, Double(geo.size.width) - 60)
                        HStack(spacing: 2) {
                            Rectangle().fill(Theme.layer).frame(width: 30)
                            Rectangle().fill(Theme.insulation)
                                .frame(width: safeLength(min(usable, max(10, thickness / 300 * usable))))
                                .overlay(Rectangle().stroke(Theme.primaryHi, lineWidth: 2))
                            Rectangle().fill(Theme.layer.opacity(0.7)).frame(width: 26)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: thickness)

                    if el.layers.contains(where: { $0.isInsulation }) {
                        Text("The build-up already has an insulation layer; this figure replaces it rather than adding to it.")
                            .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.horizontal, 18)

            // Insulation type
            BLCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("INSULATION TYPE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                    if insulationMaterials.isEmpty {
                        Text("No insulation materials in the library — add one from the Layers tab.")
                            .font(.bl(12, .medium)).foregroundColor(Theme.cardSubtext)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(insulationMaterials) { m in
                                let active = m.name == insName
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        insName = m.name; lambda = m.lambda
                                    }
                                    appState.haptic()
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(m.name).font(.bl(12, .bold)).lineLimit(1)
                                        Text("λ \(f.lambdaText(m.lambda))").font(.bl(10, .semibold))
                                    }
                                    .foregroundColor(active ? Theme.buttonText : Theme.cardSubtext)
                                    .padding(.vertical, 9).padding(.horizontal, 13)
                                    .background(ZStack { if active { Theme.primaryGradient } else { Theme.cardBlue } })
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(PressableStyle())
                            }
                        }
                    }
                    Toggle(isOn: $roundUp) {
                        Text("Round up to board size").font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                    }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                }
            }.padding(.horizontal, 18)

            VStack(spacing: 10) {
                // Applying the answer used to be manual: read the number, walk
                // back to the layer stack, re-enter it.
                PrimaryButton(title: "Apply to build-up", icon: Icon.layers) {
                    applyToStack(thickness: thickness)
                }
                HStack(spacing: 10) {
                    SecondaryButton(title: "Keep Result", icon: Icon.doc) { keep(thickness: thickness, u: resultU) }
                    GhostButton(title: "Reset", icon: Icon.clear, tint: Theme.fail) {
                        if let first = insulationMaterials.first { insName = first.name; lambda = first.lambda }
                        roundUp = true
                        appState.haptic(); toast.flash("Reset", icon: Icon.clear)
                    }
                }
                NavigationLink(destination: CondensationView(elementID: elementID)) {
                    HStack { Image(systemName: Icon.drop); Text("Open Condensation Check").font(.bl(14, .bold)) }
                        .foregroundColor(Theme.cold).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.cold.opacity(0.5), lineWidth: 1.3))
                }.buttonStyle(PressableStyle())
            }.padding(.horizontal, 18)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let match = insulationMaterials.first(where: { $0.name == el.insulationName }) {
                insName = match.name; lambda = match.lambda
            } else if let first = insulationMaterials.first {
                insName = first.name; lambda = first.lambda
            }
        }
    }

    private func headlineDetail(raw: Double, resultU: Double, el: ThermalElement,
                                f: UnitFormatter, exceeds: Bool) -> String {
        if raw <= 0 { return "Target already met without extra insulation." }
        if exceeds {
            return "Reaching \(f.uText(el.targetU)) with λ \(f.lambdaText(lambda)) needs more than \(f.thicknessText(InputRange.thicknessMM.upperBound)). Use a better insulant or relax the target."
        }
        return "for target U \(f.uText(el.targetU)) → resulting U \(f.uText(resultU))"
    }

    /// Writes the solved thickness into the stack: updates the existing
    /// insulation layer, or adds one when there is none.
    private func applyToStack(thickness: Double) {
        guard thickness > 0 else {
            toast.flash("Target already met", icon: Icon.check); return
        }
        guard let material = insulationMaterials.first(where: { $0.name == insName })
                ?? insulationMaterials.first else {
            toast.flash("Pick an insulation material", icon: Icon.warning); return
        }
        if let existing = store.element(elementID)?.layers.first(where: { $0.isInsulation }) {
            var updated = existing
            updated.materialName = material.name
            updated.lambda = material.lambda
            updated.vaporResistance = material.vaporResistance
            updated.thicknessMM = thickness
            store.updateLayer(updated, in: elementID)
            toast.flash("Insulation layer updated", icon: Icon.check)
        } else {
            let layer = Layer(materialName: material.name, lambda: material.lambda,
                              vaporResistance: material.vaporResistance,
                              thicknessMM: thickness, isInsulation: true, side: "Core")
            store.addLayer(layer, to: elementID)
            toast.flash("Insulation layer added", icon: Icon.add)
        }
        store.mutate(elementID) { $0.dateModified = Date() }
        store.log("Insulation applied", "\(store.element(elementID)?.name ?? ""): \(appState.fmt.thicknessText(thickness))", Icon.insulation)
        appState.haptic(.medium)
    }

    private func keep(thickness: Double, u: Double) {
        guard store.element(elementID) != nil else { return }
        if !insName.isEmpty { store.mutate(elementID) { $0.insulationName = insName } }
        let f = appState.fmt
        store.appendNote("Insulation solve: \(insName) \(f.thicknessText(thickness)) → U \(f.uText(u)) \(f.uSuffix)",
                         to: elementID)
        store.mutate(elementID) { $0.dateModified = Date() }
        store.log("Insulation solved", "\(store.element(elementID)?.name ?? ""): \(f.thicknessText(thickness))", Icon.insulation)
        appState.haptic(); toast.flash("Result saved", icon: Icon.doc)
    }
}

// MARK: - 11  Cost & Payback

struct CostPaybackView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let upgradedU = ThermalEngine.uValue(of: el)
        let usingDefaultExisting = !(el.existingU > 0)
        let existingU = usingDefaultExisting ? 1.6 : el.existingU
        let dT = ThermalEngine.deltaT(of: el)
        let savedW = max(0, existingU - upgradedU) * el.area * max(0, dT)
        let annualKWh = savedW * max(0, appState.heatingHours) / 1000.0
        let annualSaving = annualKWh * appState.energyPrice
        // Cost now lives on the element, so leaving the screen no longer wipes it.
        let spend = el.costInsulation
        let payback = annualSaving > 0 ? spend / annualSaving : 0

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(spacing: 10) {
                            Text("PAYBACK").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                            Text(paybackText(payback: payback, spend: spend, saving: annualSaving))
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundColor(Theme.secondary)
                                .minimumScaleFactor(0.4).lineLimit(1)
                            Text("Saving ≈ \(appState.money(annualSaving)) / yr · \(f.energyText(annualKWh))")
                                .font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
                                .multilineTextAlignment(.center)
                            if el.layers.isEmpty {
                                Text("Add layers first — with no build-up there is no upgraded U to compare against.")
                                    .font(.bl(11, .medium)).foregroundColor(Theme.warn)
                                    .multilineTextAlignment(.center)
                            } else if usingDefaultExisting {
                                Text("Assuming an existing U of 1.6 \(f.uSuffix). Set the real one on the Before/After screen.")
                                    .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding(.horizontal, 18)

                    BLCard {
                        VStack(spacing: 12) {
                            Text("Estimate insulation cost and payback.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            BLNumberField(label: "Insulation Cost (\(appState.currency.symbol))",
                                          value: costBinding, format: "%.0f", range: InputRange.money)
                            BLNumberField(label: "Energy Price (\(appState.currency.symbol)/kWh)",
                                          value: priceBinding, format: "%.2f", range: InputRange.price)
                            HStack {
                                Text("Annual saving").font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
                                Spacer()
                                Text(appState.money(annualSaving)).font(.bl(16, .heavy)).foregroundColor(Theme.pass)
                            }
                            Text("Energy price is shared across the app and lives in Settings.")
                                .font(.bl(10, .medium)).foregroundColor(Theme.cardInactive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Save Payback", icon: Icon.money) {
                            store.appendNote("Payback \(paybackText(payback: payback, spend: spend, saving: annualSaving)) on \(appState.money(spend)) at \(appState.money(annualSaving))/yr",
                                             to: elementID)
                            store.log("Payback saved", "\(el.name)", Icon.money)
                            appState.haptic(.medium)
                            toast.flash("Payback saved", icon: Icon.money)
                        }
                        NavigationLink(destination: MaterialListView(elementID: elementID)) {
                            HStack { Image(systemName: Icon.list); Text("Open Material List").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.layer).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.layer.opacity(0.5), lineWidth: 1.3))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Cost & Payback", displayMode: .inline)
    }

    private func paybackText(payback: Double, spend: Double, saving: Double) -> String {
        if spend <= 0 { return "—" }
        guard saving > 0 else { return "never" }
        return payback > 99 ? "99+ yrs" : String(format: "%.1f yrs", payback)
    }

    private var costBinding: Binding<Double> {
        Binding(get: { store.element(elementID)?.costInsulation ?? 0 },
                set: { v in store.mutate(elementID) { $0.costInsulation = v; $0.dateModified = Date() } })
    }
    private var priceBinding: Binding<Double> {
        Binding(get: { appState.energyPrice }, set: { appState.energyPrice = $0 })
    }
}

// MARK: - 12  Material List

struct MaterialListView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    @State private var waste = 10.0   // % extra

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let insLayer = el.layers.first(where: { $0.isInsulation })
        let areaWithWaste = (el.area * (1 + waste / 100)).clamped(InputRange.area)
        // Every one of these was a bare `Int(ceil(...))` — each of them traps if
        // the area field holds a large number.
        let boards = insLayer != nil ? safeInt(ceil(areaWithWaste / 0.72), min: 0, max: 999_999) : 0
        let fixings = safeInt(ceil(areaWithWaste * 5), min: 0, max: 9_999_999)
        let battenM = safeInt(ceil(el.area * 3.3), min: 0, max: 999_999)

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Full insulation material list.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            listRow(Icon.insulation, "Insulation",
                                    insLayer == nil
                                        ? "Add an insulation layer to size this"
                                        : "\(insLayer!.materialName) \(f.thicknessText(insLayer!.thicknessMM)) — \(f.areaText(areaWithWaste)) (\(boards) boards)",
                                    Theme.insulation)
                            listRow(Icon.drop, "Vapor / membrane",
                                    "\(f.areaText(areaWithWaste)) \(el.hasVaporControl ? "(VCL fitted)" : "(add VCL)")",
                                    Theme.cold)
                            listRow(Icon.cube, "Fixings", "≈ \(fixings) fixings", Theme.layer)
                            listRow(Icon.wrench, "Battens / framing",
                                    "≈ \(battenM) \(f.lengthSuffix) timber", Theme.secondary)
                            Text("Board count assumes 1200 × 600 sheets. Quantities include the waste allowance below.")
                                .font(.bl(10, .medium)).foregroundColor(Theme.cardInactive)
                        }
                    }.padding(.horizontal, 18)

                    BLCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("WASTE ALLOWANCE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext); Spacer()
                                Text("\(safeInt(waste))%").font(.bl(14, .heavy)).foregroundColor(Theme.primary) }
                            Slider(value: $waste, in: 0...25, step: 1).accentColor(Theme.primary)
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Save List", icon: Icon.list) {
                            store.appendNote("Material list: \(boards) boards, \(fixings) fixings, \(battenM) \(f.lengthSuffix) timber at \(safeInt(waste))% waste",
                                             to: elementID)
                            store.log("Material list built", el.name, Icon.list)
                            appState.haptic(.medium); toast.flash("List saved to notes", icon: Icon.check)
                        }
                        NavigationLink(destination: CostEstimateView(elementID: elementID)) {
                            HStack { Image(systemName: Icon.money); Text("Open Cost Estimate").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.buttonText).frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Material List", displayMode: .inline)
    }

    private func listRow(_ icon: String, _ title: String, _ detail: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(color)
                .frame(width: 38, height: 38).background(color.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                Text(detail).font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

// MARK: - 13  Cost Estimate

struct CostEstimateView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    var body: some View {
        let el = store.element(elementID) ?? .newDefault()
        let sym = appState.currency.symbol
        let subtotal = el.costSubtotal
        let reserve = subtotal * el.costReservePct / 100
        let total = el.costTotal
        let perArea = el.area > 0 ? total / el.area : 0

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(spacing: 8) {
                            Text("TOTAL ESTIMATE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                            Text(appState.money(total)).font(.system(size: 42, weight: .heavy, design: .rounded))
                                .foregroundColor(Theme.primary)
                                .minimumScaleFactor(0.4).lineLimit(1)
                            Text("incl. \(safeInt(el.costReservePct))% reserve (\(appState.money(reserve)))")
                                .font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
                            if perArea > 0 {
                                Text("\(appState.money(perArea)) per \(appState.fmt.areaSuffix)")
                                    .font(.bl(12, .semibold)).foregroundColor(Theme.secondary)
                            }
                        }
                    }.padding(.horizontal, 18)

                    BLCard {
                        VStack(spacing: 12) {
                            Text("Add up insulation and finishing.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            BLNumberField(label: "Insulation (\(sym))", value: costBinding(\.costInsulation),
                                          format: "%.0f", range: InputRange.money)
                            BLNumberField(label: "Membranes (\(sym))", value: costBinding(\.costMembrane),
                                          format: "%.0f", range: InputRange.money)
                            BLNumberField(label: "Finish (\(sym))", value: costBinding(\.costFinish),
                                          format: "%.0f", range: InputRange.money)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text("RESERVE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext); Spacer()
                                    Text("\(safeInt(el.costReservePct))%").font(.bl(14, .heavy)).foregroundColor(Theme.primary) }
                                Slider(value: costBinding(\.costReservePct), in: 0...25, step: 1)
                                    .accentColor(Theme.primary)
                            }
                            Text("Costs are stored with the element and feed the project summary.")
                                .font(.bl(10, .medium)).foregroundColor(Theme.cardInactive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Log Cost", icon: Icon.money) {
                            guard total > 0 else {
                                toast.flash("Enter at least one cost", icon: Icon.warning); return
                            }
                            store.appendNote("Cost estimate \(appState.money(total)) incl. \(safeInt(el.costReservePct))% reserve",
                                             to: elementID)
                            store.log("Cost estimate", "\(el.name): \(appState.money(total))", Icon.money)
                            appState.haptic(.medium); toast.flash("Total \(appState.money(total))", icon: Icon.money)
                        }
                        NavigationLink(destination: BuildingMapView()) {
                            HStack { Image(systemName: Icon.map); Text("Open Building Map").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.layer).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.layer.opacity(0.5), lineWidth: 1.3))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Cost Estimate", displayMode: .inline)
    }

    /// One binding factory for all four cost fields — they all read and write the
    /// stored element rather than view-local state that vanished on navigation.
    private func costBinding(_ path: WritableKeyPath<ThermalElement, Double>) -> Binding<Double> {
        Binding(get: { store.element(elementID)?[keyPath: path] ?? 0 },
                set: { v in store.mutate(elementID) { $0[keyPath: path] = v; $0.dateModified = Date() } })
    }
}
