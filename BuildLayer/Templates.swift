//
//  Templates.swift
//  BuildLayer
//
//  Ready-made build-ups. Starting an element meant adding five layers by hand
//  through a modal picker every time; a template drops a complete, correctly
//  ordered (outside → inside) stack in one tap, which the user then tunes.
//
//  Also holds the image downscaler: photos used to be stored at full camera
//  resolution, which is megabytes per element in the persisted store.
//

import SwiftUI
import UIKit

// MARK: - Build-up templates

struct BuildUpTemplate: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let type: ElementType
    let layers: [Layer]

    /// Indicative U for the card, so the user can pick by performance.
    func previewU() -> Double {
        var e = ThermalElement.newDefault(type: type)
        e.layers = layers
        return ThermalEngine.uValue(of: e)
    }
}

enum TemplateLibrary {

    private static func layer(_ name: String, _ lambda: Double, _ mu: Double,
                              _ mm: Double, _ insulation: Bool, _ side: String) -> Layer {
        Layer(materialName: name, lambda: lambda, vaporResistance: mu,
              thicknessMM: mm, isInsulation: insulation, side: side)
    }

    static let all: [BuildUpTemplate] = [
        BuildUpTemplate(
            name: "Insulated cavity wall",
            detail: "Brick outer leaf, full-fill mineral wool, block inner leaf",
            type: .wall,
            layers: [
                layer("Brickwork (outer)", 0.77, 10, 102, false, "Outside"),
                layer("Mineral wool (slab)", 0.035, 1, 100, true, "Core"),
                layer("Concrete block", 1.13, 60, 100, false, "Inside"),
                layer("Gypsum plasterboard", 0.21, 8, 12.5, false, "Inside")
            ]),

        BuildUpTemplate(
            name: "External wall insulation",
            detail: "Render, PIR board over existing solid masonry",
            type: .wall,
            layers: [
                layer("Cement render", 0.87, 25, 15, false, "Outside"),
                layer("PIR board", 0.022, 60, 100, true, "Outside"),
                layer("Brickwork (outer)", 0.77, 10, 215, false, "Core"),
                layer("Gypsum plasterboard", 0.21, 8, 12.5, false, "Inside")
            ]),

        BuildUpTemplate(
            name: "Timber frame wall",
            detail: "Cladding, sheathing, insulated studs, service void",
            type: .wall,
            layers: [
                layer("Cement render", 0.87, 25, 15, false, "Outside"),
                layer("OSB / sheathing", 0.13, 50, 9, false, "Outside"),
                layer("Glass wool (quilt)", 0.040, 1, 140, true, "Core"),
                layer("OSB / sheathing", 0.13, 50, 9, false, "Inside"),
                layer("Gypsum plasterboard", 0.21, 8, 12.5, false, "Inside")
            ]),

        BuildUpTemplate(
            name: "Cold pitched roof",
            detail: "Quilt between and over ceiling joists",
            type: .roof,
            layers: [
                layer("Glass wool (quilt)", 0.040, 1, 100, true, "Outside"),
                layer("Softwood timber", 0.13, 50, 100, false, "Core"),
                layer("Glass wool (quilt)", 0.040, 1, 200, true, "Core"),
                layer("Gypsum plasterboard", 0.21, 8, 12.5, false, "Inside")
            ]),

        BuildUpTemplate(
            name: "Warm flat roof",
            detail: "Membrane over PIR on a concrete deck",
            type: .roof,
            layers: [
                layer("PIR board", 0.022, 60, 140, true, "Outside"),
                layer("Reinforced concrete", 2.3, 130, 150, false, "Core"),
                layer("Gypsum plasterboard", 0.21, 8, 12.5, false, "Inside")
            ]),

        BuildUpTemplate(
            name: "Insulated ground floor",
            detail: "Screed over EPS on a concrete slab",
            type: .floor,
            layers: [
                layer("Reinforced concrete", 2.3, 130, 150, false, "Outside"),
                layer("EPS board", 0.038, 30, 120, true, "Core"),
                layer("Screed", 1.15, 30, 65, false, "Inside")
            ]),

        BuildUpTemplate(
            name: "Suspended timber floor",
            detail: "Wood fibre between joists, boarded over",
            type: .floor,
            layers: [
                layer("Wood fibre board", 0.040, 5, 150, true, "Outside"),
                layer("Softwood timber", 0.13, 50, 150, false, "Core"),
                layer("Plywood", 0.14, 110, 22, false, "Inside")
            ])
    ]

    static func templates(for type: ElementType) -> [BuildUpTemplate] {
        all.filter { $0.type == type }
    }

    /// Fresh layer ids each time, so applying one template twice does not create
    /// duplicate identities inside a ForEach.
    static func instantiate(_ template: BuildUpTemplate) -> [Layer] {
        template.layers.map { source in
            var l = source
            l.id = UUID()
            return l
        }
    }
}

// MARK: - Image downscaling

enum ImageStore {
    /// Longest edge of a stored photo. A markup photo is looked at on a phone
    /// and printed into a report thumbnail — full sensor resolution buys nothing
    /// and costs megabytes in the persisted store.
    static let maxDimension: CGFloat = 1400
    static let jpegQuality: CGFloat = 0.72

    /// Downscale and JPEG-encode, honouring the image's orientation.
    static func encode(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                     // target is already in pixels
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: jpegQuality)
    }

    /// Human-readable size of the stored photo, for the Data screen in Settings.
    static func sizeText(_ data: Data?) -> String {
        guard let data = data else { return "—" }
        let kb = Double(data.count) / 1024
        return kb > 1024 ? String(format: "%.1f MB", kb / 1024)
                         : String(format: "%.0f KB", kb)
    }
}
