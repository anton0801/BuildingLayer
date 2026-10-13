//
//  SyncDTO.swift
//  BuildLayer
//
//  Translation between the domain models and the wire format.
//
//  Kept as an explicit mapping rather than making the models Codable to JSON
//  directly: the app's storage format and the API contract are allowed to drift
//  apart, and a rename in Swift must not silently become a breaking API change.
//

import Foundation

enum SyncDTO {

    // MARK: - Outgoing

    static func encode(_ element: ThermalElement) -> [String: Any] {
        var payload: [String: Any] = [
            "uuid": element.id.uuidString,
            "name": element.name,
            "type": element.type.rawValue,
            "area": finite(element.area),
            "target_u": finite(element.targetU),
            "tolerance": finite(element.tolerance),
            "inside_temp": finite(element.insideTemp),
            "outside_temp": finite(element.outsideTemp),
            "indoor_rh": finite(element.indoorRH),
            "outdoor_rh": finite(element.outdoorRH),
            "status": element.status.rawValue,
            "insulation_name": element.insulationName,
            "notes": element.notes,
            "has_vapor_control": element.hasVaporControl,
            "existing_u": finite(element.existingU),
            "cost_insulation": finite(element.costInsulation),
            "cost_membrane": finite(element.costMembrane),
            "cost_finish": finite(element.costFinish),
            "cost_reserve_pct": finite(element.costReservePct),
            "signoff_by": element.signoffBy,
            "date_created_ms": element.dateCreated.msSinceEpoch,
            "updated_ms": element.dateModified.msSinceEpoch,
            "deleted": false,
            "layers": element.layers.map(encodeLayer),
        ]
        // Optionals are omitted rather than sent as null so the server's
        // decodeIfPresent-style defaults apply.
        if let manual = element.manualStatus { payload["manual_status"] = manual.rawValue }
        if let date = element.signoffDate { payload["signoff_ms"] = date.msSinceEpoch }
        if !element.signatureStrokes.isEmpty {
            payload["signature"] = element.signatureStrokes.map { stroke in
                stroke.map { ["x": $0.x, "y": $0.y] }
            }
        }
        return payload
    }

    private static func encodeLayer(_ layer: Layer) -> [String: Any] {
        [
            "uuid": layer.id.uuidString,
            "material_name": layer.materialName,
            "lambda": finite(layer.lambda),
            "vapor_resistance": finite(layer.vaporResistance),
            "thickness_mm": finite(layer.thicknessMM),
            "is_insulation": layer.isInsulation,
            "side": layer.side,
        ]
    }

    static func encode(_ material: Material) -> [String: Any] {
        [
            "uuid": material.id.uuidString,
            "name": material.name,
            "lambda": finite(material.lambda),
            "density": finite(material.density),
            "vapor_resistance": finite(material.vaporResistance),
            "is_insulation": material.isInsulation,
            "is_custom": material.isCustom,
            "updated_ms": material.dateModified.msSinceEpoch,
            "deleted": false,
        ]
    }

    static func encode(_ reminder: Reminder) -> [String: Any] {
        var payload: [String: Any] = [
            "uuid": reminder.id.uuidString,
            "kind": reminder.kind.rawValue,
            "fire_at_ms": reminder.date.msSinceEpoch,
            "is_on": reminder.isOn,
            "element_name": reminder.elementName,
            "updated_ms": reminder.dateModified.msSinceEpoch,
            "deleted": false,
        ]
        if let elementID = reminder.elementID { payload["element_uuid"] = elementID.uuidString }
        return payload
    }

    static func encode(_ entry: HistoryEntry) -> [String: Any] {
        [
            "uuid": entry.id.uuidString,
            "title": entry.title,
            "detail": entry.detail,
            "icon": entry.icon,
            "happened_at_ms": entry.date.msSinceEpoch,
            "deleted": false,
        ]
    }

    static func encodeTombstone(_ tombstone: Tombstone) -> [String: Any] {
        [
            "uuid": tombstone.recordID.uuidString,
            "deleted": true,
            "updated_ms": tombstone.deletedAt.msSinceEpoch,
        ]
    }

    // MARK: - Incoming

    struct RemoteElement {
        var element: ThermalElement
        var deleted: Bool
        var updatedMs: Double
    }
    struct RemoteMaterial {
        var material: Material
        var deleted: Bool
        var updatedMs: Double
    }
    struct RemoteReminder {
        var reminder: Reminder
        var deleted: Bool
        var updatedMs: Double
    }
    struct RemoteHistory {
        var entry: HistoryEntry
        var deleted: Bool
    }

