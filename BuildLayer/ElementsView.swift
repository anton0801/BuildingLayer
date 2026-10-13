//
//  ElementsView.swift
//  BuildLayer
//
//  Tab 1 — Elements. List + screens 01 Element Capture, 02 Photo Markup,
//  15 Defect & Damp, 16 Element Detail, 17 Approval Signoff.
//

import SwiftUI

// MARK: - Elements tab (list)

enum ElementSort: String, CaseIterable, Identifiable {
    case recent   = "Newest"
    case name     = "Name"
    case worstU   = "Worst U"
    case status   = "Status"
    var id: String { rawValue }
}

struct ElementsView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toast: ToastCenter

    @State private var query = ""
    @State private var typeFilter: String = "All"
    @State private var sort: ElementSort = .recent

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        TowerRushProjectBanner()
                            .padding(.horizontal, 18)
                        summary
                        TowerRushToolStrip()
                            .padding(.horizontal, 18)
                        NavigationLink(destination: ElementCaptureView(existingID: nil)) {
                            HStack(spacing: 10) {
                                Image(systemName: Icon.add).font(.system(size: 18, weight: .bold))
                                Text("New Element").font(.bl(16, .bold))
                            }
                            .foregroundColor(Theme.buttonText)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Theme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Theme.warmGlow, radius: 12, y: 5)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.horizontal, 18)

                        if store.elements.isEmpty {
                            EmptyState(icon: Icon.elements, title: "No elements yet",
                                       message: "Create a wall, roof or floor to start building its thermal pie.")
                        } else {
                            // Search + filter + sort: the list was a flat stack
                            // with no way to find anything once it grew.
                            filterBar
                            if visibleElements.isEmpty {
                                EmptyState(icon: Icon.list, title: "No matches",
                                           message: "Nothing matches “\(query)” in \(typeFilter.lowercased()) elements.")
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(visibleElements) { el in
                                        NavigationLink(destination: ElementDetailView(elementID: el.id)) {
                                            ElementCard(element: el)
                                        }
                                        .buttonStyle(PressableStyle(scale: 0.98))
                                    }
                                }
                                .padding(.horizontal, 18)
                            }
                        }
                    }
                    .padding(.top, 8).padding(.bottom, 110)
                }
            }
            .navigationBarTitle("Elements", displayMode: .inline)
            .navigationBarItems(trailing: HStack(spacing: 16) {
                NavigationLink(destination: BuildingSummaryView()) {
                    Image(systemName: Icon.chart).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.primary)
                }
                SettingsLink()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: Filtering

    private var visibleElements: [ThermalElement] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var list = store.elements

        if typeFilter != "All" {
            list = list.filter { $0.type.rawValue == typeFilter }
        }
        if !trimmed.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.insulationName.localizedCaseInsensitiveContains(trimmed)
                || $0.notes.localizedCaseInsensitiveContains(trimmed)
                || $0.layers.contains { $0.materialName.localizedCaseInsensitiveContains(trimmed) }
            }
        }
        switch sort {
        case .recent: list.sort { $0.dateCreated > $1.dateCreated }
        case .name:   list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .worstU: list.sort { ThermalEngine.uValue(of: $0) > ThermalEngine.uValue(of: $1) }
        case .status: list.sort { statusRank($0.status) < statusRank($1.status) }
        }
        return list
    }

    private func statusRank(_ s: ElementStatus) -> Int {
        switch s {
        case .fail: return 0
        case .attention: return 1
        case .inProgress: return 2
        case .pass: return 3
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.titleDim)
                TextField("Search name, material or note", text: $query)
                    .font(.bl(14, .medium))
                    .foregroundColor(Theme.title)
                    .disableAutocorrection(true)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: Icon.close).foregroundColor(Theme.titleDim)
                    }
                }
            }
            .padding(.vertical, 11).padding(.horizontal, 14)
            .background(Theme.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 1))

            ChipSelector(options: ["All"] + ElementType.allCases.map { $0.rawValue },
                         selection: $typeFilter, label: { $0 }, onCard: false)
            ChipSelector(options: ElementSort.allCases, selection: $sort,
                         label: { "Sort: " + $0.rawValue }, onCard: false)
        }
        .padding(.horizontal, 18)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatPill(value: "\(store.elements.count)", caption: "Elements", color: Theme.layer, icon: Icon.elements)
            StatPill(value: "\(store.passCount)", caption: "Pass code", color: Theme.pass, icon: Icon.check)
            StatPill(value: "\(store.condensationRiskCount)", caption: "Cond. risk", color: Theme.cold, icon: Icon.drop)
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - Element card

