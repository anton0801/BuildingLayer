//
//  Theme.swift
//  BuildLayer
//
//  Design system: adaptive colour palette + gradients + iOS-14-safe icon catalog.
//  Every colour is an adaptive UIColor so switching appearance (system/light/dark)
//  in Settings recolours the whole app instantly via .preferredColorScheme.
//

import SwiftUI

// MARK: - Hex Color Helper

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

private func uiColor(_ hex: String) -> UIColor {
    let scanner = Scanner(string: hex.replacingOccurrences(of: "#", with: ""))
    var value: UInt64 = 0
    scanner.scanHexInt64(&value)
    let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
    let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
    let b = CGFloat(value & 0x0000FF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: 1.0)
}

/// Builds a colour that automatically swaps between dark/light appearance.
private func adaptive(dark: String, light: String) -> Color {
    let darkUI = uiColor(dark)
    let lightUI = uiColor(light)
    return Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? darkUI : lightUI
    })
}

// MARK: - Palette

enum Theme {

    // Backgrounds — dark navy in dark mode, soft blue in light mode.
    static let bg        = adaptive(dark: "0D1A2D", light: "EAF2FC")
    static let bgDeep    = adaptive(dark: "081223", light: "DCE9F7")
    static let bgSoft    = adaptive(dark: "13243B", light: "F3F8FE")

    // Cards stay bright in both modes (white / light-blue) per the spec.
    static let card      = adaptive(dark: "FFFFFF", light: "FFFFFF")
    static let cardBlue  = adaptive(dark: "E7F0FB", light: "EAF1FB")
    static let cardHover = adaptive(dark: "DBE9F7", light: "DFEAF8")
    static let cardBorder = Color(hex: "C6D8ED")
    static let divider   = Color.white.opacity(0.12)

    // Accents (identical in both appearances).
    static let primary      = Color(hex: "F77B1C")
    static let primaryActive = Color(hex: "E0660A")
    static let primaryHi    = Color(hex: "FF9B4E")
    static let secondary    = Color(hex: "F4C32C")
    static let secondaryHi  = Color(hex: "FFD964")

    static let layer        = Color(hex: "4DA3F0")
    static let insulation   = Color(hex: "F77B1C")
    static let cold         = Color(hex: "34C6E0")

    // Status
    static let pass     = Color(hex: "38C172")
    static let progress = Color(hex: "4DA3F0")
    static let warn     = Color(hex: "F4C32C")
    static let fail     = Color(hex: "EF4444")

    // Text on the dark/light *background* (titles).
    static let title     = adaptive(dark: "FFFFFF", light: "102A4A")
    static let subtitle  = adaptive(dark: "A9C0DE", light: "44587A")
    static let titleDim  = adaptive(dark: "8AA0BE", light: "7187A6")

    // Text on bright cards (always dark navy — readable on white).
    static let cardText    = Color(hex: "102A4A")
    static let cardSubtext = Color(hex: "44587A")
    static let cardInactive = Color(hex: "8AA0BE")

    static let buttonText = Color(hex: "0D1A2D")

    // Gradients
    static var bgGradient: LinearGradient {
        LinearGradient(colors: [bgDeep, bg, bgSoft],
                       startPoint: .top, endPoint: .bottom)
    }
    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primaryHi, primary, primaryActive],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var heatGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: "FFD964"), primary, Color(hex: "E0660A")],
                       startPoint: .leading, endPoint: .trailing)
    }
    static var coldGradient: LinearGradient {
        LinearGradient(colors: [cold, layer], startPoint: .top, endPoint: .bottom)
    }

    // Effects
    static let warmGlow = Color(hex: "F77B1C").opacity(0.32)
    static let coldGlow = Color(hex: "34C6E0").opacity(0.26)
    static let shadow   = Color.black.opacity(0.55)
}

// MARK: - Typography

