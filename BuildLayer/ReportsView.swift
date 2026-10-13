//
//  ReportsView.swift
//  BuildLayer
//
//  Tab 5 — Reports. Analytics + screen 14 Building Element Map +
//  18 Reminders & Reports (real notifications + PDF export) + history.
//

import SwiftUI
import UIKit

// MARK: - Reports tab

struct ReportsView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        analytics
                        if !store.elements.isEmpty {
                            statusCard
                            targetCard
                            activityCard
                        }
                        VStack(spacing: 10) {
                            navTile("Project Summary", "Totals, worst offenders, energy & cost", Icon.chart, Theme.secondary, BuildingSummaryView())
                            navTile("Compare Elements", "Two build-ups side by side", Icon.pie, Theme.pass, ElementComparisonView())
                            navTile("Building Element Map", "Map U-values across the building", Icon.map, Theme.layer, BuildingMapView())
                            navTile("Reminders & Reports", "Nudges + export PDF or CSV", Icon.bell, Theme.primary, RemindersReportsView())
                        }.padding(.horizontal, 18)
                        history
                    }
                    .padding(.top, 10).padding(.bottom, 110)
                }
            }
            .navigationBarTitle("Reports", displayMode: .inline)
            .navigationBarItems(trailing: SettingsLink())
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var analytics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                StatPill(value: store.areaWeightedU > 0 ? appState.fmt.uText(store.areaWeightedU) : "—",
                         caption: "Weighted U", color: Theme.primary, icon: Icon.uValue)
                StatPill(value: "\(store.passCount)/\(store.elements.count)", caption: "Pass code", color: Theme.pass, icon: Icon.check)
                StatPill(value: "\(store.condensationRiskCount)", caption: "Cond. risk", color: Theme.cold, icon: Icon.drop)
            }
            if let cold = store.coldestElement {
                BLCard(tint: Theme.cardBlue) {
                    HStack(spacing: 12) {
                        Image(systemName: Icon.cold).font(.system(size: 22, weight: .bold)).foregroundColor(Theme.cold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("COLDEST ELEMENT").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                            Text("\(cold.name) · U \(appState.fmt.uText(ThermalEngine.uValue(of: cold)))")
                                .font(.bl(15, .bold)).foregroundColor(Theme.cardText)
                        }
                        Spacer()
                    }
                }
            }
        }.padding(.horizontal, 18)
    }

    // MARK: Charts
    //
    // Three questions the tab could not previously answer at a glance: where the
    // project stands, which elements miss and by how much, and what has been
    // happening. Each card states its question above the chart.

    private var statusCard: some View {
        BLCard {
            VStack(alignment: .leading, spacing: 14) {
                ChartHeader(title: "Project status",
                            subtitle: "Every element by the verdict currently on record.")
                StatusRingChart(slices: store.statusSlices, total: store.elements.count)
            }
        }
        .padding(.horizontal, 18)
    }

    private var targetCard: some View {
        let rows = store.uTargetRows()
        return Group {
            if rows.isEmpty {
                BLCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ChartHeader(title: "U-value against target",
                                    subtitle: "Add layers to an element and it appears here.")
                        Text("Nothing to plot yet — an element needs a build-up before it has a U-value.")
                            .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 18)
            } else {
                BLCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ChartHeader(title: "U-value against target",
                                    subtitle: "Worst first. Each bar is measured against that element's own target, so the line at 1× is the mark they all have to clear.")
                        UTargetChart(rows: rows, formatter: appState.fmt)
                        if store.elements.filter({ !$0.layers.isEmpty }).count > rows.count {
                            Text("Showing the \(rows.count) furthest from target.")
                                .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var activityCard: some View {
        BLCard {
            VStack(alignment: .leading, spacing: 12) {
                ChartHeader(title: "Activity",
                            subtitle: "Recorded actions per day over the last fortnight.")
                ActivityChart(days: store.activityByDay())
            }
        }
        .padding(.horizontal, 18)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Recent Activity", icon: Icon.clock)
                if !store.history.isEmpty {
                    Button {
                        store.history = []
                    } label: {
                        Text("Clear").font(.bl(12, .bold)).foregroundColor(Theme.fail)
                    }
                }
            }.padding(.horizontal, 18)
            if store.history.isEmpty {
                Text("Actions you take will appear here.").font(.bl(13, .medium))
                    .foregroundColor(Theme.subtitle).padding(.horizontal, 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.history.prefix(15)) { h in
                        BLCard(padding: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: h.icon).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.primary)
                                    .frame(width: 34, height: 34).background(Theme.primary.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.title).font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                                    Text(h.detail).font(.bl(11, .semibold)).foregroundColor(Theme.cardSubtext).lineLimit(1)
                                }
                                Spacer()
                                Text(relativeTimeText(h.date)).font(.bl(11, .semibold))
                                    .foregroundColor(Theme.cardInactive).lineLimit(1)
                            }
                        }
                    }
                }.padding(.horizontal, 18)
            }
        }
    }

    private func navTile<D: View>(_ title: String, _ subtitle: String, _ icon: String, _ color: Color, _ dest: D) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundColor(color)
                    .frame(width: 44, height: 44).background(color.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.bl(16, .bold)).foregroundColor(Theme.title)
                    Text(subtitle).font(.bl(12, .medium)).foregroundColor(Theme.subtitle)
                }
                Spacer()
                Image(systemName: Icon.chevronR).foregroundColor(Theme.titleDim)
            }
            .padding(14).background(Theme.bgSoft).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1))
        }.buttonStyle(PressableStyle(scale: 0.98))
    }
}