struct ElementCard: View {
    @EnvironmentObject var appState: AppState
    let element: ThermalElement

    var body: some View {
        let f = appState.fmt
        let r = ThermalEngine.result(for: element)
        return BLCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: element.type.icon).font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.primary)
                    Text(element.name.isEmpty ? "Untitled element" : element.name)
                        .font(.bl(17, .bold)).foregroundColor(Theme.cardText).lineLimit(1)
                    Spacer()
                    TowerRushAsset(asset: TowerAsset.accent(for: element.type), size: 31, opacity: 0.92)
                    StatusBadge(status: element.status, isManual: element.manualStatus != nil)
                }
                if !element.layers.isEmpty {
                    WallCrossSection(layers: element.layers, height: 70,
                                     atRisk: ThermalEngine.condensation(of: element).atRisk)
                }
                HStack {
                    miniMetric("U", element.layers.isEmpty ? "—" : f.uText(r.uValue), Theme.primary)
                    Divider().frame(height: 28).background(Theme.cardBorder)
                    miniMetric("Target", f.uText(element.targetU), Theme.cardSubtext)
                    Divider().frame(height: 28).background(Theme.cardBorder)
                    miniMetric("Area", f.areaText(element.area), Theme.layer)
                    Spacer()
                    Image(systemName: Icon.chevronR).foregroundColor(Theme.cardInactive)
                }
            }
        }
    }
    private func miniMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.bl(10, .bold)).foregroundColor(Theme.cardSubtext).textCase(.uppercase)
            Text(value).font(.bl(15, .heavy)).foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

// MARK: - 01  Element Capture

