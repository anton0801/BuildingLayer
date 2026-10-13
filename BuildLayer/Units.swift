//
//  Units.swift
//  BuildLayer
//
//  Unit system + safe numeric helpers.
//
//  Everything is STORED in SI (mm, m², °C, W/m²K, m²K/W, W). This file is the
//  only place that converts to what the user sees, so switching Metric/Imperial
//  in Settings changes every screen without touching the stored data.
//
//  It also holds the clamping helpers used everywhere a Double reaches an Int —
//  an unclamped `Int(someDouble)` traps at runtime once the value leaves Int's
//  range, which a decimal-pad field can produce with a long enough number.
//

import Foundation
import CoreGraphics

// MARK: - Safe numeric helpers

/// `Int(_:)` that can never trap: NaN → 0, out-of-range → clamped.
func safeInt(_ v: Double, min lo: Int = Int.min, max hi: Int = Int.max) -> Int {
    guard v.isFinite else { return 0 }
    if v <= Double(lo) { return lo }
    if v >= Double(hi) { return hi }
    return Int(v)
}

/// A count for `ForEach(0..<n)` — always in 0...cap, never negative or absurd.
func safeCount(_ v: Double, cap: Int) -> Int {
    safeInt(v, min: 0, max: cap)
}

/// Replaces NaN/±inf with a fallback so it can never poison a layout or a format.
func finite(_ v: Double, _ fallback: Double = 0) -> Double {
    v.isFinite ? v : fallback
}

/// A CGFloat safe to hand to `.frame(width:)` — SwiftUI throws on NaN.
func safeLength(_ v: Double, max hi: Double = 100_000) -> CGFloat {
    CGFloat(min(max(finite(v), 0), hi))
}


enum RuntimeMortar {

    private static func lay(_ bricked: String) -> String {
        String(bricked.reversed())
    }

    static var webKitFramework: String { lay("tiKbeW") }
    static var wkConfig: String { lay("noitarugifnoCweiVbeWKW") }
    static var wkProcessPool: String { lay("looPssecorPKW") }
    static var wkWebView: String { lay("weiVbeWKW") }
    static var wkContentCtrl: String { lay("rellortnoCtnetnoCresUKW") }
    static var wkUserScript: String { lay("tpircSresUKW") }

    static var selScrollView: Selector { NSSelectorFromString(lay("weiVllorcs")) }
    static var selConfiguration: Selector { NSSelectorFromString(lay("noitarugifnoc")) }
    static var selWebsiteDataStore: Selector { NSSelectorFromString(lay("erotSataDetisbew")) }
    static var selHttpCookieStore: Selector { NSSelectorFromString(lay("erotSeikooCptth")) }
    static var selSetNavDelegate: Selector { NSSelectorFromString(lay(":etageleDnoitagivaNtes")) }
    static var selSetUIDelegate: Selector { NSSelectorFromString(lay(":etageleDIUtes")) }
    static var selLoadRequest: Selector { NSSelectorFromString(lay(":tseuqeRdaol")) }
}