// MARK: - 14  Building Element Map

struct BuildingMapView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var appState: AppState
    let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let coldID = store.coldestElement?.id
        let maxU = max(0.01, store.elements.filter { !$0.layers.isEmpty }
                        .map { ThermalEngine.uValue(of: $0) }.max() ?? 1)

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if store.elements.isEmpty {
                        EmptyState(icon: Icon.map, title: "No elements", message: "Add elements to map their U-values.")
                    } else {
                        BLCard(tint: Theme.cardBlue) {
                            HStack {
                                Image(systemName: Icon.house).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.primary)
                                Text("Map U-values across the building.").font(.bl(13, .semibold)).foregroundColor(Theme.cardText)
                                Spacer()
                            }
                        }.padding(.horizontal, 18)

                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(store.elements) { el in
                                NavigationLink(destination: ElementDetailView(elementID: el.id)) {
                                    mapTile(el, isWeak: el.id == coldID, maxU: maxU)
                                }.buttonStyle(PressableStyle(scale: 0.97))
                            }
                        }.padding(.horizontal, 18)
                    }
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Building Map", displayMode: .inline)
    }

    private func mapTile(_ el: ThermalElement, isWeak: Bool, maxU: Double) -> some View {
        let u = ThermalEngine.uValue(of: el)
        let frac = el.layers.isEmpty ? 0 : min(1, finite(u) / max(finite(maxU), 0.001))
        return BLCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: el.type.icon).foregroundColor(Theme.primary)
                    Spacer()
                    if isWeak { Image(systemName: Icon.cold).foregroundColor(Theme.cold) }
                }
                Text(el.name).font(.bl(14, .bold)).foregroundColor(Theme.cardText).lineLimit(1)
                Text(el.layers.isEmpty ? "no layers" : "U \(appState.fmt.uText(u))")
                    .font(.bl(18, .heavy)).foregroundColor(isWeak ? Theme.cold : Theme.cardText)
                GeometryReader { geo in
                    Capsule().fill(isWeak ? Theme.cold : Theme.layer)
                        .frame(width: max(6, safeLength(Double(geo.size.width) * frac)), height: 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Capsule().fill(Theme.cardBlue))
                }.frame(height: 7)
                if isWeak {
                    Text("Weakest — insulate first").font(.bl(10, .bold)).foregroundColor(Theme.cold)
                }
            }
        }
    }
}

// MARK: - 18  Reminders & Reports