struct ElementCaptureView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toast: ToastCenter
    @Environment(\.presentationMode) var presentationMode

    let existingID: UUID?
    @State private var draft = ThermalElement.newDefault()
    @State private var savedID: UUID? = nil
    @State private var goToLayers = false
    @State private var showTemplates = false
    @State private var didLoad = false

    var body: some View {
        let f = appState.fmt
        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if !draft.layers.isEmpty {
                        WallCrossSection(layers: draft.layers, height: 110,
                                         atRisk: ThermalEngine.condensation(of: draft).atRisk)
                            .padding(.horizontal, 18)
                    }
                    BLCard {
                        VStack(spacing: 14) {
                            Text("Enter the element area and target U.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            BLField(label: "Project / Element", placeholder: "e.g. South Wall", text: $draft.name)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("ELEMENT TYPE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                ChipSelector(options: ElementType.allCases, selection: $draft.type,
                                             label: { $0.rawValue }, icon: { $0.icon })
                            }
                            HStack(spacing: 12) {
                                BLNumberField(label: "Area", value: UnitBinding.area($draft.area, f),
                                              suffix: f.areaSuffix, format: "%.1f", range: InputRange.area)
                                BLNumberField(label: "Target U", value: UnitBinding.uValue($draft.targetU, f),
                                              suffix: f.uSuffix, format: f.isMetric ? "%.2f" : "%.3f",
                                              range: InputRange.uValue)
                            }
                            BLNumberField(label: "Tolerance ±", value: UnitBinding.uValue($draft.tolerance, f),
                                          suffix: f.uSuffix, format: f.isMetric ? "%.2f" : "%.3f",
                                          range: InputRange.tolerance)
                            // Standard presets — typing a target from memory was
                            // the only way to set one before.
                            VStack(alignment: .leading, spacing: 7) {
                                Text("APPLY A STANDARD").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(StandardBasis.allCases) { basis in
                                            standardChip(basis, f)
                                        }
                                    }.padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)

                    // Live preview
                    BLCard(tint: Theme.cardBlue) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("PROJECTED U").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                                Text(draft.layers.isEmpty ? "Add layers →" : f.uText(ThermalEngine.uValue(of: draft)))
                                    .font(.bl(24, .heavy)).foregroundColor(Theme.primary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("STATUS").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                                StatusBadge(status: liveStatus)
                            }
                        }
                    }
                    .padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        GhostButton(title: "Start from a template", icon: Icon.stack, tint: Theme.secondary) {
                            showTemplates = true
                        }
                        PrimaryButton(title: "Lock Element", icon: Icon.check) { lock() }
                        HStack(spacing: 10) {
                            SecondaryButton(title: "Keep Element", icon: Icon.doc) { keep() }
                            GhostButton(title: "Clear Fields", icon: Icon.clear, tint: Theme.fail) { clear() }
                        }
                        // Open Layer Stack
                        NavigationLink(destination: layerDest, isActive: $goToLayers) { EmptyView() }
                        GhostButton(title: "Open Layer Stack", icon: Icon.layers) {
                            guard validate() else { return }
                            persist(); goToLayers = true
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle(existingID == nil ? "Element Capture" : "Edit Element", displayMode: .inline)
        .sheet(isPresented: $showTemplates) {
            TemplatePickerSheet(type: draft.type) { template in
                draft.layers = TemplateLibrary.instantiate(template)
                draft.insulationName = draft.layers.first(where: { $0.isInsulation })?.materialName ?? ""
                appState.haptic(.medium)
                toast.flash("Applied \(template.name)", icon: Icon.stack)
            }
            .environmentObject(appState)
            .environmentObject(store)
            .environment(\.unitFormatter, f)
        }
        .onAppear(perform: loadIfNeeded)
    }

    @ViewBuilder private var layerDest: some View {
        if let id = savedID { LayerStackEditor(elementID: id) } else { EmptyView() }
    }

    /// Highlighted only when the target really equals this standard, so a
    /// hand-typed target is never shown as if it came from a preset.
    private func standardChip(_ basis: StandardBasis, _ f: UnitFormatter) -> some View {
        let target = basis.targetU(for: draft.type)
        let active = abs(target - draft.targetU) < 0.0005
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                draft.targetU = target
            }
            appState.haptic()
        } label: {
            HStack(spacing: 6) {
                if active { Image(systemName: Icon.check).font(.system(size: 11, weight: .bold)) }
                Text("\(basis.rawValue) · \(f.uText(target))").font(.bl(13, .bold))
            }
            .foregroundColor(active ? Theme.buttonText : Theme.cardSubtext)
            .padding(.vertical, 9).padding(.horizontal, 14)
            .background(active ? Theme.primary : Theme.cardBlue)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(active ? Color.clear : Theme.cardBorder.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private var liveStatus: ElementStatus {
        if draft.layers.isEmpty { return .inProgress }
        if ThermalEngine.condensation(of: draft).atRisk { return .attention }
        return ThermalEngine.result(for: draft).passesTarget ? .pass : .fail
    }

    private func loadIfNeeded() {
        // Guarded: onAppear fires again when returning from a pushed screen, and
        // reloading there threw away edits made since.
        guard !didLoad else { return }
        didLoad = true
        if let id = existingID, let e = store.element(id) {
            draft = e; savedID = id
        } else {
            var d = ThermalElement.newDefault(type: ElementType(rawValue: appState.defaultElementType) ?? .wall)
            d.targetU = appState.defaultTargetU
            draft = d
        }
    }

    /// Blocks the obviously-unusable values instead of storing them and failing
    /// with a divide-by-zero somewhere three screens later.
    private func validate() -> Bool {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            toast.flash("Name the element first", icon: Icon.warning); return false
        }
        if draft.area <= 0 {
            toast.flash("Area must be above zero", icon: Icon.warning); return false
        }
        if draft.targetU <= 0 {
            toast.flash("Set a target U above zero", icon: Icon.warning); return false
        }
        return true
    }

    @discardableResult
    private func persist() -> UUID {
        draft.dateModified = Date()
        if let id = savedID {
            draft.id = id
            store.update(draft)
            store.refreshStatus(for: id)
            return id
        } else {
            let new = draft
            store.add(new)
            savedID = new.id
            store.refreshStatus(for: new.id)
            return new.id
        }
    }

    private func lock() {
        guard validate() else { return }
        let id = persist()
        store.refreshStatus(for: id)
        appState.haptic(.medium)
        toast.flash("Element locked", icon: Icon.check)
        presentationMode.wrappedValue.dismiss()
    }
    private func keep() {
        guard validate() else { return }
        persist(); appState.haptic()
        toast.flash("Element saved", icon: Icon.doc)
    }
    /// Resets the draft to a blank element. It used to leave `savedID` set, so
    /// the next save renamed the stored element to an empty string.
    private func clear() {
        appState.haptic()
        var blank = ThermalElement.newDefault(type: draft.type)
        blank.name = ""
        blank.area = 0
        blank.targetU = appState.defaultTargetU
        if let id = savedID { blank.id = id; blank.layers = draft.layers }
        draft = blank
        toast.flash("Fields cleared", icon: Icon.clear)
    }
}

// MARK: - Template picker

