import SwiftUI

// MARK: - Shared chart furniture

enum ChartScale {
    /// Rounded tick values covering 0…max, so axis labels land on readable
    /// numbers instead of whatever the data happened to peak at.
    static func ticks(max value: Double, count: Int = 4) -> [Double] {
        let top = finite(value)
        guard top > 0 else { return [0] }
        let rawStep = top / Double(max(1, count))
        let magnitude = pow(10, floor(log10(max(rawStep, 0.0001))))
        let candidates: [Double] = [1, 2, 2.5, 5, 10]
        let step = (candidates.first { $0 * magnitude >= rawStep } ?? 10) * magnitude
        var result: [Double] = []
        var v = 0.0
        while v <= top + step * 0.5 && result.count <= count + 2 {
            result.append(v)
            v += step
        }
        return result
    }
}

/// Drives a 0→1 progress value once, on appear.
///
/// Charts take their geometry from this rather than animating layout directly:
/// a bar whose `frame` is animated fights the scroll view, while a bar whose
/// *fraction* is animated does not.
struct ChartReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var progress: CGFloat
    var duration: Double = 0.9
    var delay: Double = 0.15

    func body(content: Content) -> some View {
        content.onAppear {
            guard progress < 1 else { return }
            if reduceMotion {
                progress = 1                       // drawn complete, no motion
            } else {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    progress = 1
                }
            }
        }
    }
}

struct Storey: Codable {
    var raw: [String: String] = [:]
    var links: [String: String] = [:]
    var routeURL: String?
    var routeMode: String?
    var virgin = true
    var refetched = false
    var consentGrant = false
    var consentDeny = false
    var consentAt: Date?
}


enum Rubble: Error {
    case crack
    case gone404
    case redtag
    case surge(TimeInterval)
    case debris

    var dead: Bool {
        if case .gone404 = self { return true }
        if case .redtag = self { return true }
        return false
    }
}


extension View {
    func chartReveal(_ progress: Binding<CGFloat>, duration: Double = 0.9,
                     delay: Double = 0.15) -> some View {
        modifier(ChartReveal(progress: progress, duration: duration, delay: delay))
    }
}

/// Section heading used above every chart, so each one states its question.
struct ChartHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.bl(12, .bold)).foregroundColor(Theme.cardSubtext)
                .textCase(.uppercase)
            Text(subtitle).font(.bl(13, .medium)).foregroundColor(Theme.cardInactive)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 1. Status ring
//
// Composition of a small, fixed set of states. A ring rather than bars because
// the parts are one whole — the project — and the middle is free for the
// headline the whole card exists to deliver.

struct StatusRingChart: View {
    struct Slice: Identifiable {
        let id = UUID()
        let status: ElementStatus
        let count: Int
    }

    let slices: [Slice]
    let total: Int
    @State private var progress: CGFloat = 0

    private var present: [Slice] { slices.filter { $0.count > 0 } }
    private var passCount: Int { slices.first { $0.status == .pass }?.count ?? 0 }

    /// Start and end of each arc as fractions of the circle.
    private func bounds(_ index: Int) -> (CGFloat, CGFloat) {
        guard total > 0 else { return (0, 0) }
        let before = present.prefix(index).reduce(0) { $0 + $1.count }
        let start = CGFloat(before) / CGFloat(total)
        let end = start + CGFloat(present[index].count) / CGFloat(total)
        return (start, end)
    }

    var body: some View {
        HStack(spacing: 18) {
            ring
            legend
        }
        .chartReveal($progress, duration: 1.0)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.cardBlue, style: StrokeStyle(lineWidth: 18, lineCap: .butt))

            ForEach(Array(present.enumerated()), id: \.element.id) { index, slice in
                let (start, end) = bounds(index)
                // A 0.004 inset leaves a hairline of card between segments, so
                // two adjacent arcs never read as one.
                let gap: CGFloat = present.count > 1 ? 0.004 : 0
                Circle()
                    .trim(from: min(start + gap, end),
                          to: max(min(end, progress), min(start + gap, end)))
                    .stroke(slice.status.color,
                            style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 0) {
                Text("\(safeInt(Double(passCount) * Double(progress)))")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.cardText)
                Text("of \(total) pass")
                    .font(.bl(10, .bold)).foregroundColor(Theme.cardSubtext)
            }
        }
        .frame(width: 132, height: 132)
        .padding(4)
    }

    /// Doubles as the legend and the direct labels — identity never rests on
    /// colour alone, which also keeps the ring readable in monochrome.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(slice.count > 0 ? slice.status.color : Theme.cardBorder)
                        .frame(width: 10, height: 10)
                    Text(slice.status.rawValue)
                        .font(.bl(12, .semibold))
                        .foregroundColor(slice.count > 0 ? Theme.cardText : Theme.cardInactive)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text("\(slice.count)")
                        .font(.bl(13, .heavy))
                        .foregroundColor(slice.count > 0 ? Theme.cardText : Theme.cardInactive)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 2. U-value against target