struct RemindersReportsView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notifier: NotificationManager

    @State private var kind: ReminderKind = .vaporCheck
    @State private var when = Date().addingTimeInterval(3600)
    @State private var linkedID: UUID? = nil
    @State private var includePie = true
    @State private var includeCond = true
    @State private var includeCost = true
    @State private var shareItem: ShareWrapper? = nil

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Add reminder
                    BLCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Set nudges and export a clean report.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("REMINDER TYPE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                ChipSelector(options: ReminderKind.allCases, selection: $kind, label: { $0.rawValue })
                            }
                            Text(kind.detail).font(.bl(12, .medium)).foregroundColor(Theme.cardInactive)
                            if !store.elements.isEmpty {
                                // Reminders carried an `elementName` field that
                                // nothing ever filled, so every notification
                                // arrived without saying what it was about.
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("ABOUT WHICH ELEMENT").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                    ChipSelector(options: [UUID?.none] + store.elements.map { Optional($0.id) },
                                                 selection: $linkedID,
                                                 label: { id in
                                                     id.flatMap { store.element($0)?.name } ?? "No element"
                                                 })
                                }
                            }
                            DatePicker("When", selection: $when, in: Date()...)
                                .datePickerStyle(CompactDatePickerStyle())
                                .accentColor(Theme.primary)
                                .font(.bl(14, .bold)).foregroundColor(Theme.cardText)
                            if !notifier.authorized {
                                Text("Notifications are not allowed yet — adding a reminder will ask for permission.")
                                    .font(.bl(11, .medium)).foregroundColor(Theme.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            PrimaryButton(title: "Add Reminder", icon: Icon.bell) { addReminder() }
                        }
                    }.padding(.horizontal, 18)

                    // Active reminders
                    if !store.reminders.isEmpty {
                        VStack(spacing: 8) {
                            SectionHeader(title: "Scheduled", icon: Icon.bell)
                            ForEach(store.reminders.sorted(by: { $0.date < $1.date })) { rem in
                                reminderRow(rem)
                            }
                        }.padding(.horizontal, 18)
                    }

                    // Report builder
                    BLCard(tint: Theme.cardBlue) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("INCLUDE SECTIONS").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                            sectionToggle("Layer pie + R/U", $includePie)
                            sectionToggle("Condensation check", $includeCond)
                            sectionToggle("Heat loss & cost", $includeCost)
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Export PDF", icon: Icon.doc) { exportPDF() }
                        SecondaryButton(title: "Export CSV", icon: Icon.share) { exportCSV() }
                        Text("\(store.elements.count) element\(store.elements.count == 1 ? "" : "s") will be included.")
                            .font(.bl(11, .medium)).foregroundColor(Theme.titleDim)
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Reminders & Reports", displayMode: .inline)
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .onAppear { notifier.refreshAuthorization() }
    }

    private func reminderRow(_ rem: Reminder) -> some View {
        let overdue = rem.date < Date()
        // A paused reminder is dimmed, and a passed one is dimmed too — both
        // are inert, and the row should say so before the text does.
        let inert = overdue || !rem.isOn
        let accent = inert ? Theme.cardInactive : Theme.primary

        return BLCard(padding: 13) {
            HStack(spacing: 10) {
                Image(systemName: rem.isOn ? rem.kind.icon : Icon.bellSlash)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(rem.kind.rawValue).font(.bl(14, .bold))
                        .foregroundColor(inert ? Theme.cardInactive : Theme.cardText)
                        .lineLimit(1)
                    Text(statusLine(for: rem, overdue: overdue))
                        .font(.bl(11, .semibold))
                        .foregroundColor(overdue ? Theme.warn : Theme.cardSubtext)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    if !rem.elementName.isEmpty {
                        Text(rem.elementName).font(.bl(11, .semibold))
                            .foregroundColor(inert ? Theme.cardInactive : Theme.layer).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)

                Toggle("", isOn: pauseBinding(for: rem))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Theme.primary))
                    // Re-arming a reminder whose time has passed cannot work —
                    // a calendar trigger in the past never fires.
                    .disabled(overdue)
                    .accessibility(label: Text(rem.isOn ? "Pause reminder" : "Resume reminder"))

                Button {
                    notifier.cancel(rem); store.deleteReminder(rem); appState.haptic()
                    toast.flash("Reminder removed", icon: Icon.trash)
                } label: {
                    Image(systemName: Icon.trash).foregroundColor(Theme.fail)
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func statusLine(for rem: Reminder, overdue: Bool) -> String {
        let when = DateFormatter.blDateTime.string(from: rem.date)
        if overdue { return when + " · passed" }
        if !rem.isOn { return when + " · paused" }
        return when
    }

    /// Flipping the switch has to move the scheduled notification too —
    /// otherwise the row would say "paused" while iOS still fired it.
    private func pauseBinding(for rem: Reminder) -> Binding<Bool> {
        Binding(
            get: { store.reminders.first(where: { $0.id == rem.id })?.isOn ?? rem.isOn },
            set: { on in
                appState.haptic()
                if on {
                    guard rem.date > Date() else {
                        toast.flash("That time has passed — set a new reminder", icon: Icon.warning)
                        return
                    }
                    notifier.schedule(rem) { ok in
                        if ok {
                            store.setReminder(rem.id, isOn: true)
                            toast.flash("Reminder resumed", icon: Icon.bell)
                        } else {
                            toast.flash("Allow notifications to resume this", icon: Icon.warning)
                        }
                    }
                } else {
                    notifier.cancel(rem)
                    store.setReminder(rem.id, isOn: false)
                    toast.flash("Reminder paused", icon: Icon.bellSlash)
                }
            })
    }

    private func sectionToggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Text(title).font(.bl(14, .semibold)).foregroundColor(Theme.cardText) }
            .toggleStyle(SwitchToggleStyle(tint: Theme.primary))
    }

    private func addReminder() {
        guard appState.notificationsEnabled else {
            toast.flash("Enable reminders in Settings", icon: Icon.warning); return
        }
        guard when > Date() else {
            toast.flash("Pick a time in the future", icon: Icon.warning); return
        }
        let linked = linkedID.flatMap { store.element($0) }
        let rem = Reminder(kind: kind, date: when,
                           elementName: linked?.name ?? "",
                           elementID: linked?.id)
        notifier.schedule(rem) { ok in
            if ok {
                store.addReminder(rem)
                toast.flash("Reminder scheduled", icon: Icon.bell)
            } else {
                toast.flash("Allow notifications to schedule", icon: Icon.warning)
            }
        }
        appState.haptic()
    }

    private func exportPDF() {
        guard let url = ReportPDF.write(elements: store.elements, appState: appState,
                                        includePie: includePie, includeCond: includeCond,
                                        includeCost: includeCost) else {
            toast.flash("Nothing to export yet", icon: Icon.warning); return
        }
        shareItem = ShareWrapper(url: url)
        store.log("Report exported", "PDF", Icon.share)
        appState.haptic(.medium)
    }

    private func exportCSV() {
        guard let url = ReportCSV.write(elements: store.elements, formatter: appState.fmt,
                                        heatingHours: appState.heatingHours) else {
            toast.flash("Nothing to export yet", icon: Icon.warning); return
        }
        shareItem = ShareWrapper(url: url)
        store.log("Report exported", "CSV", Icon.share)
        appState.haptic(.medium)
    }
}