struct TemplatePickerSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ElementStore
    @Environment(\.presentationMode) var presentationMode
    let type: ElementType
    let onPick: (BuildUpTemplate) -> Void

    @State private var shownType: ElementType = .wall

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        Text("A template drops a complete, correctly ordered build-up in one tap. Tune the thicknesses afterwards.")
                            .font(.bl(13, .medium)).foregroundColor(Theme.subtitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ChipSelector(options: ElementType.allCases, selection: $shownType,
                                     label: { $0.rawValue }, icon: { $0.icon }, onCard: false)
                        ForEach(store.templates(for: shownType)) { template in
                            Button {
                                onPick(template)
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                templateCard(template)
                            }.buttonStyle(PressableStyle(scale: 0.98))
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                }
            }
            .navigationBarTitle("Build-up Templates", displayMode: .inline)
            .navigationBarItems(trailing: Button("Close") { presentationMode.wrappedValue.dismiss() }
                                    .foregroundColor(Theme.primary).font(.bl(15, .bold)))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { shownType = type }
    }

    private func templateCard(_ t: BuildUpTemplate) -> some View {
        BLCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t.name).font(.bl(16, .bold)).foregroundColor(Theme.cardText)
                    Spacer()
                    Text("U \(appState.fmt.uText(t.previewU()))")
                        .font(.bl(13, .heavy)).foregroundColor(Theme.primary)
                }
                Text(t.detail).font(.bl(12, .medium)).foregroundColor(Theme.cardSubtext)
                WallCrossSection(layers: t.layers, showHeatArrow: false, height: 56)
                Text("\(t.layers.count) layers").font(.bl(11, .semibold)).foregroundColor(Theme.cardInactive)
            }
        }
    }
}

// MARK: - 16  Element Detail