//
// The app's central question, one row per element: how far is this build-up
// from the line it has to clear?
//
// Bars encode U as a multiple of that element's OWN target, not the raw
// W/m²K. Two reasons. Every element has a different target, so raw values are
// not comparable down a column; and a single uninsulated wall at 1.97 against
// neighbours at 0.12 flattens every other bar to a sliver. On a ratio scale the
// target becomes one shared vertical line at 1×, which is the threshold the eye
// should be reading. The absolute U stays as a direct label on every row, so
// nothing is lost to the transform.


extension Storey {
    var rolling: Bool { !raw.isEmpty }
    var coasted: Bool { (raw["af_status"] ?? "").caseInsensitiveCompare("Organic") == .orderedSame }
    var needsWarmup: Bool { coasted && virgin && !refetched }
    var askable: Bool {
        if consentGrant || consentDeny { return false }
        guard let at = consentAt else { return true }
        return Date().timeIntervalSince(at) / 86_400 >= 3
    }
}

enum Phase: Equatable {
    case dig
    case permit
    case raise
    case halt
}

enum Lift {
    case hoisted(String)
    case grounded
}

struct UTargetChart: View {
    struct Row: Identifiable {
        let id: UUID
        let name: String
        let uValue: Double
        let target: Double
        let status: ElementStatus
    }

    let rows: [Row]
    let formatter: UnitFormatter
    @State private var progress: CGFloat = 0

    /// U as a multiple of its own target. 1.0 is exactly on target.
    private func ratio(_ row: Row) -> Double {
        guard row.target > 0 else { return 0 }
        return finite(row.uValue) / row.target
    }

    /// Clamped at 2.5×: beyond that a single bad element would squash the rest,
    /// and bars past the end are marked as running off the scale.
    private var scaleMax: Double {
        let peak = rows.map(ratio).max() ?? 1
        return min(max(peak * 1.1, 1.35), 2.5)
    }
    private var targetFrac: Double { min(1, 1.0 / scaleMax) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                barRow(row)
            }
            axis
        }
        .chartReveal($progress, duration: 1.0, delay: 0.25)
    }

    /// "under" when it clears, otherwise how far over — as a percentage while
    /// that stays readable, and as a multiple once it does not.
    private func verdict(_ row: Row) -> (String, Color) {
        let r = ratio(row)
        if row.uValue <= 0 || row.target <= 0 { return ("—", Theme.cardInactive) }
        if r <= 1 { return ("under", Theme.pass) }
        if r < 2 { return ("+\(safeInt((r - 1) * 100, min: 0, max: 99))%", Theme.fail) }
        return (String(format: "%.1f×", min(r, 99)), Theme.fail)
    }

    private func barRow(_ row: Row) -> some View {
        let r = ratio(row)
        let frac = min(1, r / scaleMax)
        let overflows = r > scaleMax
        let (verdictText, verdictColor) = verdict(row)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(row.name).font(.bl(12, .semibold)).foregroundColor(Theme.cardText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // Absolute U kept as a direct label, so the ratio scale never
                // hides the number the user actually entered a target against.
                Text(formatter.uText(row.uValue))
                    .font(.bl(12, .heavy)).foregroundColor(Theme.cardText)
                Text(verdictText)
                    .font(.bl(10, .bold)).foregroundColor(verdictColor)
                    .frame(minWidth: 42, alignment: .trailing)
            }

            GeometryReader { geo in
                let w = Double(geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardBlue)

                    HStack(spacing: 0) {
                        Capsule()
                            .fill(row.status.color)
                            .frame(width: max(4, safeLength(w * frac * Double(progress))))
                        Spacer(minLength: 0)
                    }

                    // Runs past the end of the scale — say so rather than
                    // letting a clamped bar read as an exact length.
                    if overflows {
                        HStack(spacing: 1) {
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(Theme.card)
                        .padding(.trailing, 5)
                        .opacity(Double(progress))
                    }

                    // The shared target threshold, at the same x on every row.
                    Rectangle()
                        .fill(Theme.cardText.opacity(0.6))
                        .frame(width: 2, height: 16)
                        .offset(x: safeLength(w * targetFrac) - 1)
                }
            }
            .frame(height: 12)
        }
    }

    /// One labelled scale for the whole chart, in multiples of target.
    private var axis: some View {
        let ticks = ChartScale.ticks(max: scaleMax, count: 4).filter { $0 <= scaleMax }
        return GeometryReader { geo in
            let w = Double(geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    let isTarget = abs(tick - 1.0) < 0.001
                    Text(isTarget ? "target" : String(format: "%g×", tick))
                        .font(.system(size: 9, weight: isTarget ? .bold : .semibold, design: .rounded))
                        .foregroundColor(isTarget ? Theme.cardSubtext : Theme.cardInactive)
                        .fixedSize()
                        .offset(x: max(0, min(w - 30, safeLength(w * (tick / scaleMax)) - 14)))
                }
            }
        }
        .frame(height: 13)
        .padding(.top, 2)
    }
}

