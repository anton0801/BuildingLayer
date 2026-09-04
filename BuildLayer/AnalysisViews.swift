//
//  AnalysisViews.swift
//  BuildLayer
//
//  Whole-project analysis. The app could tell you everything about one element
//  and nothing about the building they add up to, and there was no way to put
//  two build-ups side by side — which is the actual question when choosing one.
//
//  · BuildingSummaryView — totals, worst offenders, project-wide cost & energy
//  · ElementComparisonView — two elements compared line by line
//

import SwiftUI

// MARK: - Whole-building summary

struct BuildingSummaryView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toast: ToastCenter

    @State private var shareItem: ShareWrapper? = nil

    var body: some View {
        let f = appState.fmt
        let hours = appState.heatingHours
        let priced = store.elements.filter { !$0.layers.isEmpty }
        let annualKWh = store.totalAnnualKWh(heatingHours: hours)
        let annualCost = annualKWh * appState.energyPrice
        let totalSpend = store.elements.reduce(0) { $0 + $1.costTotal }

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if store.elements.isEmpty {
                        EmptyState(icon: Icon.chart, title: "Nothing to summarise",
                                   message: "Add elements with layers and the whole-project totals appear here.")
                    } else {
                        headline(annualKWh: annualKWh, annualCost: annualCost)

                        HStack(spacing: 10) {
                            StatPill(value: f.areaText(store.totalArea), caption: "Total area",
                                     color: Theme.layer, icon: Icon.ruler)
                            StatPill(value: store.areaWeightedU > 0 ? f.uText(store.areaWeightedU) : "—",
                                     caption: "Weighted U", color: Theme.primary, icon: Icon.uValue)
                            StatPill(value: "\(store.passCount)/\(store.elements.count)", caption: "Pass",
                                     color: Theme.pass, icon: Icon.check)
                        }
                        .padding(.horizontal, 18)

                        if totalSpend > 0 {
                            BLCard(tint: Theme.cardBlue) {
                                HStack {
                                    Image(systemName: Icon.money).font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Theme.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("BUDGETED WORK").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                                        Text(appState.money(totalSpend))
                                            .font(.bl(20, .heavy)).foregroundColor(Theme.cardText)
                                    }
                                    Spacer()
                                    if annualCost > 0 {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("SIMPLE PAYBACK").font(.bl(10, .bold)).foregroundColor(Theme.cardSubtext)
                                            Text(paybackText(spend: totalSpend, annual: annualCost))
                                                .font(.bl(16, .heavy)).foregroundColor(Theme.primary)
                                        }
                                    }
                                }
                            }.padding(.horizontal, 18)
                        }

                        worstOffenders(priced)
                        breakdownByType(priced)

                        VStack(spacing: 10) {
                            NavigationLink(destination: ElementComparisonView()) {
                                HStack { Image(systemName: Icon.chart); Text("Compare two elements").font(.bl(15, .bold)) }
                                    .foregroundColor(Theme.buttonText).frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(Theme.primaryGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .shadow(color: Theme.warmGlow, radius: 10, y: 4)
                            }.buttonStyle(PressableStyle())

                            SecondaryButton(title: "Export CSV", icon: Icon.share) { exportCSV() }
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Project Summary", displayMode: .inline)
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    private func paybackText(spend: Double, annual: Double) -> String {
        guard annual > 0 else { return "—" }
        let years = spend / annual
        return years > 99 ? "99+ yrs" : String(format: "%.1f yrs", years)
    }

    private func headline(annualKWh: Double, annualCost: Double) -> some View {
        BLCard {
            VStack(spacing: 10) {
                Text("PROJECT HEAT LOSS").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                Text(appState.fmt.powerText(store.totalHeatLossW))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.primary)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("across \(store.elements.count) element\(store.elements.count == 1 ? "" : "s") at their own design temperatures")
                    .font(.bl(12, .medium)).foregroundColor(Theme.cardSubtext)
                    .multilineTextAlignment(.center)
                Divider().background(Theme.cardBorder)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ANNUAL ENERGY").font(.bl(10, .bold)).foregroundColor(Theme.cardSubtext)
                        Text(appState.fmt.energyText(annualKWh))
                            .font(.bl(17, .heavy)).foregroundColor(Theme.cardText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("AT \(appState.money(appState.energyPrice))/kWh").font(.bl(10, .bold)).foregroundColor(Theme.cardSubtext)
                        Text(appState.money(annualCost))
                            .font(.bl(17, .heavy)).foregroundColor(Theme.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    /// Where the heat actually goes — ranked by watts, not by U, because a big
    /// mediocre wall loses far more than a small terrible one.
    private func worstOffenders(_ elements: [ThermalElement]) -> some View {
        let ranked = elements
            .map { (element: $0, loss: ThermalEngine.heatLoss(uValue: ThermalEngine.uValue(of: $0),
                                                              area: $0.area,
                                                              deltaT: ThermalEngine.deltaT(of: $0))) }
            .filter { $0.loss > 0 }
            .sorted { $0.loss > $1.loss }
        let peak = ranked.first?.loss ?? 1

        return Group {
            if !ranked.isEmpty {
                BLCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WHERE THE HEAT GOES").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                        ForEach(ranked.prefix(6), id: \.element.id) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: row.element.type.icon)
                                        .font(.system(size: 11, weight: .bold)).foregroundColor(Theme.cardSubtext)
                                    Text(row.element.name).font(.bl(13, .semibold))
                                        .foregroundColor(Theme.cardText).lineLimit(1)
                                    Spacer()
                                    Text(appState.fmt.powerText(row.loss))
                                        .font(.bl(12, .heavy)).foregroundColor(Theme.primary)
                                }
                                GeometryReader { geo in
                                    Capsule().fill(Theme.heatGradient)
                                        .frame(width: max(6, safeLength(Double(geo.size.width) * (row.loss / max(peak, 0.001)))),
                                               height: 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Capsule().fill(Theme.cardBlue))
                                }.frame(height: 8)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func breakdownByType(_ elements: [ThermalElement]) -> some View {
        BLCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("BY ELEMENT TYPE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                ForEach(ElementType.allCases) { type in
                    let group = elements.filter { $0.type == type }
                    let area = group.reduce(0) { $0 + $1.area }
                    let loss = group.reduce(0) {
                        $0 + ThermalEngine.heatLoss(uValue: ThermalEngine.uValue(of: $1),
                                                    area: $1.area, deltaT: ThermalEngine.deltaT(of: $1))
                    }
                    HStack {
                        Image(systemName: type.icon).font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.primary).frame(width: 22)
                        Text(type.rawValue).font(.bl(13, .semibold)).foregroundColor(Theme.cardText)
                        Spacer()
                        Text(group.isEmpty ? "—" : "\(group.count) · \(appState.fmt.areaText(area))")
                            .font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                        Text(group.isEmpty ? "" : appState.fmt.powerText(loss))
                            .font(.bl(12, .heavy)).foregroundColor(Theme.primary)
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func exportCSV() {
        guard let url = ReportCSV.write(elements: store.elements, formatter: appState.fmt,
                                        heatingHours: appState.heatingHours) else {
            toast.flash("Nothing to export yet", icon: Icon.warning); return
        }
        shareItem = ShareWrapper(url: url)
        store.log("Project exported", "CSV", Icon.share)
        appState.haptic(.medium)
    }
}

// MARK: - Element comparison

struct ElementComparisonView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var appState: AppState

    @State private var leftID: UUID? = nil
    @State private var rightID: UUID? = nil

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if store.elements.count < 2 {
                        EmptyState(icon: Icon.chart, title: "Need two elements",
                                   message: "Create at least two elements to compare their build-ups.")
                    } else {
                        pickerCard("A", $leftID, Theme.layer)
                        pickerCard("B", $rightID, Theme.primary)
                        if let a = store.element(leftID), let b = store.element(rightID) {
                            if a.id == b.id {
                                BLCard(tint: Theme.cardBlue) {
                                    Text("Pick two different elements to see the comparison.")
                                        .font(.bl(13, .medium)).foregroundColor(Theme.cardText)
                                }.padding(.horizontal, 18)
                            } else {
                                comparison(a, b)
                            }
                        }
                    }
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Compare Elements", displayMode: .inline)
        .onAppear {
            if leftID == nil { leftID = store.elements.first?.id }
            if rightID == nil { rightID = store.elements.dropFirst().first?.id ?? store.elements.first?.id }
        }
    }

    private func pickerCard(_ label: String, _ selection: Binding<UUID?>, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(label).font(.bl(12, .heavy)).foregroundColor(Theme.buttonText)
                    .frame(width: 22, height: 22).background(tint).clipShape(Circle())
                Text(store.element(selection.wrappedValue)?.name ?? "Choose an element")
                    .font(.bl(14, .bold)).foregroundColor(Theme.title).lineLimit(1)
                Spacer()
            }
            ElementPicker(selectedID: selection)
        }
        .padding(.vertical, 4)
    }

    private func comparison(_ a: ThermalElement, _ b: ThermalElement) -> some View {
        let f = appState.fmt
        let ra = ThermalEngine.result(for: a)
        let rb = ThermalEngine.result(for: b)
        let lossA = ThermalEngine.heatLoss(uValue: ra.uValue, area: a.area, deltaT: ThermalEngine.deltaT(of: a))
        let lossB = ThermalEngine.heatLoss(uValue: rb.uValue, area: b.area, deltaT: ThermalEngine.deltaT(of: b))
        let condA = ThermalEngine.condensation(of: a)
        let condB = ThermalEngine.condensation(of: b)

        return VStack(spacing: 14) {
            BLCard {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        stackColumn(a, Theme.layer)
                        stackColumn(b, Theme.primary)
                    }
                }
            }.padding(.horizontal, 18)

            BLCard {
                VStack(spacing: 0) {
                    compareRow("U-value", f.uText(ra.uValue), f.uText(rb.uValue),
                               lowerIsBetter: true, a: ra.uValue, b: rb.uValue)
                    compareRow("Total R", f.rText(ra.totalR), f.rText(rb.totalR),
                               lowerIsBetter: false, a: ra.totalR, b: rb.totalR)
                    compareRow("Target U", f.uText(a.targetU), f.uText(b.targetU),
                               lowerIsBetter: nil, a: a.targetU, b: b.targetU)
                    compareRow("Area", f.areaText(a.area), f.areaText(b.area),
                               lowerIsBetter: nil, a: a.area, b: b.area)
                    compareRow("Heat loss", f.powerText(lossA), f.powerText(lossB),
                               lowerIsBetter: true, a: lossA, b: lossB)
                    compareRow("Layers", "\(a.layers.count)", "\(b.layers.count)",
                               lowerIsBetter: nil, a: Double(a.layers.count), b: Double(b.layers.count))
                    compareRow("Condensation", condA.atRisk ? "Risk" : "OK", condB.atRisk ? "Risk" : "OK",
                               lowerIsBetter: true,
                               a: condA.atRisk ? 1 : 0, b: condB.atRisk ? 1 : 0)
                    compareRow("Insulation", a.insulationName.isEmpty ? "—" : a.insulationName,
                               b.insulationName.isEmpty ? "—" : b.insulationName,
                               lowerIsBetter: nil, a: 0, b: 0, showsWinner: false)
                }
            }.padding(.horizontal, 18)

            verdict(a, b, ra, rb)
        }
    }

    private func stackColumn(_ el: ThermalElement, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(el.name).font(.bl(13, .bold)).foregroundColor(Theme.cardText).lineLimit(1)
            if el.layers.isEmpty {
                RoundedRectangle(cornerRadius: 10).fill(Theme.cardBlue).frame(height: 78)
                    .overlay(Text("No layers").font(.bl(11, .semibold)).foregroundColor(Theme.cardInactive))
            } else {
                WallCrossSection(layers: el.layers, showHeatArrow: false, height: 78,
                                 atRisk: ThermalEngine.condensation(of: el).atRisk)
            }
            StatusBadge(status: el.status, isManual: el.manualStatus != nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `lowerIsBetter` nil means the row is informational and gets no winner mark.
    private func compareRow(_ label: String, _ left: String, _ right: String,
                            lowerIsBetter: Bool?, a: Double, b: Double,
                            showsWinner: Bool = true) -> some View {
        let leftWins: Bool? = {
            guard showsWinner, let lower = lowerIsBetter, a != b, a.isFinite, b.isFinite else { return nil }
            return lower ? a < b : a > b
        }()
        return VStack(spacing: 0) {
            HStack {
                Text(left).font(.bl(13, .heavy))
                    .foregroundColor(leftWins == true ? Theme.pass : Theme.cardText)
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                    .textCase(.uppercase).frame(width: 96)
                Text(right).font(.bl(13, .heavy))
                    .foregroundColor(leftWins == false ? Theme.pass : Theme.cardText)
                    .frame(maxWidth: .infinity, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.vertical, 9)
            Divider().background(Theme.cardBorder.opacity(0.5))
        }
    }

    private func verdict(_ a: ThermalElement, _ b: ThermalElement,
                         _ ra: ThermalResult, _ rb: ThermalResult) -> some View {
        let better = ra.uValue < rb.uValue ? a : b
        let gap = ThermalEngine.improvementPercent(existingU: max(ra.uValue, rb.uValue),
                                                   upgradedU: min(ra.uValue, rb.uValue))
        return BLCard(tint: Theme.cardBlue) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Icon.lightbulb).foregroundColor(Theme.secondary)
                Text(a.layers.isEmpty || b.layers.isEmpty
                     ? "Add layers to both elements for a meaningful comparison."
                     : "“\(better.name)” performs \(safeInt(gap))% better on U-value. Heat loss also depends on area — check the heat-loss row before deciding where to spend.")
                    .font(.bl(13, .semibold)).foregroundColor(Theme.cardText)
            }
        }
        .padding(.horizontal, 18)
    }
}
