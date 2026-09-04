//
//  OnboardingView.swift
//  BuildLayer
//
//  5-screen "layer-stack" onboarding. Each screen has a distinct interactive
//  gesture: tap (O1), horizontal drag (O2), drag-to-stack (O3), vertical drag
//  thermometer (O4), tap-to-pick (O5). Choices configure the app and seed the
//  first element. State saved to @AppStorage("hasCompletedOnboarding").
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: ElementStore
    let onDone: () -> Void

    @State private var page = 0

    // Shared selections
    @State private var selectedType: ElementType = .wall
    @State private var targetU: Double = 0.30
    @State private var basis: StandardBasis = .comfort
    @State private var builtLayers: Int = 0
    @State private var insideTemp: Double = 20
    @State private var outsideTemp: Double = -5
    @State private var climate: String = "Cold"
    @State private var startMode: String = "Use Sample"
    @State private var elementTitle: String = "South Wall"

    private let lastPage = 4

    var body: some View {
        ZStack {
            TowerRushOnboardingBackground(page: page)

            VStack(spacing: 0) {
                // Top bar: page dots + Skip
                HStack {
                    HStack(spacing: 7) {
                        ForEach(0...lastPage, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? Theme.primary : Theme.titleDim.opacity(0.4))
                                .frame(width: i == page ? 22 : 8, height: 8)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: page)
                        }
                    }
                    Spacer()
                    Button("Skip") { finish(createSample: false, createEmpty: true) }
                        .font(.bl(15, .bold)).foregroundColor(Theme.subtitle)
                }
                .padding(.horizontal, 22).padding(.top, 14)

                // Pages
                TabView(selection: $page) {
                    screen1.tag(0)
                    screen2.tag(1)
                    screen3.tag(2)
                    screen4.tag(3)
                    screen5.tag(4)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                // Bottom controls
                HStack(spacing: 14) {
                    if page > 0 {
                        Button {
                            withAnimation { page -= 1 }
                        } label: {
                            Image(systemName: Icon.chevronL).font(.system(size: 17, weight: .bold))
                                .foregroundColor(Theme.subtitle)
                                .frame(width: 52, height: 52)
                                .background(Theme.bgSoft).clipShape(Circle())
                                .overlay(Circle().stroke(Theme.divider, lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    PrimaryButton(title: primaryTitle, icon: page == lastPage ? Icon.add : Icon.arrowR) {
                        appState.haptic()
                        if page == lastPage {
                            finish(createSample: startMode == "Use Sample",
                                   createEmpty: startMode == "Start Empty")
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.bottom, 18)
            }
        }
        .onDisappear { /* gesture-driven; nothing looping to reset */ }
    }

    private var primaryTitle: String {
        switch page {
        case 0: return "Enter \(selectedType.rawValue)"
        case 1: return "Set Target U"
        case 2: return "Build Stack"
        case 3: return "Set Climate"
        default: return "Create Element Record"
        }
    }

    // MARK: - Finish

    @State private var isFinishing = false

    private func finish(createSample: Bool, createEmpty: Bool) {
        // Double-tapping the final button used to create two elements.
        guard !isFinishing else { return }
        isFinishing = true

        appState.defaultElementType = selectedType.rawValue
        appState.defaultTargetU = max(0.05, targetU)
        appState.climatePreset = climate

        if createSample {
            store.add(ThermalElement.sample(type: selectedType, targetU: targetU,
                                            inside: insideTemp, outside: outsideTemp,
                                            title: elementTitle.isEmpty ? "Sample Wall" : elementTitle))
        } else if !createEmpty {
            var e = ThermalElement.newDefault(type: selectedType)
            e.name = elementTitle.isEmpty ? "New \(selectedType.rawValue)" : elementTitle
            e.targetU = targetU
            e.insideTemp = insideTemp
            e.outsideTemp = outsideTemp
            store.add(e)
        }
        appState.hasCompletedOnboarding = true
        onDone()
    }

    // MARK: - O1  R Layer Entry  (tap-to-trigger)

    @State private var o1Rotate = false
    @State private var o1Fly = false

    private var screen1: some View {
        OnboardingScaffold(
            chip: "01 · R Layer Entry",
            title: "Turn a wall buildup into a clear thermal check.",
            subtitle: "Pick the element you want to assess. No sign-up — everything stays on your device."
        ) {
            VStack(spacing: 22) {
                // Rotating cross-section that flips per element
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.bgDeep.opacity(0.4))
                    sampleStrip
                        .rotation3DEffect(.degrees(o1Rotate ? 8 : -8),
                                          axis: selectedType == .wall ? (x: 0, y: 1, z: 0) : (x: 1, y: 0, z: 0))
                        .padding(20)
                    // The particles are always in the tree; `o1Fly` animates
                    // them outward. Previously the same flag both inserted the
                    // views and set their end state, so they were created
                    // already-finished and nothing was ever visible.
                    ForEach(0..<8, id: \.self) { i in
                        Circle().fill(Theme.primaryHi)
                            .frame(width: 7, height: 7)
                            .offset(x: cos(Double(i) / 8 * 2 * .pi) * (o1Fly ? 70 : 0),
                                    y: sin(Double(i) / 8 * 2 * .pi) * (o1Fly ? 70 : 0))
                            .opacity(o1Fly ? 0 : 0.9)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 150)

                HStack(spacing: 12) {
                    ForEach(ElementType.allCases) { type in
                        elementCard(type)
                    }
                }
            }
        }
    }

    private func elementCard(_ type: ElementType) -> some View {
        let selected = selectedType == type
        return Button {
            appState.haptic()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                selectedType = type
                o1Rotate.toggle()
            }
            // Snap back to the centre, then animate outward, so each tap replays.
            o1Fly = false
            withAnimation(.easeOut(duration: 0.55)) { o1Fly = true }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.icon).font(.system(size: 26, weight: .bold))
                    .foregroundColor(selected ? Theme.buttonText : Theme.layer)
                Text(type.rawValue).font(.bl(14, .bold))
                    .foregroundColor(selected ? Theme.buttonText : Theme.cardText)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(ZStack { if selected { Theme.primaryGradient } else { Theme.card } })
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? Color.clear : Theme.cardBorder, lineWidth: 1))
            .shadow(color: selected ? Theme.warmGlow : .clear, radius: 12, y: 5)
        }
        .buttonStyle(PressableStyle())
    }

    private var sampleStrip: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle().fill(i == 2 ? Theme.insulation : Theme.layer.opacity(1 - Double(i)*0.12))
                    .overlay(i == 2 ? Rectangle().stroke(Theme.primaryHi, lineWidth: 2) : nil)
            }
        }
        .frame(height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - O2  Target U-Value  (horizontal drag)

    private var screen2: some View {
        OnboardingScaffold(
            chip: "02 · Target U-Value",
            title: "Set the target U-value to aim for.",
            subtitle: "Drag the slider — stricter targets mean a thicker insulation layer ahead."
        ) {
            VStack(spacing: 22) {
                ChipSelector(options: StandardBasis.allCases, selection: $basis,
                             label: { $0.rawValue }, onCard: false)
                .onChange(of: basis) { newVal in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        targetU = newVal.targetU(for: selectedType)
                    }
                }
                // A roof target picked on screen 2 stayed put if the user went
                // back and switched to a wall on screen 1.
                .onChange(of: selectedType) { type in
                    withAnimation { targetU = basis.targetU(for: type) }
                }

                BLCard {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Target U").font(.bl(13, .bold)).foregroundColor(Theme.cardSubtext)
                            Spacer()
                            Text("\(appState.fmt.uText(targetU)) \(appState.fmt.uSuffix)")
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .font(.bl(20, .heavy)).foregroundColor(Theme.primary)
                        }
                        uDragTrack
                        // Preview: stricter target → thicker orange band
                        HStack(spacing: 3) {
                            Rectangle().fill(Theme.layer).frame(width: 26)
                            Rectangle().fill(Theme.insulation)
                                .frame(width: safeLength(40 + (0.6 - targetU) * 260, max: 220))
                                .overlay(Rectangle().stroke(Theme.primaryHi, lineWidth: 2))
                            Rectangle().fill(Theme.layer.opacity(0.7)).frame(width: 22)
                        }
                        .frame(height: 54)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: targetU)
                    }
                }
            }
        }
    }

    private var uDragTrack: some View {
        GeometryReader { geo in
            let minU = 0.10, maxU = 0.60
            let frac = CGFloat((targetU - minU) / (maxU - minU))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cardBlue).frame(height: 10)
                Capsule().fill(Theme.heatGradient)
                    .frame(width: max(12, geo.size.width * frac), height: 10)
                Circle().fill(Theme.primary)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: Theme.warmGlow, radius: 6)
                    .offset(x: max(0, min(geo.size.width - 26, geo.size.width * frac - 13)))
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = max(0, min(1, v.location.x / geo.size.width))
                // Precedence bug: `minU + f*(maxU-minU) * 100` multiplied only
                // the span by 100, giving a 0.00–0.50 range — and letting the
                // user pick a target U of zero, which no build-up can ever meet.
                targetU = ((minU + Double(f) * (maxU - minU)) * 100).rounded() / 100
            })
        }
        .frame(height: 28)
    }

    // MARK: - O3  Build the Stack  (drag-to-stack)

    @State private var o3Drag: CGFloat = 0

    private var screen3: some View {
        OnboardingScaffold(
            chip: "03 · Build the Stack",
            title: "Drag layers and watch R build up.",
            subtitle: "Pull up on the wall to glue layers in. R rises, U falls with every band."
        ) {
            VStack(spacing: 20) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.bgDeep.opacity(0.4))
                    VStack(spacing: 3) {
                        ForEach(0..<builtLayers, id: \.self) { i in
                            Rectangle()
                                .fill(i == 2 ? Theme.insulation : Theme.layer.opacity(1 - Double(i)*0.1))
                                .frame(height: 24)
                                .overlay(i == 2 ? Rectangle().stroke(Theme.primaryHi, lineWidth: 2) : nil)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(10)
                    if builtLayers == 0 {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.draw.fill").font(.system(size: 26, weight: .bold))
                            Text("Drag up").font(.bl(13, .bold))
                        }.foregroundColor(Theme.titleDim)
                    }
                }
                .frame(height: 170)
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { v in
                    let count = min(5, max(0, Int(-v.translation.height / 28)))
                    if count != builtLayers {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { builtLayers = count }
                        appState.haptic()
                    }
                })

                BLCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("R-VALUE").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                            Text(String(format: "%.2f", 0.3 + Double(builtLayers) * 0.9))
                                .font(.bl(22, .heavy)).foregroundColor(Theme.cardText)
                        }
                        Spacer()
                        RScaleBar(currentR: 0.3 + Double(builtLayers) * 0.9, targetR: 4.0)
                            .frame(width: 120)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("U-VALUE").font(.bl(11, .bold)).foregroundColor(Theme.cardSubtext)
                            Text(String(format: "%.2f", 1.0 / (0.3 + Double(builtLayers) * 0.9)))
                                .font(.bl(22, .heavy)).foregroundColor(Theme.primary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - O4  Climate & ΔT  (vertical drag thermometer)

    private var screen4: some View {
        OnboardingScaffold(
            chip: "04 · Climate & ΔT",
            title: "Set climate and temperature difference.",
            subtitle: "Slide the thermometer for the outdoor design temp. Colder → stronger heat flow out."
        ) {
            VStack(spacing: 20) {
                ChipSelector(options: ["Mild", "Cold", "Severe"], selection: $climate,
                             label: { $0 }, onCard: false)
                .onChange(of: climate) { c in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        switch c {
                        case "Mild":   outsideTemp = 5
                        case "Severe": outsideTemp = -20
                        default:       outsideTemp = -5
                        }
                    }
                }

                HStack(spacing: 18) {
                    thermometerControl
                    BLCard {
                        VStack(alignment: .leading, spacing: 12) {
                            tempRow("Inside", insideTemp, Theme.primary)
                            tempRow("Outside", outsideTemp, Theme.cold)
                            Divider().background(Theme.cardBorder)
                            HStack {
                                Text("ΔT").font(.bl(13, .bold)).foregroundColor(Theme.cardSubtext)
                                Spacer()
                                Text("\(Int(insideTemp - outsideTemp))°C")
                                    .font(.bl(22, .heavy)).foregroundColor(Theme.cardText)
                            }
                            // Heat arrow strength reflects ΔT
                            HStack(spacing: 4) {
                                Image(systemName: Icon.heat).foregroundColor(Theme.primary)
                                ForEach(0..<max(1, safeCount((insideTemp - outsideTemp) / 8, cap: 5)), id: \.self) { _ in
                                    Image(systemName: "arrow.right").foregroundColor(Theme.primaryHi)
                                }
                            }.font(.system(size: 14, weight: .bold))
                        }
                    }
                }
                .frame(height: 230)
            }
        }
    }

    private func tempRow(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.bl(13, .semibold)).foregroundColor(Theme.cardSubtext)
            Spacer()
            Text("\(Int(value))°C").font(.bl(16, .bold)).foregroundColor(Theme.cardText)
        }
    }

    private var thermometerControl: some View {
        GeometryReader { geo in
            let minT = -25.0, maxT = 10.0
            let frac = CGFloat((outsideTemp - minT) / (maxT - minT))
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.cardBlue)
                Capsule().fill(Theme.coldGradient)
                    .frame(height: max(20, geo.size.height * frac))
                VStack {
                    Spacer()
                    Circle().fill(Theme.cold)
                        .frame(width: 30, height: 30)
                        .overlay(Image(systemName: Icon.thermo).font(.system(size: 13, weight: .bold)).foregroundColor(.white))
                        .offset(y: -geo.size.height * frac + 15)
                }
            }
            .frame(width: 54)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = max(0, min(1, 1 - v.location.y / geo.size.height))
                outsideTemp = (minT + Double(f) * (maxT - minT)).rounded()
            })
        }
    }

    // MARK: - O5  First Element Record  (tap-to-pick)

    private var screen5: some View {
        OnboardingScaffold(
            chip: "05 · First Element Record",
            title: "Create one element now or start empty.",
            subtitle: "Use Sample loads a wall with insulation, computed R/U and a condensation check."
        ) {
            VStack(spacing: 16) {
                BLCard {
                    BLField(label: "Element Title", placeholder: "e.g. South Wall", text: $elementTitle)
                }
                VStack(spacing: 12) {
                    startModeCard("Use Sample", "Loads a worked example", Icon.sparkles)
                    startModeCard("Create Now", "Start from your O1–O4 picks", Icon.add)
                    startModeCard("Start Empty", "Open a blank project list", Icon.doc)
                }
            }
        }
    }

    private func startModeCard(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        let selected = startMode == title
        return Button {
            appState.haptic()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { startMode = title }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .bold))
                    .foregroundColor(selected ? Theme.buttonText : Theme.primary)
                    .frame(width: 44, height: 44)
                    .background(ZStack { if selected { Theme.primaryGradient } else { Theme.cardBlue } })
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.bl(16, .bold)).foregroundColor(Theme.cardText)
                    Text(subtitle).font(.bl(12, .medium)).foregroundColor(Theme.cardSubtext)
                }
                Spacer()
                Image(systemName: selected ? Icon.check : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(selected ? Theme.pass : Theme.cardInactive)
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? Theme.primary : Theme.cardBorder, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Shared scaffold

struct OnboardingScaffold<Content: View>: View {
    let chip: String
    let title: String
    let subtitle: String
    let content: Content
    init(chip: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.chip = chip; self.title = title; self.subtitle = subtitle; self.content = content()
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(chip).font(.bl(12, .heavy)).foregroundColor(Theme.primary)
                    .padding(.vertical, 5).padding(.horizontal, 11)
                    .background(Theme.primary.opacity(0.14)).clipShape(Capsule())
                Text(title).font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.title).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.bl(14, .medium)).foregroundColor(Theme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
                content.padding(.top, 6)
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 24)
        }
    }
}