extension Font {
    static func bl(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let blTitle   = Font.system(size: 28, weight: .heavy, design: .rounded)
    static let blHeading = Font.system(size: 21, weight: .bold, design: .rounded)
    static let blBody    = Font.system(size: 16, weight: .medium, design: .rounded)
    static let blCaption = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let blNumber  = Font.system(size: 34, weight: .heavy, design: .rounded)
}

// MARK: - Icon Catalog (all guaranteed available in iOS 14.0)
//
// Every SF Symbol used in the app is referenced through this enum so we can be
// certain none render blank on iOS 14. Adding a symbol that was introduced later
// would show an empty box — keeping them here makes that impossible by accident.

enum Icon {
    // Tabs
    static let elements   = "square.grid.2x2.fill"
    static let layers     = "square.stack.3d.up.fill"
    static let uValue     = "gauge"
    static let insulation = "flame.fill"
    static let reports    = "doc.text.fill"

    // Common
    static let settings   = "gearshape.fill"
    static let add        = "plus.circle.fill"
    static let addSmall   = "plus"
    static let remove     = "minus.circle.fill"
    static let trash      = "trash.fill"
    static let edit       = "square.and.pencil"
    static let close      = "xmark.circle.fill"
    static let check      = "checkmark.circle.fill"
    static let chevronR   = "chevron.right"
    static let chevronL   = "chevron.left"
    static let chevronD   = "chevron.down"
    static let arrowR     = "arrow.right"
    static let arrowUpR   = "arrow.up.right"
    static let duplicate  = "doc.on.doc.fill"
    static let share      = "square.and.arrow.up"
    static let clear      = "xmark"
    static let back       = "chevron.left"

    // Domain
    static let wall       = "rectangle.split.3x1.fill"
    static let roof       = "house.fill"
    static let floor      = "rectangle.fill"
    static let house      = "house.fill"
    static let thermo     = "thermometer"
    static let heat       = "flame.fill"
    static let cold       = "snowflake"
    static let drop       = "drop.fill"
    static let ruler      = "ruler.fill"
    static let hammer     = "hammer.fill"
    static let wrench     = "wrench.and.screwdriver.fill"
    static let target     = "scope"
    static let gaugeAlt   = "speedometer"
    static let bell       = "bell.fill"
    static let bellSlash  = "bell.slash.fill"
    static let calendar   = "calendar"
    static let clock      = "clock.fill"
    static let camera     = "camera.fill"
    static let photo      = "photo.fill"
    static let pin        = "mappin.circle.fill"
    static let map        = "map.fill"
    static let money      = "dollarsign.circle.fill"
    static let chart      = "chart.bar.fill"
    static let pie        = "chart.pie.fill"
    static let warning    = "exclamationmark.triangle.fill"
    static let info       = "info.circle.fill"
    static let list       = "list.bullet"
    static let slider     = "slider.horizontal.3"
    static let bolt       = "bolt.fill"
    static let sun        = "sun.max.fill"
    static let wind       = "wind"
    static let shield     = "checkmark.shield.fill"
    static let sign       = "signature"
    static let sparkles   = "sparkles"
    static let stack      = "square.stack.3d.up.fill"
    static let lightbulb  = "lightbulb.fill"
    static let cube       = "cube.fill"
    static let box        = "shippingbox.fill"
    static let moon       = "moon.fill"
    static let circleHalf = "circle.lefthalf.fill"
    static let gear       = "gearshape.fill"
    static let doc        = "doc.text.fill"
    static let flag       = "flag.fill"
    static let tag        = "tag.fill"
    static let leaf       = "leaf.fill"
    static let cloud      = "icloud.fill"
    static let refresh    = "arrow.clockwise"
    static let link       = "link"

    /// Icon for an element type.
    static func element(_ type: String) -> String {
        switch type.lowercased() {
        case "roof":  return roof
        case "floor": return floor
        default:      return wall
        }
    }
}