struct ElementDetailView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    let elementID: UUID

    @State private var showDeleteConfirm = false

    var body: some View {
        // The element can vanish under this screen (deleted here, or from the
        // building map). Rendering a placeholder — as this did — left the user
        // editing a ghost, so leave instead.
        Group {
            if let el = store.element(elementID) {
                content(for: el)
            } else {
                ZStack {
                    ScreenBackground()
                    EmptyState(icon: Icon.trash, title: "Element removed",
                               message: "This element no longer exists.")
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationBarTitle("Element Detail", displayMode: .inline)
    }

    private func content(for el: ThermalElement) -> some View {
        let f = appState.fmt
        let r = ThermalEngine.result(for: el)
        let cond = ThermalEngine.condensation(of: el)

        return ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Passport card
                    BLCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: el.type.icon).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.primary)
                                Text(el.name.isEmpty ? "Untitled element" : el.name)
                                    .font(.bl(20, .heavy)).foregroundColor(Theme.cardText)
                                Spacer()
                                StatusBadge(status: el.status, isManual: el.manualStatus != nil)
                            }
                            if let data = el.photoData, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(height: 150).frame(maxWidth: .infinity).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            if el.layers.isEmpty {
                                Text("No layers yet — open the Layer Stack to build the pie.")
                                    .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                            } else {
                                WallCrossSection(layers: el.layers, height: 110, atRisk: cond.atRisk)
                            }
                        }
                    }
                    .padding(.horizontal, 18)

                    // Metrics
                    HStack(spacing: 10) {
                        StatPill(value: el.layers.isEmpty ? "—" : f.uText(r.uValue), caption: "U-Value",
                                 color: r.passesTarget ? Theme.pass : Theme.fail, icon: Icon.uValue)
                        StatPill(value: f.rText(r.totalR), caption: "Total R", color: Theme.primary, icon: Icon.layers)
                        StatPill(value: cond.atRisk ? "Risk" : "OK", caption: "Condensation",
                                 color: cond.atRisk ? Theme.cold : Theme.pass, icon: Icon.drop)
                    }
                    .padding(.horizontal, 18)

                    BLCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionRow(label: "Target U", value: "\(f.uText(el.targetU)) \(f.uSuffix)")
                            SectionRow(label: "Area", value: f.areaText(el.area))
                            SectionRow(label: "Insulation", value: el.insulationName.isEmpty ? "—" : el.insulationName)
                            SectionRow(label: "Inside / Outside",
                                       value: "\(f.tempText(el.insideTemp)) / \(f.tempText(el.outsideTemp))")
                            SectionRow(label: "Dominant layer", value: r.dominantLayer)
                            if el.hasCostData {
                                SectionRow(label: "Estimated cost", value: appState.money(el.costTotal))
                            }
                            SectionRow(label: "Updated", value: relativeTimeText(el.dateModified))
                        }
                    }
                    .padding(.horizontal, 18)

                    if let manual = el.manualStatus {
                        signoffCard(el, manual)
                    }

                    if !el.notes.isEmpty { notesCard(el) }

                    // Quick links
                    VStack(spacing: 10) {
                        navTile("Open Layer Stack", Icon.layers, LayerStackEditor(elementID: elementID))
                        navTile("Open R & U Calc", Icon.uValue, RUCalcView(elementID: elementID))
                        navTile("Open Markup", Icon.camera, ElementPhotoMarkupView(elementID: elementID))
                        navTile("Defect & Damp Note", Icon.warning, DefectDampNoteView(elementID: elementID))
                        navTile("Approval Signoff", Icon.sign, ApprovalSignoffView(elementID: elementID))
                    }
                    .padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        NavigationLink(destination: ElementCaptureView(existingID: elementID)) {
                            HStack { Image(systemName: Icon.edit); Text("Update Element").font(.bl(15, .bold)) }
                                .foregroundColor(Theme.buttonText).frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Theme.secondary).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }.buttonStyle(PressableStyle())
                        HStack(spacing: 10) {
                            GhostButton(title: "Duplicate", icon: Icon.duplicate) {
                                store.duplicate(el); appState.haptic(); toast.flash("Element duplicated", icon: Icon.duplicate)
                            }
                            GhostButton(title: "Delete", icon: Icon.trash, tint: Theme.fail) {
                                showDeleteConfirm = true
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        // Deleting used to happen on a single tap with no confirmation and no
        // way back; it now confirms first and the toast offers an undo.
        .alert(isPresented: $showDeleteConfirm) {
            Alert(title: Text("Delete “\(el.name)”?"),
                  message: Text("Its layers, notes and photo go with it. You can undo straight after."),
                  primaryButton: .destructive(Text("Delete")) { performDelete(el) },
                  secondaryButton: .cancel())
        }
    }

    private func performDelete(_ el: ThermalElement) {
        store.delete(el)
        appState.haptic(.medium)
        toast.flash("“\(el.name)” deleted", icon: Icon.trash, actionTitle: "Undo") {
            store.undoDelete()
        }
        presentationMode.wrappedValue.dismiss()
    }

    private func signoffCard(_ el: ThermalElement, _ manual: ElementStatus) -> some View {
        BLCard(tint: Theme.cardBlue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: Icon.shield).foregroundColor(manual.color)
                    Text("SIGNED OFF · \(manual.rawValue.uppercased())")
                        .font(.bl(11, .heavy)).foregroundColor(Theme.cardSubtext)
                    Spacer()
                }
                Text(el.signoffBy.isEmpty ? "Reviewer not named" : el.signoffBy)
                    .font(.bl(15, .bold)).foregroundColor(Theme.cardText)
                if let date = el.signoffDate {
                    Text(DateFormatter.blDateTime.string(from: date))
                        .font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                }
                if !el.signatureStrokes.isEmpty {
                    SignatureImage(strokes: el.signatureStrokes)
                        .frame(height: 64)
                }
                Text("This decision overrides the calculated status until it is cleared.")
                    .font(.bl(11, .medium)).foregroundColor(Theme.cardInactive)
                GhostButton(title: "Clear signoff", icon: Icon.clear, tint: Theme.fail) {
                    store.mutate(elementID) { $0.clearSignoff() }
                    store.refreshStatus(for: elementID)
                    appState.haptic()
                    toast.flash("Signoff cleared", icon: Icon.clear)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func notesCard(_ el: ThermalElement) -> some View {
        BLCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NOTES").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                    Spacer()
                    Button {
                        store.mutate(elementID) { $0.notes = "" }
                        appState.haptic(); toast.flash("Notes cleared", icon: Icon.clear)
                    } label: {
                        Text("Clear").font(.bl(12, .bold)).foregroundColor(Theme.fail)
                    }
                }
                // Notes accumulate one line per action; showing them as rows
                // beats a single wall of text with no structure.
                ForEach(Array(el.notes.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(Theme.primary).frame(width: 5, height: 5).padding(.top, 6)
                        Text(String(line)).font(.bl(12, .medium)).foregroundColor(Theme.cardSubtext)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func navTile<D: View>(_ title: String, _ icon: String, _ dest: D) -> some View {
        NavigationLink(destination: dest) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.primary)
                    .frame(width: 38, height: 38).background(Theme.primary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.bl(15, .bold)).foregroundColor(Theme.title)
                Spacer()
                Image(systemName: Icon.chevronR).foregroundColor(Theme.titleDim)
            }
            .padding(14)
            .background(Theme.bgSoft).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.divider, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

struct SectionRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
            Spacer()
            Text(value).font(.bl(14, .bold)).foregroundColor(Theme.cardText).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 02  Element Photo Markup

struct ElementPhotoMarkupView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    let elementID: UUID

    @State private var image: UIImage? = nil
    @State private var showPicker = false
    @State private var pickCamera = false
    @State private var markArea = "Lower cill"
    @State private var severity = 2.0
    @State private var caption = ""

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(spacing: 14) {
                            Text("Photo the buildup and mark layers.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            photoArea
                            BLField(label: "Mark Area", placeholder: "e.g. cold bridge at lintel", text: $markArea)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("SEVERITY").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                    Spacer()
                                    Text("\(Int(severity))/5").font(.bl(14, .heavy)).foregroundColor(severityColor)
                                }
                                Slider(value: $severity, in: 1...5, step: 1).accentColor(severityColor)
                            }
                            BLField(label: "Caption", placeholder: "Notes about this mark", text: $caption)
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Pin Markup", icon: Icon.pin) { pin(andClose: true) }
                        HStack(spacing: 10) {
                            SecondaryButton(title: "Keep Markup", icon: Icon.doc) { pin(andClose: false) }
                            GhostButton(title: "Clear Fields", icon: Icon.clear, tint: Theme.fail) {
                                image = nil; caption = ""; markArea = ""; severity = 2
                                appState.haptic(); toast.flash("Cleared", icon: Icon.clear)
                            }
                        }
                        NavigationLink(destination: LayerStackEditor(elementID: elementID)) {
                            HStack { Image(systemName: Icon.layers); Text("Open Layer Stack").font(.bl(14, .bold)) }
                                .foregroundColor(Theme.layer).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.layer.opacity(0.5), lineWidth: 1.4))
                        }.buttonStyle(PressableStyle())
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Photo Markup", displayMode: .inline)
        .sheet(isPresented: $showPicker) { ImagePicker(image: $image, useCamera: pickCamera) }
        .onAppear { if image == nil, let e = store.element(elementID), let d = e.photoData { image = UIImage(data: d) } }
    }

    private var photoArea: some View {
        VStack(spacing: 10) {
            photoWell
            // The app already ships a camera usage description, but nothing ever
            // opened the camera — the picker hard-coded the photo library.
            HStack(spacing: 10) {
                if ImagePicker.cameraAvailable {
                    GhostButton(title: "Camera", icon: Icon.camera, tint: Theme.primary) {
                        pickCamera = true; showPicker = true
                    }
                }
                GhostButton(title: "Photo Library", icon: Icon.photo, tint: Theme.layer) {
                    pickCamera = false; showPicker = true
                }
            }
        }
    }

    private var photoWell: some View {
        Button { pickCamera = false; showPicker = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardBlue)
                    .frame(height: 180)
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 180).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(severityTag.padding(8), alignment: .bottomTrailing)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: Icon.camera).font(.system(size: 30, weight: .bold)).foregroundColor(Theme.primary)
                        Text("Add Photo").font(.bl(14, .bold)).foregroundColor(Theme.cardSubtext)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    private var severityTag: some View {
        HStack(spacing: 4) {
            Image(systemName: Icon.warning).font(.system(size: 11, weight: .bold))
            Text("\(Int(severity))").font(.bl(12, .bold))
        }
        .foregroundColor(.white).padding(.vertical, 4).padding(.horizontal, 8)
        .background(severityColor).clipShape(Capsule())
    }
    private var severityColor: Color {
        switch Int(severity) { case 1,2: return Theme.pass; case 3: return Theme.warn; default: return Theme.fail }
    }

    /// Adds the markup note. `andClose` distinguishes "Pin" (record and leave)
    /// from "Keep" (record and stay) — the two buttons used to call the same
    /// code path with an ignored parameter, so they did exactly the same thing.
    private func pin(andClose: Bool) {
        guard store.element(elementID) != nil else { return }
        let area = markArea.trimmingCharacters(in: .whitespaces)
        guard !area.isEmpty || image != nil || !caption.isEmpty else {
            toast.flash("Add a photo or a note first", icon: Icon.warning); return
        }
        if let img = image, let data = ImageStore.encode(img) {
            store.mutate(elementID) { $0.photoData = data }
        }
        let detail = caption.trimmingCharacters(in: .whitespaces)
        let note = "Markup [\(area.isEmpty ? "general" : area)] severity \(safeInt(severity))/5"
            + (detail.isEmpty ? "" : ": \(detail)")
        store.appendNote(note, to: elementID)
        store.mutate(elementID) { $0.dateModified = Date() }
        store.log("Markup pinned", "\(store.element(elementID)?.name ?? ""): \(area)", Icon.pin)
        appState.haptic()
        toast.flash("Markup pinned", icon: Icon.pin)
        if andClose { presentationMode.wrappedValue.dismiss() }
    }
}

