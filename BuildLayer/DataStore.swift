//
//  DataStore.swift
//  BuildLayer
//
//  MVVM state layer. AppState = app-wide preferences (theme/units/currency).
//  ElementStore = the thermal projects, materials, reminders, history — all
//  persisted locally as JSON in UserDefaults. No account, no network.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Local JSON persistence

/// JSON files in Application Support.
///
/// This used to live in UserDefaults, which is the wrong home for it: elements
/// carry photo blobs, UserDefaults is read into memory whole at launch, and a
/// few photos were enough to bloat every launch. Files also let a corrupt blob
/// be discarded on its own instead of taking the rest of the store with it.
enum LocalStore {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BuildLayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func url(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url(key), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        // Migrate anything written by the old UserDefaults build, once.
        if let legacy = UserDefaults.standard.data(forKey: key) {
            try? legacy.write(to: url(key), options: .atomic)
            UserDefaults.standard.removeObject(forKey: key)
        }
        guard let data = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Coalesces rapid writes. Every keystroke in a bound field used to re-encode
/// and rewrite the entire element list; now a burst of edits costs one write.
final class WriteCoalescer {
    private var pending: [String: DispatchWorkItem] = [:]
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.4) { self.delay = delay }

    func schedule(_ key: String, _ work: @escaping () -> Void) {
        pending[key]?.cancel()
        let item = DispatchWorkItem(block: work)
        pending[key] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Run everything still queued — called when the app leaves the foreground.
    func flush() {
        let items = pending.values
        pending.removeAll()
        for item in items { item.cancel(); item.perform() }
    }
}

// MARK: - App-wide preferences

final class AppState: ObservableObject {
    @AppStorage("appearanceMode") var appearanceRaw: String = AppearanceMode.dark.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("unitSystem") var unitRaw: String = UnitSystem.metric.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("currency") var currencyRaw: String = Currency.usd.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }

    // Onboarding-captured defaults (used to seed the first element).
    @AppStorage("defaultElementType") var defaultElementType: String = ElementType.wall.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("defaultTargetU") var defaultTargetU: Double = 0.30 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("climatePreset") var climatePreset: String = "Cold" {
        willSet { objectWillChange.send() }
    }
    /// Heating hours used for the annual-energy estimate — was a hard-coded
    /// 4380 buried in the engine, which made every cost figure unarguable.
    @AppStorage("heatingHours") var heatingHours: Double = 4380 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("energyPrice") var energyPrice: Double = 0.30 {
        willSet { objectWillChange.send() }
    }

    var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .dark }
    var units: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .metric }
    var currency: Currency { Currency(rawValue: currencyRaw) ?? .usd }

    /// The one place unit conversion happens. Every screen formats through this.
    var fmt: UnitFormatter { UnitFormatter(system: units) }

    /// Money in the selected currency, grouped, never in scientific notation.
    func money(_ value: Double) -> String {
        let v = finite(value).clamped(InputRange.money)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v < 100 ? 2 : 0
        f.groupingSeparator = " "
        let number = f.string(from: NSNumber(value: v)) ?? "0"
        return currency.symbol + number
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard hapticsEnabled else { return }
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }
}

// MARK: - Material library + element store

final class ElementStore: ObservableObject {
    @Published var elements: [ThermalElement] = [] { didSet { persistElements() } }
    @Published var materials: [Material] = []     { didSet { persistMaterials() } }
    @Published var reminders: [Reminder] = []     { didSet { persistReminders() } }
    @Published var history: [HistoryEntry] = []   { didSet { persistHistory() } }

    private let elementsKey = "store.elements"
    private let materialsKey = "store.materials"
    private let remindersKey = "store.reminders"
    private let historyKey = "store.history"
    private var ready = false   // skip the didSet write-back while loading in init
    private let writer = WriteCoalescer()

    /// The last deleted element, so a delete can be undone from the toast.
    @Published private(set) var lastDeleted: (element: ThermalElement, index: Int)? = nil

    init() {
        elements  = LocalStore.load([ThermalElement].self, key: elementsKey) ?? []
        materials = LocalStore.load([Material].self, key: materialsKey) ?? Self.defaultMaterials
        reminders = LocalStore.load([Reminder].self, key: remindersKey) ?? []
        history   = LocalStore.load([HistoryEntry].self, key: historyKey) ?? []
        ready = true
        // Reconcile stored statuses with what the engine now says. The status
        // was only recomputed on certain actions, so a card could show
        // "In Progress" while the summary counted the same element as passing —
        // the badge and the tally openly disagreed on one screen.
        refreshAllStatuses()
    }

