//
//  LayersView.swift
//  BuildLayer
//
//  Tab 2 — Layers. Screen 03 Layer Stack (build the pie) + 04 Material Library.
//

import SwiftUI

// MARK: - Layers tab

struct LayersView: View {
    @EnvironmentObject var store: ElementStore
    @State private var selectedID: UUID?

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                if store.elements.isEmpty {
                    EmptyState(icon: Icon.layers, title: "No element selected",
                               message: "Create an element in the Elements tab, then build its layer stack here.")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ElementPicker(selectedID: $selectedID)
                            if let id = resolvedID {
                                // Fresh subtree per element, so the add-layer
                                // form does not carry the previous element's
                                // material and thickness across.
                                LayerStackBody(elementID: id).id(id)
                            }
                        }
                        .padding(.top, 10).padding(.bottom, 110)
                    }
                }
            }
            .navigationBarTitle("Layer Stack", displayMode: .inline)
            .navigationBarItems(trailing: HStack(spacing: 16) {
                NavigationLink(destination: MaterialLibraryView()) {
                    Image(systemName: Icon.cube).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.primary)
                }
                SettingsLink()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { if selectedID == nil { selectedID = store.elements.first?.id } }
    }

    private var resolvedID: UUID? {
        if let id = selectedID, store.elements.contains(where: { $0.id == id }) { return id }
        return store.elements.first?.id
    }
}

// MARK: - 03  Layer Stack — pushable editor wrapper

struct LayerStackEditor: View {
    let elementID: UUID
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                LayerStackBody(elementID: elementID)
                    .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Layer Stack", displayMode: .inline)
    }
}

// MARK: - Shared layer-stack body