// MARK: - 15  Defect & Damp Note

struct DefectDampNoteView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    let elementID: UUID

    @State private var image: UIImage? = nil
    @State private var showPicker = false
    @State private var issue = "Cold bridge"
    @State private var severity = 3.0
    @State private var fix = ""

    private let issues = ["Cold bridge", "Damp", "Draught", "Mould", "Settling"]

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(spacing: 14) {
                            Text("Log cold spots, damp and draughts.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { showPicker = true } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14).fill(Theme.cardBlue).frame(height: 150)
                                    if let img = image {
                                        Image(uiImage: img).resizable().scaledToFill().frame(height: 150).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    } else {
                                        VStack(spacing: 6) {
                                            Image(systemName: Icon.photo).font(.system(size: 26, weight: .bold)).foregroundColor(Theme.primary)
                                            Text("Add Photo").font(.bl(13, .bold)).foregroundColor(Theme.cardSubtext)
                                        }
                                    }
                                }
                            }.buttonStyle(PressableStyle(scale: 0.98))
                            VStack(alignment: .leading, spacing: 7) {
                                Text("ISSUE TYPE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                ChipSelector(options: issues, selection: $issue, label: { $0 })
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text("SEVERITY").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext); Spacer()
                                    Text("\(Int(severity))/5").font(.bl(14, .heavy)).foregroundColor(Theme.fail) }
                                Slider(value: $severity, in: 1...5, step: 1).accentColor(Theme.fail)
                            }
                            BLField(label: "Fix Action", placeholder: "e.g. add insulated reveal", text: $fix)
                        }
                    }.padding(.horizontal, 18)
                    VStack(spacing: 10) {
                        PrimaryButton(title: "Pin Issue", icon: Icon.pin) { pin() }
                        GhostButton(title: "Clear Fields", icon: Icon.clear, tint: Theme.fail) {
                            image = nil; fix = ""; severity = 3; appState.haptic(); toast.flash("Cleared", icon: Icon.clear)
                        }
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Defect & Damp", displayMode: .inline)
        .sheet(isPresented: $showPicker) { ImagePicker(image: $image) }
    }

    private func pin() {
        guard let e = store.element(elementID) else { return }
        let action = fix.trimmingCharacters(in: .whitespaces)
        if let img = image, e.photoData == nil, let data = ImageStore.encode(img) {
            store.mutate(elementID) { $0.photoData = data }
        }
        let note = "Defect [\(issue)] severity \(safeInt(severity))/5"
            + (action.isEmpty ? "" : ": \(action)")
        store.appendNote(note, to: elementID)
        // A serious defect pins the element to Attention. Previously this wrote
        // straight to `status`, which the next refreshStatus quietly undid.
        if safeInt(severity) >= 4 {
            store.mutate(elementID) { $0.manualStatus = .attention }
        }
        store.mutate(elementID) { $0.dateModified = Date() }
        store.refreshStatus(for: elementID)
        store.log("Defect logged", "\(e.name): \(issue)", Icon.warning)
        appState.haptic(.medium); toast.flash("Issue pinned", icon: Icon.pin)
    }
}