    // MARK: Persistence
    private func persistElements()  { guard ready else { return }; writer.schedule(elementsKey)  { [elements]  in LocalStore.save(elements,  key: "store.elements")  } }
    private func persistMaterials() { guard ready else { return }; writer.schedule(materialsKey) { [materials] in LocalStore.save(materials, key: "store.materials") } }
    private func persistReminders() { guard ready else { return }; writer.schedule(remindersKey) { [reminders] in LocalStore.save(reminders, key: "store.reminders") } }
    private func persistHistory()   { guard ready else { return }; writer.schedule(historyKey)   { [history]   in LocalStore.save(history,   key: "store.history")   } }

    /// Write anything still queued. Called when the app backgrounds so a
    /// debounced edit can never be lost to a task kill.
    func flushPendingWrites() { writer.flush() }

    // MARK: Elements CRUD
    func add(_ element: ThermalElement) {
        elements.insert(element, at: 0)
        log("Element created", element.name, Icon.add)
    }
    func update(_ element: ThermalElement) {
        if let i = elements.firstIndex(where: { $0.id == element.id }) {
            elements[i] = element
        }
    }
    func delete(_ element: ThermalElement) {
        guard let index = elements.firstIndex(where: { $0.id == element.id }) else { return }
        lastDeleted = (elements[index], index)
        elements.remove(at: index)
        log("Element deleted", element.name, Icon.trash)
    }
    /// Put back the most recently deleted element, at its old position.
    @discardableResult
    func undoDelete() -> Bool {
        guard let pending = lastDeleted else { return false }
        lastDeleted = nil
        elements.insert(pending.element, at: min(pending.index, elements.count))
        log("Delete undone", pending.element.name, Icon.check)
        return true
    }
    func duplicate(_ element: ThermalElement) {
        var copy = element
        copy.id = UUID()
        copy.name = element.name + " (copy)"
        copy.dateCreated = Date()
        // Fresh ids for the layers too — duplicated ids break ForEach identity
        // and made the two elements' layer rows animate as one.
        copy.layers = copy.layers.map { layer in
            var l = layer; l.id = UUID(); return l
        }
        elements.insert(copy, at: 0)
        log("Element duplicated", copy.name, Icon.duplicate)
    }
    func element(_ id: UUID?) -> ThermalElement? {
        guard let id = id else { return nil }
        return elements.first(where: { $0.id == id })
    }