struct LayerStackBody: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    @State private var showMaterialPicker = false
    @State private var showTemplates = false
    @State private var newMaterial: Material? = nil
    @State private var newThickness: Double = 50
    @State private var newSide = "Core"
    @State private var editingLayerID: UUID? = nil

    private let sides = ["Outside", "Core", "Inside"]

    var body: some View {
        let element = store.element(elementID) ?? .newDefault()
        let f = appState.fmt
        let r = ThermalEngine.result(for: element)
        let cond = ThermalEngine.condensation(of: element)

        return VStack(spacing: 16) {
            // Cross-section + R scale
            BLCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(element.name).font(.bl(16, .bold)).foregroundColor(Theme.cardText).lineLimit(1)
                        Spacer()
                        Text("\(element.layers.count) layer\(element.layers.count == 1 ? "" : "s")")
                            .font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                    }
                    if element.layers.isEmpty {
                        VStack(spacing: 10) {
                            Text("Add layers from outside → inside to build the pie.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            GhostButton(title: "Start from a template", icon: Icon.stack, tint: Theme.secondary) {
                                showTemplates = true
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                    } else {
                        WallCrossSection(layers: element.layers, height: 120, atRisk: cond.atRisk)
                    }
                    HStack {
                        Text("R \(f.rText(r.totalR))").font(.bl(13, .heavy)).foregroundColor(Theme.cardText)
                        RScaleBar(currentR: r.totalR, targetR: 1.0 / max(element.targetU, 0.01))
                            .frame(height: 12)
                        Text("U \(f.uText(r.uValue))").font(.bl(13, .heavy)).foregroundColor(Theme.primary)
                    }
                }
            }.padding(.horizontal, 18)

            // Existing layers
            if !element.layers.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(element.layers.enumerated()), id: \.element.id) { idx, layer in
                        layerRow(element: element, index: idx, layer: layer)
                    }
                    Text("Tap a layer to edit its thickness, material or side.")
                        .font(.bl(11, .medium)).foregroundColor(Theme.titleDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }.padding(.horizontal, 18)
            }

            // Add layer form
            BLCard(tint: Theme.cardBlue) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ADD LAYER").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                    Button { showMaterialPicker = true } label: {
                        HStack {
                            Image(systemName: Icon.cube).foregroundColor(Theme.primary)
                            Text(newMaterial?.name ?? "Choose material…")
                                .font(.bl(15, .semibold)).foregroundColor(newMaterial == nil ? Theme.cardInactive : Theme.cardText)
                                .lineLimit(1)
                            Spacer()
                            if let m = newMaterial {
                                Text("λ \(f.lambdaText(m.lambda))").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                            }
                            Image(systemName: Icon.chevronD).foregroundColor(Theme.cardInactive)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 13)
                        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    }
                    HStack(spacing: 12) {
                        BLNumberField(label: "Thickness",
                                      value: UnitBinding.thickness($newThickness, f),
                                      suffix: f.thicknessSuffix,
                                      format: f.isMetric ? "%.0f" : "%.2f",
                                      range: InputRange.thicknessMM)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SIDE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                            ChipSelector(options: sides, selection: $newSide, label: { $0 })
                        }
                    }
                    PrimaryButton(title: "Add Layer", icon: Icon.add) { addLayer() }
                }
            }.padding(.horizontal, 18)

            // Actions
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SecondaryButton(title: "Templates", icon: Icon.stack) { showTemplates = true }
                    GhostButton(title: "Clear Fields", icon: Icon.clear, tint: Theme.fail) {
                        newMaterial = nil; newThickness = 50; newSide = "Core"
                        appState.haptic(); toast.flash("Cleared", icon: Icon.clear)
                    }
                }
                NavigationLink(destination: RUCalcView(elementID: elementID)) {
                    HStack { Image(systemName: Icon.uValue); Text("Open R & U Calc").font(.bl(15, .bold)) }
                        .foregroundColor(Theme.buttonText).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.primaryGradient).clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Theme.warmGlow, radius: 10, y: 4)
                }.buttonStyle(PressableStyle())
            }.padding(.horizontal, 18)
        }
        .sheet(isPresented: $showMaterialPicker) {
            MaterialPickerSheet(materials: store.materials) { m in
                newMaterial = m
                // The field now follows this change. It used to keep showing the
                // previous thickness while the stored value had already moved,
                // so the layer added was not the one on screen.
                newThickness = m.isInsulation ? 100 : 50
            }
            .environmentObject(appState)
            .environment(\.unitFormatter, appState.fmt)
        }
        .sheet(isPresented: $showTemplates) {
            TemplatePickerSheet(type: store.element(elementID)?.type ?? .wall) { template in
                store.mutate(elementID) {
                    $0.layers = TemplateLibrary.instantiate(template)
                    $0.insulationName = $0.layers.first(where: { $0.isInsulation })?.materialName ?? ""
                    $0.dateModified = Date()
                }
                store.refreshStatus(for: elementID)
                appState.haptic(.medium)
                toast.flash("Applied \(template.name)", icon: Icon.stack)
            }
            .environmentObject(appState)
            .environment(\.unitFormatter, appState.fmt)
        }
        .sheet(item: layerEditorBinding) { target in
            LayerEditorSheet(elementID: elementID, layerID: target.id)
                .environmentObject(store).environmentObject(appState).environmentObject(toast)
                .environment(\.unitFormatter, appState.fmt)
        }
    }

    /// `sheet(item:)` needs an Identifiable; wrapping the id keeps the editor
    /// bound to a specific layer even if the list reorders underneath it.
    private struct EditTarget: Identifiable { let id: UUID }
    private var layerEditorBinding: Binding<EditTarget?> {
        Binding(get: { editingLayerID.map(EditTarget.init) },
                set: { editingLayerID = $0?.id })
    }

    private func layerRow(element: ThermalElement, index: Int, layer: Layer) -> some View {
        let f = appState.fmt
        return BLCard(padding: 12) {
            HStack(spacing: 12) {
                Button { editingLayerID = layer.id } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6).fill(layer.isInsulation ? Theme.insulation : Theme.layer)
                            .frame(width: 8, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(layer.materialName).font(.bl(14, .bold)).foregroundColor(Theme.cardText).lineLimit(1)
                            Text("\(f.thicknessText(layer.thicknessMM)) · \(layer.side) · R \(f.rText(layer.resistance))")
                                .font(.bl(11, .semibold)).foregroundColor(Theme.cardSubtext).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                VStack(spacing: 2) {
                    Button { store.moveLayer(in: elementID, from: index, up: true); appState.haptic() } label: {
                        Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
                            .foregroundColor(index == 0 ? Theme.cardInactive : Theme.layer)
                            .frame(width: 26, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(index == 0)
                    Button { store.moveLayer(in: elementID, from: index, up: false); appState.haptic() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                            .foregroundColor(index == element.layers.count - 1 ? Theme.cardInactive : Theme.layer)
                            .frame(width: 26, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(index == element.layers.count - 1)
                }
                Button {
                    store.duplicateLayer(layer.id, in: elementID)
                    appState.haptic(); toast.flash("Layer duplicated", icon: Icon.duplicate)
                } label: {
                    Image(systemName: Icon.duplicate).font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.layer).frame(width: 30, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
                Button { delete(layer) } label: {
                    Image(systemName: Icon.trash).font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.fail).frame(width: 30, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func addLayer() {
        guard let m = newMaterial else {
            toast.flash("Pick a material first", icon: Icon.warning); return
        }
        // A zero-thickness layer contributes nothing and renders as a sliver —
        // it used to be accepted silently.
        guard newThickness > 0 else {
            toast.flash("Enter a thickness above zero", icon: Icon.warning); return
        }
        let layer = Layer(materialName: m.name, lambda: m.lambda, vaporResistance: m.vaporResistance,
                          thicknessMM: newThickness.clamped(InputRange.thicknessMM),
                          isInsulation: m.isInsulation, side: newSide)
        store.addLayer(layer, to: elementID)
        store.mutate(elementID) { $0.dateModified = Date() }
        store.log("Layer added", "\(store.element(elementID)?.name ?? ""): \(m.name)", Icon.layers)
        appState.haptic(); toast.flash("Layer added", icon: Icon.add)
    }

    private func delete(_ layer: Layer) {
        store.removeLayer(layer.id, from: elementID)
        store.mutate(elementID) { $0.dateModified = Date() }
        appState.haptic(); toast.flash("Layer removed", icon: Icon.trash)
    }
}

// MARK: - Material picker sheet

struct MaterialPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    let materials: [Material]
    let onPick: (Material) -> Void

    @State private var query = ""
    @State private var insulationOnly = false

    private var filtered: [Material] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var list = materials
        if insulationOnly { list = list.filter { $0.isInsulation } }
        if !trimmed.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(trimmed) } }
        // Best insulators first — that is the order people scan for.
        return list.sorted {
            $0.isInsulation == $1.isInsulation ? $0.lambda < $1.lambda
                                               : ($0.isInsulation && !$1.isInsulation)
        }
    }

    var body: some View {
        let f = appState.fmt
        return NavigationView {
            ZStack {
                ScreenBackground()
                VStack(spacing: 0) {
                    // The library is 19 entries and growing; scrolling it blind
                    // was the slowest step in building a stack.
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.titleDim)
                            TextField("Search materials", text: $query)
                                .font(.bl(14, .medium)).foregroundColor(Theme.title)
                                .disableAutocorrection(true)
                            if !query.isEmpty {
                                Button { query = "" } label: {
                                    Image(systemName: Icon.close).foregroundColor(Theme.titleDim)
                                }
                            }
                        }
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .background(Theme.bgSoft).clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.divider, lineWidth: 1))

                        Toggle(isOn: $insulationOnly) {
                            Text("Insulation only").font(.bl(13, .semibold)).foregroundColor(Theme.subtitle)
                        }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                    }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if filtered.isEmpty {
                                EmptyState(icon: Icon.cube, title: "No materials",
                                           message: "Nothing matches that search. Add a custom material in the library.")
                            }
                            ForEach(filtered) { m in
                                Button {
                                    onPick(m); presentationMode.wrappedValue.dismiss()
                                } label: {
                                    BLCard(padding: 13) {
                                        HStack {
                                            Image(systemName: m.isInsulation ? Icon.insulation : Icon.cube)
                                                .foregroundColor(m.isInsulation ? Theme.insulation : Theme.layer)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(m.name).font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                                                Text("λ \(f.lambdaText(m.lambda)) · µ \(fmt0(m.vaporResistance))")
                                                    .font(.bl(11, .semibold)).foregroundColor(Theme.cardSubtext)
                                            }
                                            Spacer()
                                            if m.isInsulation {
                                                Text("INSUL").font(.bl(9, .bold)).foregroundColor(.white)
                                                    .padding(.vertical, 3).padding(.horizontal, 7)
                                                    .background(Theme.insulation).clipShape(Capsule())
                                            }
                                        }
                                    }
                                }.buttonStyle(PressableStyle(scale: 0.98))
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                }
            }
            .navigationBarTitle("Choose Material", displayMode: .inline)
            .navigationBarItems(trailing: Button("Close") { presentationMode.wrappedValue.dismiss() }
                                    .foregroundColor(Theme.primary).font(.bl(15, .bold)))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - 04  Material Library

struct MaterialLibraryView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState

    @State private var name = ""
    @State private var lambda = 0.040
    @State private var density = 30.0
    @State private var vapor = 1.0
    @State private var isInsulation = true

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard(tint: Theme.cardBlue) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Pick materials with their conductivity.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            BLField(label: "Material", placeholder: "Custom material name", text: $name)
                            HStack(spacing: 12) {
                                BLNumberField(label: "Lambda λ",
                                              value: UnitBinding.lambda($lambda, appState.fmt),
                                              suffix: appState.fmt.lambdaSuffix, format: "%.3f",
                                              range: InputRange.lambda)
                                BLNumberField(label: "Density", value: $density, suffix: "kg/m³",
                                              format: "%.0f", range: InputRange.density)
                            }
                            BLNumberField(label: "Vapor Resist µ", value: $vapor, format: "%.0f",
                                          range: InputRange.vapor)
                            Toggle(isOn: $isInsulation) {
                                Text("Is insulation").font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                            }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                            PrimaryButton(title: "Add Material", icon: Icon.add) { add() }
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 8) {
                        ForEach(store.materials) { m in
                            BLCard(padding: 13) {
                                HStack {
                                    Image(systemName: m.isInsulation ? Icon.insulation : Icon.cube)
                                        .foregroundColor(m.isInsulation ? Theme.insulation : Theme.layer)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.name).font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                                        Text("λ \(appState.fmt.lambdaText(m.lambda)) · \(fmt0(m.density)) kg/m³ · µ \(fmt0(m.vaporResistance))")
                                            .font(.bl(11, .semibold)).foregroundColor(Theme.cardSubtext)
                                    }
                                    Spacer()
                                    if m.isCustom {
                                        Button { store.deleteMaterial(m); appState.haptic() } label: {
                                            Image(systemName: Icon.trash).foregroundColor(Theme.fail)
                                        }
                                    }
                                }
                            }
                        }
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Material Library", displayMode: .inline)
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { toast.flash("Name the material", icon: Icon.warning); return }
        guard lambda > 0 else { toast.flash("λ must be above zero", icon: Icon.warning); return }
        let ok = store.addMaterial(Material(name: trimmed,
                                            lambda: lambda.clamped(InputRange.lambda),
                                            density: density.clamped(InputRange.density),
                                            vaporResistance: vapor.clamped(InputRange.vapor),
                                            isInsulation: isInsulation, isCustom: true))
        guard ok else {
            toast.flash("A built-in material already uses that name", icon: Icon.warning); return
        }
        name = ""; appState.haptic(); toast.flash("Material saved", icon: Icon.check)
    }
}