// MARK: - 17  Approval Signoff

struct ApprovalSignoffView: View {
    @EnvironmentObject var store: ElementStore
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var appState: AppState
    @Environment(\.presentationMode) var presentationMode
    let elementID: UUID

    @State private var reviewer = ""
    @State private var decision = "Approved"
    @State private var comment = ""
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var didLoad = false

    private let decisions = ["Approved", "Conditional", "Rejected"]

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    BLCard {
                        VStack(spacing: 14) {
                            Text("Review the evidence and record a clear decision.")
                                .font(.bl(13, .medium)).foregroundColor(Theme.cardSubtext)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            BLField(label: "Reviewer", placeholder: "Name", text: $reviewer)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("DECISION").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                ChipSelector(options: decisions, selection: $decision, label: { $0 })
                            }
                            BLField(label: "Comment", placeholder: "Notes", text: $comment)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text("SIGNATURE").font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                                    Spacer()
                                    Button { strokes = []; current = [] } label: {
                                        Text("Clear").font(.bl(12, .bold)).foregroundColor(Theme.fail)
                                    }
                                }
                                SignaturePad(strokes: $strokes, current: $current)
                            }
                        }
                    }.padding(.horizontal, 18)

                    BLCard(tint: Theme.cardBlue) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: Icon.info).foregroundColor(Theme.layer)
                            Text("A signoff sets the element's status and holds it there — later layer edits will not silently change it. Clear the signoff on the detail screen to hand control back to the calculation.")
                                .font(.bl(12, .medium)).foregroundColor(Theme.cardText)
                        }
                    }.padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Record Signoff", icon: Icon.shield) { signoff(close: true) }
                        GhostButton(title: "Keep Signoff", icon: Icon.doc) { signoff(close: false) }
                    }.padding(.horizontal, 18)
                }
                .padding(.top, 10).padding(.bottom, 120)
            }
        }
        .navigationBarTitle("Approval Signoff", displayMode: .inline)
        .onAppear(perform: loadExisting)
    }

    /// Re-opening the screen shows the signoff already on record instead of a
    /// blank form that overwrites it.
    private func loadExisting() {
        guard !didLoad, let e = store.element(elementID) else { return }
        didLoad = true
        reviewer = e.signoffBy
        strokes = e.signatureStrokes.map { $0.map { $0.point } }
        switch e.manualStatus {
        case .pass?: decision = "Approved"
        case .fail?: decision = "Rejected"
        case .attention?: decision = "Conditional"
        default: break
        }
    }

    private func signoff(close: Bool) {
        guard let e = store.element(elementID) else { return }
        let name = reviewer.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            toast.flash("Enter the reviewer's name", icon: Icon.warning); return
        }
        let status: ElementStatus
        switch decision {
        case "Approved": status = .pass
        case "Rejected": status = .fail
        default:         status = .attention
        }
        let remark = comment.trimmingCharacters(in: .whitespaces)
        // The signature pad drew strokes and then discarded them; they are now
        // stored with the element and reproduced in the PDF report.
        let saved = strokes.filter { !$0.isEmpty }.map { $0.map(CGPointCodable.init) }

        store.mutate(elementID) {
            $0.manualStatus = status
            $0.status = status
            $0.signoffBy = name
            $0.signoffDate = Date()
            $0.signatureStrokes = saved
            $0.dateModified = Date()
        }
        store.appendNote("Signoff [\(decision)] by \(name)" + (remark.isEmpty ? "" : ": \(remark)"),
                         to: elementID)
        store.log("Element signed off", "\(e.name): \(decision)", Icon.shield)
        appState.haptic(.medium); toast.flash("Signoff recorded", icon: Icon.shield)
        if close { presentationMode.wrappedValue.dismiss() }
    }
}