    /// Mutate an element in place. Every screen used to fetch a copy, edit it and
    /// call `update`, which lost any change made in between.
    func mutate(_ id: UUID, _ change: (inout ThermalElement) -> Void) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        change(&elements[i])
    }

    /// The status the engine computes for an element right now.
    func computedStatus(for element: ThermalElement) -> ElementStatus {
        if element.layers.isEmpty { return .inProgress }
        if ThermalEngine.condensation(of: element).atRisk { return .attention }
        return ThermalEngine.result(for: element).passesTarget ? .pass : .fail
    }

    /// Recompute & store the status for an element.
    ///
    /// A signoff decision is a human judgement, so it wins over the calculation
    /// until it is cleared — previously the next layer edit silently reverted an
    /// approved element back to whatever the numbers said.
    func refreshStatus(for id: UUID) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        if let manual = elements[i].manualStatus {
            elements[i].status = manual
        } else {
            elements[i].status = computedStatus(for: elements[i])
        }
    }

    /// Refresh every element — used after a bulk change (erase, import, target edit).
    func refreshAllStatuses() {
        for i in elements.indices {
            elements[i].status = elements[i].manualStatus ?? computedStatus(for: elements[i])
        }
    }

    // MARK: Layers
    func addLayer(_ layer: Layer, to id: UUID) {
        mutate(id) { e in
            e.layers.append(layer)
            if layer.isInsulation { e.insulationName = layer.materialName }
        }
        refreshStatus(for: id)
    }
    func updateLayer(_ layer: Layer, in id: UUID) {
        mutate(id) { e in
            guard let i = e.layers.firstIndex(where: { $0.id == layer.id }) else { return }
            e.layers[i] = layer
            e.insulationName = e.layers.first(where: { $0.isInsulation })?.materialName ?? ""
        }
        refreshStatus(for: id)
    }
    func removeLayer(_ layerID: UUID, from id: UUID) {
        mutate(id) { e in
            e.layers.removeAll { $0.id == layerID }
            // Keep the headline insulation name honest when its layer goes away.
            e.insulationName = e.layers.first(where: { $0.isInsulation })?.materialName ?? ""
        }
        refreshStatus(for: id)
    }
    func moveLayer(in id: UUID, from index: Int, up: Bool) {
        mutate(id) { e in
            let target = up ? index - 1 : index + 1
            guard e.layers.indices.contains(index), e.layers.indices.contains(target) else { return }
            e.layers.swapAt(index, target)
        }
        refreshStatus(for: id)
    }
    func duplicateLayer(_ layerID: UUID, in id: UUID) {
        mutate(id) { e in
            guard let i = e.layers.firstIndex(where: { $0.id == layerID }) else { return }
            var copy = e.layers[i]
            copy.id = UUID()
            e.layers.insert(copy, at: i + 1)
        }
        refreshStatus(for: id)
    }

    /// Append a dated note rather than letting callers hand-splice strings —
    /// every screen was building the same `notes.isEmpty ? x : notes + "\n" + x`.
    func appendNote(_ text: String, to id: UUID) {
        let stamp = DateFormatter.blShort.string(from: Date())
        mutate(id) { e in
            let line = "[\(stamp)] " + text
            e.notes = e.notes.isEmpty ? line : e.notes + "\n" + line
        }
    }

    // MARK: Materials
    /// Adds a material, replacing any custom one with the same name so the
    /// library cannot fill with near-duplicates.
    @discardableResult
    func addMaterial(_ m: Material) -> Bool {
        let name = m.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, m.lambda > 0 else { return false }
        var material = m
        material.name = name
        if let i = materials.firstIndex(where: {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            guard materials[i].isCustom else { return false }   // never shadow a built-in
            materials[i] = material
            log("Material updated", name, Icon.cube)
        } else {
            materials.append(material)
            log("Material added", name, Icon.cube)
        }
        return true
    }
    func deleteMaterial(_ m: Material) {
        materials.removeAll { $0.id == m.id }
    }

    // MARK: Reminders
    func addReminder(_ r: Reminder) {
        reminders.insert(r, at: 0)
        log("Reminder set", r.kind.rawValue, Icon.bell)
    }
    func deleteReminder(_ r: Reminder) {
        reminders.removeAll { $0.id == r.id }
    }

    // MARK: History
    func log(_ title: String, _ detail: String, _ icon: String) {
        history.insert(HistoryEntry(title: title, detail: detail, icon: icon), at: 0)
        if history.count > 120 { history.removeLast(history.count - 120) }
    }

    // MARK: Analytics helpers
    var coldestElement: ThermalElement? {
        elements.filter { !$0.layers.isEmpty }
            .max(by: { ThermalEngine.uValue(of: $0) < ThermalEngine.uValue(of: $1) })
    }
    /// Only elements that actually have a build-up can pass — an empty element
    /// used to be counted as passing because `1/R` of the bare surface films
    /// happens to clear a loose target.
    var passCount: Int {
        elements.filter { !$0.layers.isEmpty && ThermalEngine.result(for: $0).passesTarget }.count
    }

    // MARK: Whole-building rollups
    var totalArea: Double { elements.reduce(0) { $0 + finite($1.area) } }

    var totalHeatLossW: Double {
        elements.filter { !$0.layers.isEmpty }.reduce(0) {
            $0 + ThermalEngine.heatLoss(uValue: ThermalEngine.uValue(of: $1),
                                        area: $1.area,
                                        deltaT: ThermalEngine.deltaT(of: $1))
        }
    }

    func totalAnnualKWh(heatingHours: Double) -> Double {
        elements.filter { !$0.layers.isEmpty }.reduce(0) {
            $0 + ThermalEngine.annualEnergyKWh(uValue: ThermalEngine.uValue(of: $1),
                                               area: $1.area,
                                               deltaT: ThermalEngine.deltaT(of: $1),
                                               heatingHours: heatingHours)
        }
    }

    /// Area-weighted U — the plain mean treated a 2 m² window reveal as equal to
    /// a 40 m² wall, which is not what a building average means.
    var areaWeightedU: Double {
        let withLayers = elements.filter { !$0.layers.isEmpty && $0.area > 0 }
        let area = withLayers.reduce(0) { $0 + $1.area }
        guard area > 0 else { return 0 }
        let sum = withLayers.reduce(0) { $0 + ThermalEngine.uValue(of: $1) * $1.area }
        return sum / area
    }
    var condensationRiskCount: Int {
        elements.filter { !$0.layers.isEmpty && ThermalEngine.condensation(of: $0).atRisk }.count
    }

    func eraseAll() {
        elements = []
        reminders = []
        history = []
        materials = Self.defaultMaterials
        lastDeleted = nil
        writer.flush()
    }

    // MARK: - Default material library (typical λ values, W/m·K)
    static let defaultMaterials: [Material] = [
        Material(name: "Brickwork (outer)", lambda: 0.77, density: 1700, vaporResistance: 10),
        Material(name: "Concrete block", lambda: 1.13, density: 2000, vaporResistance: 60),
        Material(name: "Aerated block (AAC)", lambda: 0.15, density: 600, vaporResistance: 10),
        Material(name: "Cement render", lambda: 0.87, density: 1800, vaporResistance: 25),
        Material(name: "Gypsum plasterboard", lambda: 0.21, density: 700, vaporResistance: 8),
        Material(name: "Softwood timber", lambda: 0.13, density: 500, vaporResistance: 50),
        Material(name: "OSB / sheathing", lambda: 0.13, density: 650, vaporResistance: 50),
        Material(name: "Plywood", lambda: 0.14, density: 560, vaporResistance: 110),
        Material(name: "Air cavity (25mm)", lambda: 0.16, density: 1, vaporResistance: 1),
        Material(name: "Mineral wool (slab)", lambda: 0.035, density: 30, vaporResistance: 1, isInsulation: true),
        Material(name: "Glass wool (quilt)", lambda: 0.040, density: 16, vaporResistance: 1, isInsulation: true),
        Material(name: "EPS board", lambda: 0.038, density: 18, vaporResistance: 30, isInsulation: true),
        Material(name: "XPS board", lambda: 0.034, density: 35, vaporResistance: 100, isInsulation: true),
        Material(name: "PIR board", lambda: 0.022, density: 30, vaporResistance: 60, isInsulation: true),
        Material(name: "Phenolic board", lambda: 0.020, density: 35, vaporResistance: 50, isInsulation: true),
        Material(name: "Wood fibre board", lambda: 0.040, density: 140, vaporResistance: 5, isInsulation: true),
        Material(name: "Sheep wool", lambda: 0.039, density: 25, vaporResistance: 1, isInsulation: true),
        Material(name: "Screed", lambda: 1.15, density: 2000, vaporResistance: 30),
        Material(name: "Reinforced concrete", lambda: 2.3, density: 2400, vaporResistance: 130)
    ]
}

