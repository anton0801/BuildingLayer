//
//  Models.swift
//  BuildLayer
//
//  All Codable data structures + domain enums. The thermal "pie" of an element
//  is an ordered list of Layers; each layer references a Material's conductivity.
//

import Foundation
import SwiftUI

// MARK: - Element type

enum ElementType: String, Codable, CaseIterable, Identifiable {
    case wall = "Wall"
    case roof = "Roof"
    case floor = "Floor"

    var id: String { rawValue }
    var icon: String { Icon.element(rawValue) }

    /// Internal surface resistance Rsi (m²K/W) — depends on heat-flow direction.
    var rsi: Double {
        switch self {
        case .wall:  return 0.13   // horizontal flow
        case .roof:  return 0.10   // upward flow
        case .floor: return 0.17   // downward flow
        }
    }
    /// External surface resistance Rse (m²K/W).
    var rse: Double { 0.04 }

    /// Rsi + Rse.
    var surfaceResistance: Double { rsi + rse }
}

// MARK: - Status

enum ElementStatus: String, Codable, CaseIterable, Identifiable {
    case pass        = "Pass"
    case inProgress  = "In Progress"
    case attention   = "Attention"
    case fail        = "Fail"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .pass:       return Theme.pass
        case .inProgress: return Theme.progress
        case .attention:  return Theme.warn
        case .fail:       return Theme.fail
        }
    }
    var icon: String {
        switch self {
        case .pass:       return Icon.check
        case .inProgress: return Icon.clock
        case .attention:  return Icon.warning
        case .fail:       return Icon.close
        }
    }
}

// MARK: - Material

struct Material: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var lambda: Double          // thermal conductivity W/(m·K)
    var density: Double         // kg/m³
    var vaporResistance: Double // µ (water-vapour resistance factor)
    var isInsulation: Bool = false
    var isCustom: Bool = false

    init(id: UUID = UUID(), name: String, lambda: Double, density: Double,
         vaporResistance: Double, isInsulation: Bool = false, isCustom: Bool = false) {
        self.id = id; self.name = name; self.lambda = lambda; self.density = density
        self.vaporResistance = vaporResistance
        self.isInsulation = isInsulation; self.isCustom = isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name            = try c.decode(String.self, forKey: .name)
        lambda          = try c.decode(Double.self, forKey: .lambda)
        density         = try c.decodeIfPresent(Double.self, forKey: .density) ?? 0
        vaporResistance = try c.decodeIfPresent(Double.self, forKey: .vaporResistance) ?? 1
        isInsulation    = try c.decodeIfPresent(Bool.self, forKey: .isInsulation) ?? false
        isCustom        = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

// MARK: - Layer (one slice of the build-up)

struct Layer: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var materialName: String
    var lambda: Double
    var vaporResistance: Double
    var thicknessMM: Double     // stored in millimetres for UI friendliness
    var isInsulation: Bool
    var side: String = "Core"   // "Outside" / "Core" / "Inside"

    init(id: UUID = UUID(), materialName: String, lambda: Double, vaporResistance: Double,
         thicknessMM: Double, isInsulation: Bool, side: String = "Core") {
        self.id = id; self.materialName = materialName; self.lambda = lambda
        self.vaporResistance = vaporResistance; self.thicknessMM = thicknessMM
        self.isInsulation = isInsulation; self.side = side
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        materialName    = try c.decode(String.self, forKey: .materialName)
        lambda          = try c.decode(Double.self, forKey: .lambda)
        vaporResistance = try c.decodeIfPresent(Double.self, forKey: .vaporResistance) ?? 1
        thicknessMM     = try c.decode(Double.self, forKey: .thicknessMM)
        isInsulation    = try c.decodeIfPresent(Bool.self, forKey: .isInsulation) ?? false
        side            = try c.decodeIfPresent(String.self, forKey: .side) ?? "Core"
    }

    /// Thermal resistance of this layer in m²K/W.
    /// A negative or non-finite thickness contributes nothing rather than
    /// subtracting resistance from the build-up.
    var resistance: Double {
        guard lambda > 0, lambda.isFinite, thicknessMM.isFinite, thicknessMM > 0 else { return 0 }
        return (thicknessMM / 1000.0) / lambda
    }
}

// MARK: - Thermal element (the project)