// MARK: - Signature pad

struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    @Binding var current: [CGPoint]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardBlue)
            Path { p in
                for s in strokes { addStroke(&p, s) }
                addStroke(&p, current)
            }
            .stroke(Theme.cardText, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            if strokes.isEmpty && current.isEmpty {
                Text("Sign here").font(.bl(13, .medium)).foregroundColor(Theme.cardInactive)
            }
        }
        .frame(height: 120)
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
        .gesture(DragGesture(minimumDistance: 0)
            // Thin the samples: a fast scribble produced thousands of points,
            // all of which were then encoded into the stored element.
            .onChanged { v in
                if let last = current.last,
                   abs(last.x - v.location.x) < 1.5, abs(last.y - v.location.y) < 1.5 { return }
                current.append(v.location)
            }
            .onEnded { _ in
                if current.count > 1 { strokes.append(current) }
                current = []
            })
    }
    private func addStroke(_ p: inout Path, _ pts: [CGPoint]) {
        guard let first = pts.first else { return }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
    }
}

/// Read-only rendering of a stored signature, scaled to fit whatever box it is
/// given (the pad captures in its own 120pt-tall coordinate space).
struct SignatureImage: View {
    let strokes: [[CGPointCodable]]

    var body: some View {
        GeometryReader { geo in
            let points = strokes.flatMap { $0 }
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 1
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 1
            let spanX = max(1, maxX - minX)
            let spanY = max(1, maxY - minY)
            let scale = min(Double(geo.size.width) / spanX, Double(geo.size.height) / spanY)

            Path { p in
                for stroke in strokes {
                    guard let first = stroke.first else { continue }
                    p.move(to: CGPoint(x: (first.x - minX) * scale, y: (first.y - minY) * scale))
                    for pt in stroke.dropFirst() {
                        p.addLine(to: CGPoint(x: (pt.x - minX) * scale, y: (pt.y - minY) * scale))
                    }
                }
            }
            .stroke(Theme.cardText, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Image picker (UIKit bridge, iOS 14 safe)

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var useCamera: Bool = false
    @Environment(\.presentationMode) var presentationMode

    static var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        // The old ternary chose .photoLibrary in both branches, so the camera
        // was unreachable despite the usage description shipping in Info.plist.
        picker.sourceType = (useCamera && ImagePicker.cameraAvailable) ? .camera : .photoLibrary
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let edited = info[.editedImage] as? UIImage { parent.image = edited }
            else if let img = info[.originalImage] as? UIImage { parent.image = img }
            parent.presentationMode.wrappedValue.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
