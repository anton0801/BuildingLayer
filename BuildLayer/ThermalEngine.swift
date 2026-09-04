//
//  ThermalEngine.swift
//  BuildLayer
//
//  The calculation core. Pure functions — no state — so every screen can call in.
//  R (thermal resistance) sums layer by layer, U = 1/R, plus a simplified
//  interface-temperature / dew-point condensation check and heat-loss estimate.
//

import Foundation

struct LayerContribution: Identifiable {
    let id: UUID
    let name: String
    let resistance: Double
    let fraction: Double   // share of total R (0...1)
    let isInsulation: Bool
}

struct InterfaceTemp: Identifiable {
    let id = UUID()
    let label: String
    let temperature: Double
    /// Dew point of the air *at this interface*, from the local vapour pressure.
    let dewPoint: Double
    /// Saturation and actual vapour pressure at this interface (Pa).
    let saturationPressure: Double
    let vaporPressure: Double
    /// The outdoor face sits in outdoor air rather than inside the build-up.
    var countsForRisk: Bool = true

    /// Local relative humidity — the readable version of the pressure pair.
    /// At 100% the air here is saturated and moisture drops out.
    var localRH: Double {
        guard saturationPressure > 0 else { return 0 }
        return min(999, vaporPressure / saturationPressure * 100)
    }
    var atRisk: Bool { countsForRisk && vaporPressure >= saturationPressure }
    /// Close to saturation but not over — worth a warning, not a failure.
    var isTight: Bool { countsForRisk && !atRisk && localRH >= 90 }
}

struct ThermalResult {
    var totalR: Double          // m²K/W incl. surface resistances
    var uValue: Double          // W/m²K
    var contributions: [LayerContribution]
    var passesTarget: Bool
    var dominantLayer: String
}

enum ThermalEngine {

    // MARK: - R & U

    /// Sum of all layer resistances + the element's surface resistances.
    static func totalResistance(of element: ThermalElement) -> Double {
        let layersR = element.layers.reduce(0) { $0 + finite($1.resistance) }
        return max(0, layersR) + element.type.surfaceResistance
    }

    static func uValue(of element: ThermalElement) -> Double {
        let r = totalResistance(of: element)
        guard r > 0 else { return 0 }
        return 1.0 / r
    }

    static func result(for element: ThermalElement) -> ThermalResult {
        let surface = element.type.surfaceResistance
        let total = totalResistance(of: element)
        let u = total > 0 ? 1.0 / total : 0

        var contributions: [LayerContribution] = []
        // Surface films as a pseudo-contribution so the bars add up to 100%.
        if total > 0 {
            contributions.append(LayerContribution(id: UUID(),
                                                    name: "Surface films",
                                                    resistance: surface,
                                                    fraction: surface / total,
                                                    isInsulation: false))
        }
        for layer in element.layers {
            contributions.append(LayerContribution(id: layer.id,
                                                   name: layer.materialName,
                                                   resistance: layer.resistance,
                                                   fraction: total > 0 ? layer.resistance / total : 0,
                                                   isInsulation: layer.isInsulation))
        }

        let dominant = contributions
            .filter { $0.name != "Surface films" }
            .max(by: { $0.resistance < $1.resistance })?.name ?? "—"

        let passes = u > 0 && u <= element.targetU + element.tolerance
        return ThermalResult(totalR: total, uValue: u,
                             contributions: contributions,
                             passesTarget: passes,
                             dominantLayer: dominant)
    }

    // MARK: - Insulation thickness solver

    /// Returns the insulation thickness (mm) needed to reach `targetU`,
    /// given the resistance the build-up already has WITHOUT that insulation.
    static func requiredInsulationThicknessMM(element: ThermalElement,
                                              existingRWithoutInsulation: Double,
                                              lambda: Double) -> Double {
        guard element.targetU > 0, lambda > 0 else { return 0 }
        let neededTotalR = 1.0 / element.targetU
        let neededInsulationR = neededTotalR - existingRWithoutInsulation
        guard neededInsulationR > 0 else { return 0 }
        return neededInsulationR * lambda * 1000.0
    }