// MARK: - Standard target presets

enum StandardBasis: String, CaseIterable, Identifiable {
    case comfort     = "Comfort"
    case codeMinimum = "Code Minimum"
    case lowEnergy   = "Low-Energy"
    var id: String { rawValue }

    func targetU(for type: ElementType) -> Double {
        switch (self, type) {
        case (.comfort, .wall):      return 0.30
        case (.comfort, .roof):      return 0.20
        case (.comfort, .floor):     return 0.25
        case (.codeMinimum, .wall):  return 0.26
        case (.codeMinimum, .roof):  return 0.16
        case (.codeMinimum, .floor): return 0.22
        case (.lowEnergy, .wall):    return 0.15
        case (.lowEnergy, .roof):    return 0.11
        case (.lowEnergy, .floor):   return 0.13
        }
    }
}


// MARK: - Shared date formatting

extension DateFormatter {
    /// Cached — building a DateFormatter is expensive and the list rows were
    /// creating a fresh one per row, per redraw.
    static let blShort: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd MMM yyyy, HH:mm"; return f
    }()
    static let blDateTime: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
    static let blDate: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; return f
    }()
}

/// "3 min ago" style text for the activity feed, which previously showed a bare
/// day-and-month stamp under a "Recent activity" heading.
func relativeTimeText(_ date: Date) -> String {
    let seconds = Date().timeIntervalSince(date)
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(safeInt(seconds / 60)) min ago" }
    if seconds < 86_400 { return "\(safeInt(seconds / 3600)) h ago" }
    if seconds < 604_800 { return "\(safeInt(seconds / 86_400)) d ago" }
    return DateFormatter.blShort.string(from: date)
}