    static func decodeElement(_ row: [String: Any]) -> RemoteElement? {
        guard let uuidString = row["uuid"] as? String, let id = UUID(uuidString: uuidString) else { return nil }
        let updatedMs = double(row["updated_ms"]) ?? 0
        let deleted = row["deleted"] as? Bool ?? false

        var element = ThermalElement(
            id: id,
            name: row["name"] as? String ?? "",
            type: ElementType(rawValue: row["type"] as? String ?? "Wall") ?? .wall,
            area: double(row["area"]) ?? 0,
            targetU: double(row["target_u"]) ?? 0.3,
            tolerance: double(row["tolerance"]) ?? 0.02,
            insideTemp: double(row["inside_temp"]) ?? 20,
            outsideTemp: double(row["outside_temp"]) ?? -5,
            indoorRH: double(row["indoor_rh"]) ?? 55
        )
        element.outdoorRH = double(row["outdoor_rh"]) ?? 85
        element.status = ElementStatus(rawValue: row["status"] as? String ?? "") ?? .inProgress
        element.manualStatus = (row["manual_status"] as? String).flatMap { ElementStatus(rawValue: $0) }
        element.insulationName = row["insulation_name"] as? String ?? ""
        element.notes = row["notes"] as? String ?? ""
        element.hasVaporControl = row["has_vapor_control"] as? Bool ?? false
        element.existingU = double(row["existing_u"]) ?? 0
        element.costInsulation = double(row["cost_insulation"]) ?? 0
        element.costMembrane = double(row["cost_membrane"]) ?? 0
        element.costFinish = double(row["cost_finish"]) ?? 0
        element.costReservePct = double(row["cost_reserve_pct"]) ?? 10
        element.signoffBy = row["signoff_by"] as? String ?? ""
        if let ms = double(row["signoff_ms"]) { element.signoffDate = Date(msSinceEpoch: ms) }
        if let ms = double(row["date_created_ms"]) { element.dateCreated = Date(msSinceEpoch: ms) }
        element.dateModified = Date(msSinceEpoch: updatedMs)

        if let strokes = row["signature"] as? [[[String: Any]]] {
            element.signatureStrokes = strokes.map { stroke in
                stroke.compactMap { point -> CGPointCodable? in
                    guard let x = double(point["x"]), let y = double(point["y"]) else { return nil }
                    return CGPointCodable(x: x, y: y)
                }
            }.filter { !$0.isEmpty }
        }

        if let layers = row["layers"] as? [[String: Any]] {
            element.layers = layers.map { layer in
                Layer(
                    id: (layer["uuid"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID(),
                    materialName: layer["material_name"] as? String ?? "",
                    lambda: double(layer["lambda"]) ?? 0.04,
                    vaporResistance: double(layer["vapor_resistance"]) ?? 1,
                    thicknessMM: double(layer["thickness_mm"]) ?? 0,
                    isInsulation: layer["is_insulation"] as? Bool ?? false,
                    side: layer["side"] as? String ?? "Core"
                )
            }
        }
        return RemoteElement(element: element, deleted: deleted, updatedMs: updatedMs)
    }

    static func decodeMaterial(_ row: [String: Any]) -> RemoteMaterial? {
        guard let uuidString = row["uuid"] as? String, let id = UUID(uuidString: uuidString) else { return nil }
        let updatedMs = double(row["updated_ms"]) ?? 0
        let material = Material(
            id: id,
            name: row["name"] as? String ?? "",
            lambda: double(row["lambda"]) ?? 0.04,
            density: double(row["density"]) ?? 0,
            vaporResistance: double(row["vapor_resistance"]) ?? 1,
            isInsulation: row["is_insulation"] as? Bool ?? false,
            isCustom: row["is_custom"] as? Bool ?? true,
            dateModified: Date(msSinceEpoch: updatedMs)
        )
        return RemoteMaterial(material: material,
                              deleted: row["deleted"] as? Bool ?? false,
                              updatedMs: updatedMs)
    }

    static func decodeReminder(_ row: [String: Any]) -> RemoteReminder? {
        guard let uuidString = row["uuid"] as? String, let id = UUID(uuidString: uuidString),
              let kind = ReminderKind(rawValue: row["kind"] as? String ?? "") else { return nil }
        let updatedMs = double(row["updated_ms"]) ?? 0
        let reminder = Reminder(
            id: id,
            kind: kind,
            date: Date(msSinceEpoch: double(row["fire_at_ms"]) ?? Date().msSinceEpoch),
            isOn: row["is_on"] as? Bool ?? true,
            elementName: row["element_name"] as? String ?? "",
            elementID: (row["element_uuid"] as? String).flatMap { UUID(uuidString: $0) },
            dateModified: Date(msSinceEpoch: updatedMs)
        )
        return RemoteReminder(reminder: reminder,
                              deleted: row["deleted"] as? Bool ?? false,
                              updatedMs: updatedMs)
    }

    static func decodeHistory(_ row: [String: Any]) -> RemoteHistory? {
        guard let uuidString = row["uuid"] as? String, let id = UUID(uuidString: uuidString) else { return nil }
        let entry = HistoryEntry(
            id: id,
            title: row["title"] as? String ?? "",
            detail: row["detail"] as? String ?? "",
            icon: row["icon"] as? String ?? Icon.doc,
            date: Date(msSinceEpoch: double(row["happened_at_ms"]) ?? Date().msSinceEpoch)
        )
        return RemoteHistory(entry: entry, deleted: row["deleted"] as? Bool ?? false)
    }

    // MARK: - Helpers

    /// JSON numbers arrive as NSNumber, Int, Double or occasionally String
    /// depending on the encoder, so every read goes through one coercion.
    private static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d.isFinite ? d : 0 }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