struct ThermalElement: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var type: ElementType
    var area: Double            // m²
    var targetU: Double         // W/m²K
    var tolerance: Double       // ± allowance on U
    var insideTemp: Double      // °C
    var outsideTemp: Double     // °C
    var indoorRH: Double        // %
    var layers: [Layer] = []
    var insulationName: String = ""
    var status: ElementStatus = .inProgress
    var notes: String = ""
    var hasVaporControl: Bool = false
    var photoData: Data? = nil
    var existingU: Double = 0   // for before/after comparison
    var dateCreated: Date = Date()

    // --- Fields added after the first release. All optional or defaulted so an
    // --- existing stored element still decodes.

    /// Outdoor relative humidity for the vapour-diffusion check. 85% is the
    /// usual winter design assumption.
    var outdoorRH: Double = 85
    /// Set by an approval signoff. While it is set it wins over the calculated
    /// status, so a human decision is not silently undone by the next edit.
    var manualStatus: ElementStatus? = nil
    /// Who signed it off, when, and their signature strokes — the signature pad
    /// used to draw beautifully and then throw the result away.
    var signoffBy: String = ""
    var signoffDate: Date? = nil
    var signatureStrokes: [[CGPointCodable]] = []
    /// Costs entered on the cost screens, kept with the element instead of in
    /// view state that evaporated the moment you navigated away.
    var costInsulation: Double = 0
    var costMembrane: Double = 0
    var costFinish: Double = 0
    var costReservePct: Double = 10
    var dateModified: Date = Date()

    var costSubtotal: Double { costInsulation + costMembrane + costFinish }
    var costTotal: Double { costSubtotal * (1 + costReservePct / 100) }

    /// True once anything beyond the bare defaults has been entered.
    var hasCostData: Bool { costSubtotal > 0 }

    // MARK: Codable
    //
    // Hand-written so that data written by an earlier version — which has none
    // of the fields added above — still decodes. The synthesized initializer
    // does NOT fall back to a property's default value for a missing key; it
    // throws, and since the store treats a decode failure as "no data", every
    // element the user had would have silently disappeared on upgrade.

    enum CodingKeys: String, CodingKey {
        case id, name, type, area, targetU, tolerance, insideTemp, outsideTemp, indoorRH
        case layers, insulationName, status, notes, hasVaporControl, photoData
        case existingU, dateCreated
        case outdoorRH, manualStatus, signoffBy, signoffDate, signatureStrokes
        case costInsulation, costMembrane, costFinish, costReservePct, dateModified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Original fields — required, they have always been written.
        id             = try c.decode(UUID.self, forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        type           = try c.decode(ElementType.self, forKey: .type)
        area           = try c.decode(Double.self, forKey: .area)
        targetU        = try c.decode(Double.self, forKey: .targetU)
        tolerance      = try c.decode(Double.self, forKey: .tolerance)
        insideTemp     = try c.decode(Double.self, forKey: .insideTemp)
        outsideTemp    = try c.decode(Double.self, forKey: .outsideTemp)
        indoorRH       = try c.decode(Double.self, forKey: .indoorRH)
        layers         = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? []
        insulationName = try c.decodeIfPresent(String.self, forKey: .insulationName) ?? ""
        status         = try c.decodeIfPresent(ElementStatus.self, forKey: .status) ?? .inProgress
        notes          = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        hasVaporControl = try c.decodeIfPresent(Bool.self, forKey: .hasVaporControl) ?? false
        photoData      = try c.decodeIfPresent(Data.self, forKey: .photoData)
        existingU      = try c.decodeIfPresent(Double.self, forKey: .existingU) ?? 0
        dateCreated    = try c.decodeIfPresent(Date.self, forKey: .dateCreated) ?? Date()

        // Fields added later — every one of these must tolerate absence.
        outdoorRH      = try c.decodeIfPresent(Double.self, forKey: .outdoorRH) ?? 85
        manualStatus   = try c.decodeIfPresent(ElementStatus.self, forKey: .manualStatus)
        signoffBy      = try c.decodeIfPresent(String.self, forKey: .signoffBy) ?? ""
        signoffDate    = try c.decodeIfPresent(Date.self, forKey: .signoffDate)
        signatureStrokes = try c.decodeIfPresent([[CGPointCodable]].self, forKey: .signatureStrokes) ?? []
        costInsulation = try c.decodeIfPresent(Double.self, forKey: .costInsulation) ?? 0
        costMembrane   = try c.decodeIfPresent(Double.self, forKey: .costMembrane) ?? 0
        costFinish     = try c.decodeIfPresent(Double.self, forKey: .costFinish) ?? 0
        costReservePct = try c.decodeIfPresent(Double.self, forKey: .costReservePct) ?? 10
        dateModified   = try c.decodeIfPresent(Date.self, forKey: .dateModified) ?? dateCreated
    }

    /// Memberwise init stays available now that a custom decoder is declared.
    init(id: UUID = UUID(), name: String, type: ElementType, area: Double,
         targetU: Double, tolerance: Double, insideTemp: Double, outsideTemp: Double,
         indoorRH: Double, layers: [Layer] = [], insulationName: String = "",
         status: ElementStatus = .inProgress, notes: String = "",
         hasVaporControl: Bool = false, photoData: Data? = nil,
         existingU: Double = 0, dateCreated: Date = Date()) {
        self.id = id; self.name = name; self.type = type; self.area = area
        self.targetU = targetU; self.tolerance = tolerance
        self.insideTemp = insideTemp; self.outsideTemp = outsideTemp; self.indoorRH = indoorRH
        self.layers = layers; self.insulationName = insulationName; self.status = status
        self.notes = notes; self.hasVaporControl = hasVaporControl; self.photoData = photoData
        self.existingU = existingU; self.dateCreated = dateCreated
    }

    /// Clears a signoff so the calculated status takes over again.
    mutating func clearSignoff() {
        manualStatus = nil
        signoffBy = ""
        signoffDate = nil
        signatureStrokes = []
    }

    static func newDefault(type: ElementType = .wall) -> ThermalElement {
        ThermalElement(name: "New \(type.rawValue)",
                       type: type,
                       area: 12,
                       targetU: 0.30,
                       tolerance: 0.02,
                       insideTemp: 20,
                       outsideTemp: -5,
                       indoorRH: 55)
    }
}