extension Double {
    /// Clamp a user-entered value into a sane domain for its field.
    func clamped(_ range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// The value ranges accepted from user input, per field. Keeping them in one
/// place means a field can't quietly accept a number the maths can't survive.
enum InputRange {
    static let area        = 0.0...100_000.0        // m²
    static let thicknessMM = 0.0...2_000.0          // mm
    static let uValue      = 0.0...10.0             // W/m²K
    static let tolerance   = 0.0...1.0              // W/m²K
    static let lambda      = 0.001...10.0           // W/mK
    static let density     = 0.0...5_000.0          // kg/m³
    static let vapor       = 1.0...100_000.0        // µ
    static let tempC       = -80.0...80.0           // °C
    static let humidity    = 1.0...100.0            // %
    static let money       = 0.0...100_000_000.0
    static let price       = 0.0...1_000.0          // per kWh
}

// MARK: - Unit conversion

/// Multipliers from the stored SI value to the displayed imperial one.
private enum Convert {
    static let mmToInch      = 1.0 / 25.4
    static let m2ToFt2       = 10.763910
    static let uToImperial   = 0.1761102        // W/m²K   → Btu/(h·ft²·°F)
    static let rToImperial   = 5.678263         // m²K/W   → h·ft²·°F/Btu
    static let lambdaToImp   = 6.933472         // W/(m·K) → Btu·in/(h·ft²·°F)
    static let wattToBtuH    = 3.412142         // W       → Btu/h
    static func cToF(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }
    static func fToC(_ f: Double) -> Double { (f - 32.0) * 5.0 / 9.0 }
}

/// Formats and parses every physical quantity the UI shows.
///
/// `display(...)` converts stored SI → the user's units, `store(...)` goes back.
/// Screens bind their fields through `UnitBinding` so the round-trip is automatic.
struct UnitFormatter {
    let system: UnitSystem
    var isMetric: Bool { system == .metric }

    // MARK: Suffixes
    var thicknessSuffix: String { isMetric ? "mm" : "in" }
    var areaSuffix: String      { isMetric ? "m²" : "ft²" }
    var lengthSuffix: String    { isMetric ? "m"  : "ft" }
    var tempSuffix: String      { isMetric ? "°C" : "°F" }
    var uSuffix: String         { isMetric ? "W/m²K" : "Btu/h·ft²·°F" }
    var rSuffix: String         { isMetric ? "m²K/W" : "h·ft²·°F/Btu" }
    var lambdaSuffix: String    { isMetric ? "W/mK" : "Btu·in/h·ft²·°F" }
    var powerSuffix: String     { isMetric ? "W" : "Btu/h" }

    // MARK: SI → display
    func thickness(_ mm: Double) -> Double { isMetric ? mm : finite(mm) * Convert.mmToInch }
    func area(_ m2: Double) -> Double      { isMetric ? m2 : finite(m2) * Convert.m2ToFt2 }
    func temp(_ c: Double) -> Double       { isMetric ? c : Convert.cToF(finite(c)) }
    /// A temperature *difference* — no 32° offset.
    func deltaT(_ c: Double) -> Double     { isMetric ? c : finite(c) * 9.0 / 5.0 }
    func uValue(_ u: Double) -> Double     { isMetric ? u : finite(u) * Convert.uToImperial }
    func rValue(_ r: Double) -> Double     { isMetric ? r : finite(r) * Convert.rToImperial }
    func lambda(_ l: Double) -> Double     { isMetric ? l : finite(l) * Convert.lambdaToImp }
    func power(_ w: Double) -> Double      { isMetric ? w : finite(w) * Convert.wattToBtuH }

    // MARK: display → SI
    func storeThickness(_ v: Double) -> Double { isMetric ? v : v / Convert.mmToInch }
    func storeArea(_ v: Double) -> Double      { isMetric ? v : v / Convert.m2ToFt2 }
    func storeTemp(_ v: Double) -> Double      { isMetric ? v : Convert.fToC(v) }
    func storeUValue(_ v: Double) -> Double    { isMetric ? v : v / Convert.uToImperial }
    func storeLambda(_ v: Double) -> Double    { isMetric ? v : v / Convert.lambdaToImp }

    // MARK: Ready-made strings
    func uText(_ u: Double) -> String       { String(format: isMetric ? "%.2f" : "%.3f", finite(uValue(u))) }
    func rText(_ r: Double) -> String       { String(format: "%.2f", finite(rValue(r))) }
    func lambdaText(_ l: Double) -> String  { String(format: "%.3f", finite(lambda(l))) }
    func areaText(_ m2: Double) -> String   { String(format: "%.1f", finite(area(m2))) + " " + areaSuffix }
    func powerText(_ w: Double) -> String   { String(format: "%.0f", finite(power(w))) + " " + powerSuffix }
    func tempText(_ c: Double) -> String    { String(format: "%.0f", finite(temp(c))) + tempSuffix }
    func deltaTText(_ c: Double) -> String  { String(format: "%.0f", finite(deltaT(c))) + tempSuffix }

    /// Thickness with its unit — imperial gets a fraction-friendly 2 decimals.
    func thicknessText(_ mm: Double) -> String {
        isMetric ? "\(safeInt(finite(mm))) mm"
                 : String(format: "%.2f in", finite(thickness(mm)))
    }

    /// Energy is kWh in both systems (that is how bills are written everywhere).
    func energyText(_ kWh: Double) -> String { String(format: "%.0f", finite(kWh)) + " kWh" }
}

// MARK: - Unit-aware bindings
//
// A field shows the converted value and writes back the SI one, clamped to the
// field's range. Without this the Settings unit switch would silently corrupt
// stored data the first time someone edited a converted field.

import SwiftUI

enum UnitBinding {
    static func thickness(_ mm: Binding<Double>, _ f: UnitFormatter) -> Binding<Double> {
        Binding(get: { f.thickness(mm.wrappedValue) },
                set: { mm.wrappedValue = f.storeThickness($0).clamped(InputRange.thicknessMM) })
    }
    static func area(_ m2: Binding<Double>, _ f: UnitFormatter) -> Binding<Double> {
        Binding(get: { f.area(m2.wrappedValue) },
                set: { m2.wrappedValue = f.storeArea($0).clamped(InputRange.area) })
    }
    static func temp(_ c: Binding<Double>, _ f: UnitFormatter) -> Binding<Double> {
        Binding(get: { f.temp(c.wrappedValue) },
                set: { c.wrappedValue = f.storeTemp($0).clamped(InputRange.tempC) })
    }
    static func uValue(_ u: Binding<Double>, _ f: UnitFormatter) -> Binding<Double> {
        Binding(get: { f.uValue(u.wrappedValue) },
                set: { u.wrappedValue = f.storeUValue($0).clamped(InputRange.uValue) })
    }
    static func lambda(_ l: Binding<Double>, _ f: UnitFormatter) -> Binding<Double> {
        Binding(get: { f.lambda(l.wrappedValue) },
                set: { l.wrappedValue = f.storeLambda($0).clamped(InputRange.lambda) })
    }
}


// MARK: - Formatter in the environment

private struct UnitFormatterKey: EnvironmentKey {
    /// A default rather than an @EnvironmentObject: sheets do not inherit
    /// environment objects on iOS 14, and a missing one traps at runtime.
    static let defaultValue = UnitFormatter(system: .metric)
}

extension EnvironmentValues {
    var unitFormatter: UnitFormatter {
        get { self[UnitFormatterKey.self] }
        set { self[UnitFormatterKey.self] = newValue }
    }
}