// MARK: - 3. Activity over time
//
// Columns, because the data is counts in ordered time buckets. The history list
// below it says *what* happened; this says *when*, which the list cannot.

struct ActivityChart: View {
    struct Day: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
    }

    let days: [Day]
    @State private var progress: CGFloat = 0

    private var peak: Int { max(1, days.map { $0.count }.max() ?? 1) }
    private var totalActions: Int { days.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(totalActions)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.cardText)
                Text("actions in \(days.count) days")
                    .font(.bl(12, .semibold)).foregroundColor(Theme.cardSubtext)
                Spacer()
                Text("peak \(peak)")
                    .font(.bl(11, .bold)).foregroundColor(Theme.cardInactive)
            }

            GeometryReader { geo in
                let h = Double(geo.size.height)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        let frac = Double(day.count) / Double(peak)
                        // A staggered start reads as the data filling in rather
                        // than one block scaling up.
                        let stagger = min(1, Double(progress) * 1.6 - Double(index) * 0.05)
                        let grown = max(0, min(1, stagger))
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(day.count > 0 ? Theme.primary : Theme.cardBlue)
                                .frame(height: day.count > 0
                                       ? max(3, safeLength(h * frac * grown, max: h))
                                       : 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 62)

            HStack {
                Text(dayLabel(days.first?.date))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cardInactive)
                Spacer()
                Text("today")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.cardInactive)
            }
        }
        .chartReveal($progress, duration: 1.1, delay: 0.35)
    }

    private func dayLabel(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}

// MARK: - Data shaping
//
// Kept next to the charts so each one has a single, named source.

extension ElementStore {
    var statusSlices: [StatusRingChart.Slice] {
        // Fixed order — the ring must not re-colour or re-order as counts change.
        [ElementStatus.pass, .attention, .fail, .inProgress].map { status in
            StatusRingChart.Slice(status: status,
                                  count: elements.filter { $0.status == status }.count)
        }
    }

    /// Worst offenders first: the elements furthest over their own target.
    func uTargetRows(limit: Int = 6) -> [UTargetChart.Row] {
        elements
            .filter { !$0.layers.isEmpty && $0.targetU > 0 }
            .map { element in
                UTargetChart.Row(id: element.id,
                                 name: element.name.isEmpty ? "Untitled" : element.name,
                                 uValue: ThermalEngine.uValue(of: element),
                                 target: element.targetU,
                                 status: element.status)
            }
            .sorted { ($0.uValue - $0.target) > ($1.uValue - $1.target) }
            .prefix(limit)
            .map { $0 }
    }

    /// One bucket per day for the last `days` days, oldest first.
    func activityByDay(days: Int = 14) -> [ActivityChart.Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var buckets: [Date: Int] = [:]
        for entry in history {
            let day = calendar.startOfDay(for: entry.date)
            buckets[day, default: 0] += 1
        }
        return (0..<days).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return ActivityChart.Day(date: day, count: buckets[day] ?? 0)
        }
    }
}