// MARK: - Codable point (signature strokes)

/// CGPoint is not Codable, and the signature had to survive a relaunch.
struct CGPointCodable: Codable, Hashable {
    var x: Double
    var y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    init(x: Double, y: Double) { self.x = x; self.y = y }
    var point: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - Reminder

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case vaporCheck   = "Check Vapor Barrier"
    case acclimatize  = "Acclimatize Insulation"
    case verifyCode   = "Verify Regional Code"
    case inspectStack = "Re-inspect Build-up"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .vaporCheck:   return Icon.drop
        case .acclimatize:  return Icon.thermo
        case .verifyCode:   return Icon.shield
        case .inspectStack: return Icon.layers
        }
    }
    var detail: String {
        switch self {
        case .vaporCheck:   return "Confirm the vapor barrier is sealed before closing up."
        case .acclimatize:  return "Let the insulation acclimatize on site before fitting."
        case .verifyCode:   return "Re-check the target U against your regional standard."
        case .inspectStack: return "Re-inspect the build-up for gaps or settling."
        }
    }
}

struct Reminder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ReminderKind
    var date: Date
    var isOn: Bool = true
    var elementName: String = ""
    /// Which element the nudge is about. The name field existed but nothing ever
    /// filled it, so every reminder arrived without saying what it referred to.
    var elementID: UUID? = nil

    init(id: UUID = UUID(), kind: ReminderKind, date: Date, isOn: Bool = true,
         elementName: String = "", elementID: UUID? = nil) {
        self.id = id; self.kind = kind; self.date = date; self.isOn = isOn
        self.elementName = elementName; self.elementID = elementID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind        = try c.decode(ReminderKind.self, forKey: .kind)
        date        = try c.decode(Date.self, forKey: .date)
        isOn        = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? true
        elementName = try c.decodeIfPresent(String.self, forKey: .elementName) ?? ""
        elementID   = try c.decodeIfPresent(UUID.self, forKey: .elementID)
    }
}

// MARK: - History entry

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var icon: String
    var date: Date = Date()
}

// MARK: - Appearance preference

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    var icon: String {
        switch self {
        case .system: return Icon.circleHalf
        case .light:  return Icon.sun
        case .dark:   return Icon.moon
        }
    }
}

// MARK: - Units & currency

enum UnitSystem: String, CaseIterable, Identifiable {
    case metric   = "Metric (m, mm)"
    case imperial = "Imperial (ft, in)"
    var id: String { rawValue }
    var short: String { self == .metric ? "m" : "ft" }
}

enum Currency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }
}