// MARK: - Sample element factory

extension ThermalElement {
    static func sample(type: ElementType, targetU: Double, inside: Double, outside: Double, title: String) -> ThermalElement {
        var e = ThermalElement(name: title, type: type, area: 14.5,
                               targetU: targetU, tolerance: 0.02,
                               insideTemp: inside, outsideTemp: outside, indoorRH: 55)
        e.layers = [
            Layer(materialName: "Cement render", lambda: 0.87, vaporResistance: 25, thicknessMM: 20, isInsulation: false, side: "Outside"),
            Layer(materialName: "Brickwork (outer)", lambda: 0.77, vaporResistance: 10, thicknessMM: 100, isInsulation: false, side: "Outside"),
            Layer(materialName: "Mineral wool (slab)", lambda: 0.035, vaporResistance: 1, thicknessMM: 120, isInsulation: true, side: "Core"),
            Layer(materialName: "Air cavity (25mm)", lambda: 0.16, vaporResistance: 1, thicknessMM: 25, isInsulation: false, side: "Core"),
            Layer(materialName: "Gypsum plasterboard", lambda: 0.21, vaporResistance: 8, thicknessMM: 12.5, isInsulation: false, side: "Inside")
        ]
        e.insulationName = "Mineral wool (slab)"
        e.hasVaporControl = true
        e.existingU = 1.6
        e.notes = "Worked sample — cavity wall with 120mm mineral wool."
        let r = ThermalEngine.result(for: e)
        e.status = r.passesTarget ? .pass : .attention
        return e
    }
}