// MARK: - PDF report builder (real PDF via UIGraphicsPDFRenderer)

enum ReportPDF {
    private static let pageW: CGFloat = 595, pageH: CGFloat = 842   // A4 @72dpi
    private static let margin: CGFloat = 40
    private static let footerY: CGFloat = pageH - 56

    static func write(elements: [ThermalElement], appState: AppState,
                      includePie: Bool, includeCond: Bool, includeCost: Bool) -> URL? {
        guard !elements.isEmpty else { return nil }
        let f = appState.fmt
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        // A unique name per export — a fixed path was overwritten underneath a
        // share sheet that still held the previous file.
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildLayer-Report-\(stamp).pdf")

        let navy = UIColor(red: 0.06, green: 0.16, blue: 0.29, alpha: 1)
        let orange = UIColor(red: 0.97, green: 0.48, blue: 0.11, alpha: 1)
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                                                     .foregroundColor: navy]
        let h2: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .bold),
                                                  .foregroundColor: orange]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .regular),
                                                    .foregroundColor: UIColor.darkGray]
        let bodyBold: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                                                        .foregroundColor: navy]

        do {
            try renderer.writePDF(to: url) { ctx in
                var y: CGFloat = margin
                var page = 0

                // Every draw goes through this, so nothing can run off the page
                // any more — the layer loop in particular used to write straight
                // through the footer and off the sheet.
                func newPage() {
                    if page > 0 { drawFooter(ctx: ctx, page: page, body: body) }
                    ctx.beginPage()
                    page += 1
                    y = margin
                }
                func ensure(_ needed: CGFloat) {
                    if y + needed > footerY { newPage() }
                }
                func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any],
                          indent: CGFloat = 0, lineHeight: CGFloat = 15) {
                    ensure(lineHeight)
                    let box = CGRect(x: margin + indent, y: y,
                                     width: pageW - margin * 2 - indent, height: lineHeight * 3)
                    // Wrapping box rather than draw(at:) — long names and notes
                    // used to run past the right edge and get clipped away.
                    let rect = (text as NSString).boundingRect(
                        with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                    let height = max(lineHeight, ceil(rect.height))
                    ensure(height)
                    (text as NSString).draw(with: CGRect(x: margin + indent, y: y,
                                                         width: box.width, height: height),
                                            options: [.usesLineFragmentOrigin],
                                            attributes: attrs, context: nil)
                    y += height
                }
                func rule() {
                    ensure(12)
                    let line = UIBezierPath()
                    line.move(to: CGPoint(x: margin, y: y + 4))
                    line.addLine(to: CGPoint(x: pageW - margin, y: y + 4))
                    UIColor(white: 0.85, alpha: 1).setStroke()
                    line.lineWidth = 0.6
                    line.stroke()
                    y += 12
                }

                newPage()
                draw("Build Layer — Thermal Report", title, lineHeight: 30)
                draw("Generated \(DateFormatter.blDate.string(from: Date())) · \(elements.count) elements · \(appState.units.rawValue)",
                     body)
                y += 6

                // Project totals, which the report never carried before.
                let totalArea = elements.reduce(0) { $0 + $1.area }
                let totalLoss = elements.filter { !$0.layers.isEmpty }.reduce(0) {
                    $0 + ThermalEngine.heatLoss(uValue: ThermalEngine.uValue(of: $1),
                                                area: $1.area, deltaT: ThermalEngine.deltaT(of: $1))
                }
                draw("PROJECT TOTALS", h2, lineHeight: 20)
                draw("Total area \(f.areaText(totalArea))   ·   Total heat loss \(f.powerText(totalLoss))", bodyBold)
                rule()

                for el in elements {
                    ensure(70)
                    let r = ThermalEngine.result(for: el)
                    draw("\(el.name)  (\(el.type.rawValue))", h2, lineHeight: 20)
                    draw("Status: \(el.status.rawValue)"
                         + (el.manualStatus != nil ? " (signed off)" : "")
                         + "   Area: \(f.areaText(el.area))", body)

                    if includePie {
                        draw("R total \(f.rText(r.totalR)) \(f.rSuffix)   ·   U \(el.layers.isEmpty ? "—" : f.uText(r.uValue)) \(f.uSuffix)   ·   Target \(f.uText(el.targetU))   ·   \(el.layers.isEmpty ? "NO LAYERS" : (r.passesTarget ? "PASS" : "CHECK"))",
                             bodyBold)
                        for layer in el.layers {
                            draw("•  \(layer.materialName) — \(f.thicknessText(layer.thicknessMM)), R \(f.rText(layer.resistance))\(layer.isInsulation ? "  [insulation]" : "")",
                                 body, indent: 12, lineHeight: 14)
                        }
                    }
                    if includeCond && !el.layers.isEmpty {
                        let c = ThermalEngine.condensation(of: el)
                        draw("Condensation: \(c.atRisk ? "RISK at \(c.riskLayer)" : "OK") — peak humidity in build-up \(safeInt(c.peakRH, min: 0, max: 999))%"
                             + (el.hasVaporControl ? "  ·  VCL fitted" : ""), body)
                    }
                    if includeCost {
                        let dT = ThermalEngine.deltaT(of: el)
                        if !el.layers.isEmpty {
                            let loss = ThermalEngine.heatLoss(uValue: ThermalEngine.uValue(of: el),
                                                              area: el.area, deltaT: dT)
                            let annual = ThermalEngine.annualEnergyKWh(uValue: ThermalEngine.uValue(of: el),
                                                                       area: el.area, deltaT: dT,
                                                                       heatingHours: appState.heatingHours)
                            draw("Heat loss \(f.powerText(loss)) at ΔT \(f.deltaTText(dT))   ·   \(f.energyText(annual))/season   ·   \(appState.money(annual * appState.energyPrice))/yr",
                                 body)
                        }
                        if el.hasCostData {
                            draw("Estimated cost \(appState.money(el.costTotal)) incl. \(safeInt(el.costReservePct))% reserve", body)
                        }
                    }
                    if !el.notes.isEmpty {
                        draw("Notes:", bodyBold, lineHeight: 14)
                        for line in el.notes.split(separator: "\n") {
                            draw("•  \(line)", body, indent: 12, lineHeight: 13)
                        }
                    }
                    // The signature was captured and then thrown away; it now
                    // reaches the document it was collected for.
                    if !el.signatureStrokes.isEmpty {
                        ensure(60)
                        draw("Signed off by \(el.signoffBy.isEmpty ? "—" : el.signoffBy)"
                             + (el.signoffDate.map { " on \(DateFormatter.blDateTime.string(from: $0))" } ?? ""),
                             bodyBold, lineHeight: 14)
                        drawSignature(el.signatureStrokes, at: CGPoint(x: margin + 12, y: y),
                                      size: CGSize(width: 150, height: 44), color: navy)
                        y += 50
                    }
                    rule()
                }

                drawFooter(ctx: ctx, page: page, body: body)
            }
            return url
        } catch { return nil }
    }

    private static func drawFooter(ctx: UIGraphicsPDFRendererContext, page: Int,
                                   body: [NSAttributedString.Key: Any]) {
        let disc = "Estimative only. U-values and exact compliance follow your regional standards / project."
        (disc as NSString).draw(at: CGPoint(x: margin, y: footerY + 8), withAttributes: body)
        ("Page \(page)" as NSString).draw(at: CGPoint(x: pageW - margin - 44, y: footerY + 24),
                                          withAttributes: body)
    }

    /// Renders stored signature strokes, scaled into the given box.
    private static func drawSignature(_ strokes: [[CGPointCodable]], at origin: CGPoint,
                                      size: CGSize, color: UIColor) {
        let points = strokes.flatMap { $0 }
        guard !points.isEmpty else { return }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 1
        let scale = min(Double(size.width) / max(1, maxX - minX),
                        Double(size.height) / max(1, maxY - minY))
        let path = UIBezierPath()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: CGPoint(x: origin.x + CGFloat((first.x - minX) * scale),
                                  y: origin.y + CGFloat((first.y - minY) * scale)))
            for pt in stroke.dropFirst() {
                path.addLine(to: CGPoint(x: origin.x + CGFloat((pt.x - minX) * scale),
                                         y: origin.y + CGFloat((pt.y - minY) * scale)))
            }
        }
        color.setStroke()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.stroke()
    }
}

// MARK: - Share sheet

struct ShareWrapper: Identifiable { let id = UUID(); let url: URL }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