    /// Resistance of the build-up excluding any layer marked as insulation.
    static func resistanceWithoutInsulation(of element: ThermalElement) -> Double {
        let r = element.layers.filter { !$0.isInsulation }.reduce(0) { $0 + $1.resistance }
        return r + element.type.surfaceResistance
    }

    static func resultingU(element: ThermalElement, addingInsulationR insR: Double) -> Double {
        let base = resistanceWithoutInsulation(of: element)
        let total = base + insR
        return total > 0 ? 1.0 / total : 0
    }

    /// Round a thickness up to the next common board size (mm).
    static func roundUpToBoard(_ mm: Double) -> Double {
        let boards: [Double] = [20, 25, 30, 40, 50, 60, 75, 80, 90, 100, 120, 140, 160, 180, 200, 220, 240, 260, 280, 300]
        return boards.first(where: { $0 >= mm }) ?? (ceil(mm / 20) * 20)
    }

    // MARK: - Condensation (vapour diffusion)
    //
    // The old check compared every interface temperature with the *indoor* dew
    // point. In any cold climate the outer half of a build-up is always below
    // the indoor dew point, so it reported "risk" on every element — including
    // correctly built ones — which made the whole feature uninformative.
    //
    // This is the standard simplified (Glaser) comparison instead: the vapour
    // pressure falls across the build-up in proportion to each layer's vapour
    // resistance, and condensation is predicted where that actual pressure
    // reaches the saturation pressure for the local temperature. It finally
    // uses the µ values that every material and layer already carried and that
    // nothing in the app read.

    /// Saturation vapour pressure (Pa) over water/ice at a given temperature.
    static func saturationVaporPressure(_ tempC: Double) -> Double {
        let t = finite(tempC).clamped(-60...80)
        return t >= 0 ? 610.5 * exp((17.269 * t) / (237.3 + t))
                      : 610.5 * exp((21.875 * t) / (265.5 + t))
    }

    /// Dew point (°C) for a temperature & relative humidity (Magnus approx.).
    static func dewPoint(tempC: Double, rh: Double) -> Double {
        let a = 17.27, b = 237.7
        let rhc = max(1, min(100, finite(rh, 50))) / 100.0
        let t = finite(tempC).clamped(-60...80)
        let gamma = (a * t) / (b + t) + log(rhc)
        return (b * gamma) / (a - gamma)
    }

    /// Dew point implied by a vapour pressure (Pa) — the inverse of the above.
    static func dewPoint(fromVaporPressure p: Double) -> Double {
        let pressure = max(1, finite(p))
        let ln = log(pressure / 610.5)
        return (237.3 * ln) / (17.269 - ln)
    }

    /// Vapour resistance of a layer as an equivalent air-layer thickness (m).
    static func sdValue(of layer: Layer) -> Double {
        let mu = max(1, finite(layer.vaporResistance, 1))
        let thickness = max(0, finite(layer.thicknessMM)) / 1000.0
        return mu * thickness
    }

    /// sd added by a vapour control layer on the warm side (typical polythene).
    static let vaporControlSd: Double = 50.0

    /// Temperature and vapour pressure at every interface, inside → outside.
    static func interfaceTemperatures(of element: ThermalElement) -> [InterfaceTemp] {
        let totalR = totalResistance(of: element)
        guard totalR > 0, !element.layers.isEmpty else { return [] }

        let tin = element.insideTemp
        let tout = element.outsideTemp
        let drop = tin - tout

        // Vapour pressure at the two boundaries.
        let pIn = saturationVaporPressure(tin) * (finite(element.indoorRH, 55).clamped(1...100) / 100)
        let pOut = saturationVaporPressure(tout) * (finite(element.outdoorRH, 85).clamped(1...100) / 100)

        // Layers are stored outside→inside; walk reversed to travel inwards.
        let inwardOrder = Array(element.layers.reversed())
        // A vapour control layer belongs on the warm side, ahead of everything.
        let sdList = (element.hasVaporControl ? [vaporControlSd] : [])
            + inwardOrder.map(sdValue)
        let totalSd = max(0.0001, sdList.reduce(0, +))

        var result: [InterfaceTemp] = []
        var cumulativeR = element.type.rsi
        var cumulativeSd = element.hasVaporControl ? vaporControlSd : 0

        func entry(_ label: String, counts: Bool = true) -> InterfaceTemp {
            let t = tin - (cumulativeR / totalR) * drop
            let p = pIn - (cumulativeSd / totalSd) * (pIn - pOut)
            return InterfaceTemp(label: label,
                                 temperature: t,
                                 dewPoint: dewPoint(fromVaporPressure: p),
                                 saturationPressure: saturationVaporPressure(t),
                                 vaporPressure: max(0, p),
                                 countsForRisk: counts)
        }

        result.append(entry(element.hasVaporControl ? "Inside surface (behind VCL)" : "Inside surface"))

        for (i, layer) in inwardOrder.enumerated() {
            cumulativeR += layer.resistance
            cumulativeSd += sdValue(of: layer)
            let label = i == inwardOrder.count - 1
                ? "Outside face of \(layer.materialName)"
                : "Behind \(layer.materialName)"
            result.append(entry(label))
        }

        // Outside surface: shown for context, judged against outdoor air, so it
        // is excluded from the verdict.
        cumulativeR = totalR
        cumulativeSd = totalSd
        result.append(entry("Outside surface", counts: false))
        return result
    }

