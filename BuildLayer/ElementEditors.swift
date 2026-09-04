//
//  ElementEditors.swift
//  BuildLayer
//
//  · LayerEditorSheet — edit a layer that is already in the stack. Previously a
//    layer could only be added or deleted, so fixing a 100mm typo meant deleting
//    the layer, re-picking the material and re-entering everything.
//  · ReportCSV — spreadsheet export next to the PDF, for anyone who wants to do
//    their own sums.
//

import SwiftUI

// MARK: - Layer editor

struct LayerEditorSheet: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toast: ToastCenter
    @Environment(\.presentationMode) var presentationMode

    let elementID: UUID
    let layerID: UUID

    @State private var draft: Layer? = nil
    @State private var showMaterialPicker = false

    private let sides = ["Outside", "Core", "Inside"]

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    if let layer = draft {
                        content(layer)
                    } else {
                        EmptyState(icon: Icon.warning, title: "Layer not found",
                                   message: "It may have been removed on another screen.")
                    }
                }
            }
            .navigationBarTitle("Edit Layer", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                    .foregroundColor(Theme.subtitle).font(.bl(15, .semibold)),
                trailing: Button("Save") { save() }
                    .foregroundColor(Theme.primary).font(.bl(15, .bold)))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if draft == nil {
                draft = store.element(elementID)?.layers.first(where: { $0.id == layerID })
            }
        }
    }

    private func content(_ layer: Layer) -> some View {
        let f = appState.fmt
        let binding = Binding<Layer>(get: { draft ?? layer }, set: { draft = $0 })

        return VStack(spacing: 16) {
            // Live resistance readout, so the effect of a change is visible
            // before committing it.
            BLCard {
                VStack(spacing: 8) {
                    Text("LAYER RESISTANCE").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                    Text(f.rText(binding.wrappedValue.resistance))
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundColor(binding.wrappedValue.isInsulation ? Theme.insulation : Theme.layer)
                    Text(f.rSuffix).font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                }
            }.padding(.horizontal, 18)

            BLCard {
                VStack(alignment: .leading, spacing: 14) {
                    Button { showMaterialPicker = true } label: {
                        HStack {
                            Image(systemName: Icon.cube).foregroundColor(Theme.primary)
                            Text(binding.wrappedValue.materialName)
                                .font(.bl(15, .semibold)).foregroundColor(Theme.cardText).lineLimit(1)
                            Spacer()
                            Text("λ \(f.lambdaText(binding.wrappedValue.lambda))")
                                .font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                            Image(systemName: Icon.chevronD).foregroundColor(Theme.cardInactive)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 13)
                        .background(Theme.cardBlue).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    }

                    BLNumberField(label: "Thickness",
                                  value: UnitBinding.thickness(binding.thicknessMM, f),
                                  suffix: f.thicknessSuffix,
                                  format: f.isMetric ? "%.0f" : "%.2f",
                                  range: InputRange.thicknessMM)

                    BLNumberField(label: "Conductivity λ",
                                  value: UnitBinding.lambda(binding.lambda, f),
                                  suffix: f.lambdaSuffix, format: "%.3f", range: InputRange.lambda)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("SIDE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                        ChipSelector(options: sides, selection: binding.side, label: { $0 })
                    }

                    Toggle(isOn: binding.isInsulation) {
                        Text("Counts as insulation").font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                    }.toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                }
            }.padding(.horizontal, 18)

            VStack(spacing: 10) {
                PrimaryButton(title: "Save Layer", icon: Icon.check) { save() }
                GhostButton(title: "Delete Layer", icon: Icon.trash, tint: Theme.fail) {
                    store.removeLayer(layerID, from: elementID)
                    appState.haptic(.medium)
                    toast.flash("Layer removed", icon: Icon.trash)
                    presentationMode.wrappedValue.dismiss()
                }
            }.padding(.horizontal, 18)
        }
        .padding(.top, 12).padding(.bottom, 40)
        .sheet(isPresented: $showMaterialPicker) {
            MaterialPickerSheet(materials: store.materials) { m in
                draft?.materialName = m.name
                draft?.lambda = m.lambda
                draft?.vaporResistance = m.vaporResistance
                draft?.isInsulation = m.isInsulation
            }
            .environmentObject(appState)
            .environment(\.unitFormatter, appState.fmt)
        }
    }

    private func save() {
        guard var layer = draft else { presentationMode.wrappedValue.dismiss(); return }
        guard layer.thicknessMM > 0 else {
            toast.flash("Thickness must be above zero", icon: Icon.warning); return
        }
        guard layer.lambda > 0 else {
            toast.flash("λ must be above zero", icon: Icon.warning); return
        }
        layer.thicknessMM = layer.thicknessMM.clamped(InputRange.thicknessMM)
        layer.lambda = layer.lambda.clamped(InputRange.lambda)
        store.updateLayer(layer, in: elementID)
        store.mutate(elementID) { $0.dateModified = Date() }
        appState.haptic()
        toast.flash("Layer updated", icon: Icon.check)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - CSV export

enum ReportCSV {
    /// One row per element plus one per layer, so the file opens usefully in a
    /// spreadsheet without any post-processing.
    static func write(elements: [ThermalElement], formatter f: UnitFormatter,
                      heatingHours: Double) -> URL? {
        guard !elements.isEmpty else { return nil }

        func escape(_ value: String) -> String {
            let cleaned = value.replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            return "\"\(cleaned)\""
        }

        var rows: [String] = []
        rows.append([
            "Element", "Type", "Status", "Area (\(f.areaSuffix))",
            "U (\(f.uSuffix))", "Target U", "Total R (\(f.rSuffix))",
            "Heat loss (\(f.powerSuffix))", "Annual kWh", "Condensation",
            "Insulation", "Layer", "Material", "Thickness (\(f.thicknessSuffix))",
            "Lambda", "Layer R", "Insulation layer"
        ].map(escape).joined(separator: ","))

        for el in elements {
            let r = ThermalEngine.result(for: el)
            let dT = ThermalEngine.deltaT(of: el)
            let loss = ThermalEngine.heatLoss(uValue: r.uValue, area: el.area, deltaT: dT)
            let annual = ThermalEngine.annualEnergyKWh(uValue: r.uValue, area: el.area,
                                                       deltaT: dT, heatingHours: heatingHours)
            let cond = ThermalEngine.condensation(of: el)

            let head = [
                el.name, el.type.rawValue, el.status.rawValue,
                String(format: "%.2f", f.area(el.area)),
                el.layers.isEmpty ? "" : f.uText(r.uValue),
                f.uText(el.targetU), f.rText(r.totalR),
                el.layers.isEmpty ? "" : String(format: "%.0f", f.power(loss)),
                el.layers.isEmpty ? "" : String(format: "%.0f", annual),
                el.layers.isEmpty ? "n/a" : (cond.atRisk ? "RISK at \(cond.riskLayer)" : "OK"),
                el.insulationName
            ]

            if el.layers.isEmpty {
                rows.append((head + ["", "", "", "", "", ""]).map(escape).joined(separator: ","))
            } else {
                for (i, layer) in el.layers.enumerated() {
                    // Repeat the element columns only on its first layer row so
                    // the file reads as a grouped table.
                    let prefix = i == 0 ? head : Array(repeating: "", count: head.count)
                    let tail = [
                        "\(i + 1)", layer.materialName,
                        String(format: "%.1f", f.thickness(layer.thicknessMM)),
                        f.lambdaText(layer.lambda),
                        f.rText(layer.resistance),
                        layer.isInsulation ? "yes" : "no"
                    ]
                    rows.append((prefix + tail).map(escape).joined(separator: ","))
                }
            }
        }

        let csv = rows.joined(separator: "\n")
        // A unique filename per export: a fixed one was overwritten while the
        // share sheet still held a reference to the previous file.
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildLayer-\(stamp).csv")
        // A BOM makes Excel open UTF-8 correctly instead of mangling °, ² and µ.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}