    struct CondensationVerdict {
        var atRisk: Bool
        var riskLayer: String
        /// Smallest headroom in °C between the local temperature and the local
        /// dew point; negative means condensation is predicted.
        var minMargin: Double
        /// Highest local relative humidity found inside the build-up (%).
        var peakRH: Double
        var recommendation: String
    }

    static func condensation(of element: ThermalElement) -> CondensationVerdict {
        let interfaces = interfaceTemperatures(of: element).filter { $0.countsForRisk }
        guard let worst = interfaces.max(by: { $0.localRH < $1.localRH }) else {
            return CondensationVerdict(atRisk: false, riskLayer: "—", minMargin: 0, peakRH: 0,
                                       recommendation: "Add layers to run the check.")
        }
        let margin = worst.temperature - worst.dewPoint
        let risk = worst.atRisk
        let rec: String
        if risk {
            rec = element.hasVaporControl
                ? "Condensation predicted at \(worst.riskLabel). The vapour control layer is not enough — move more insulation outside this point or add a ventilated cavity."
                : "Condensation predicted at \(worst.riskLabel). Add a vapour control layer on the warm side, or shift insulation outward so this interface stays warmer."
        } else if worst.isTight {
            rec = "No condensation, but \(worst.riskLabel) reaches \(String(format: "%.0f", worst.localRH))% humidity. A vapour control layer would give more headroom."
        } else {
            rec = "No interstitial condensation predicted. Peak humidity in the build-up is \(String(format: "%.0f", worst.localRH))%, with \(String(format: "%.1f", margin))°C of headroom."
        }
        return CondensationVerdict(atRisk: risk, riskLayer: worst.label,
                                   minMargin: margin, peakRH: worst.localRH,
                                   recommendation: rec)
    }

    // MARK: - Heat loss

    /// Steady-state conduction loss through the element (W).
    static func heatLoss(uValue: Double, area: Double, deltaT: Double) -> Double {
        finite(uValue) * finite(area) * finite(deltaT)
    }

    static func deltaT(of element: ThermalElement) -> Double {
        element.insideTemp - element.outsideTemp
    }

    // MARK: - Annual energy & savings

    /// Rough annual energy through the element (kWh) over a heating season.
    static func annualEnergyKWh(uValue: Double, area: Double, deltaT: Double, heatingHours: Double = 4380) -> Double {
        // Only heat *lost* counts — a negative ΔT (warmer outside) is not a
        // negative heating bill, and used to make payback figures nonsensical.
        let loss = max(0, heatLoss(uValue: uValue, area: area, deltaT: deltaT))
        return (loss * max(0, finite(heatingHours))) / 1000.0
    }

    static func improvementPercent(existingU: Double, upgradedU: Double) -> Double {
        guard existingU > 0 else { return 0 }
        return max(0, (existingU - upgradedU) / existingU * 100.0)
    }
}


extension InterfaceTemp {
    /// The label without the "Behind "/"Outside face of " prefix, for prose.
    var riskLabel: String {
        label.replacingOccurrences(of: "Behind ", with: "")
             .replacingOccurrences(of: "Outside face of ", with: "the outer face of ")
    }
}
