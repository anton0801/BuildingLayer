//
//  LaunchView.swift
//  BuildLayer
//
//  Thematic splash: a wall cross-section assembles layer by layer, the orange
//  heat arrow weakens with every layer, and the R-scale fills. Three live layers
//  (background glow shift, midground build-up loop, foreground logo entrance),
//  a single coordinator timer, and a designed scale-up + fade exit.
//

import SwiftUI

struct LaunchView: View {
    let onFinish: () -> Void

    // Animation state flags
    @State private var isVisible = true
    @State private var bgShift = false
    @State private var glowPulse = false
    @State private var visibleLayers = 0
    @State private var rFraction: CGFloat = 0.0
    @State private var heatStrength: CGFloat = 1.0
    @State private var logoIn = false
    @State private var exiting = false

    @State private var timer: Timer?
    @State private var elapsed: Double = 0

    // The demo build-up (outside → inside)
    private let demoLayers: [(color: Color, w: CGFloat, insulation: Bool)] = [
        (Theme.layer, 0.10, false),       // render
        (Theme.layer.opacity(0.85), 0.16, false), // brick
        (Theme.insulation, 0.32, true),   // insulation
        (Theme.cold.opacity(0.5), 0.10, false),   // cavity
        (Theme.layer.opacity(0.7), 0.12, false)   // plasterboard
    ]

    var body: some View {
        ZStack {
            // LAYER 1 — shifting background gradient + glow
            Theme.bgGradient.ignoresSafeArea()
            RadialGradient(colors: [Theme.warmGlow, .clear],
                           center: bgShift ? .topTrailing : .bottomLeading,
                           startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
                .opacity(glowPulse ? 0.9 : 0.4)

            VStack(spacing: 34) {
                Spacer()

                // LAYER 2 — midground build-up + heat arrow + R scale
                VStack(spacing: 16) {
                    ZStack(alignment: .trailing) {
                        crossSection
                        heatArrow
                            .offset(x: 38)
                    }
                    .frame(height: 150)

                    rScale
                }
                .frame(maxWidth: 300)
                .scaleEffect(exiting ? 1.5 : 1.0)
                .opacity(exiting ? 0 : 1)

                // LAYER 3 — foreground logo + title entrance
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.primaryGradient)
                            .frame(width: 78, height: 78)
                            .shadow(color: Theme.warmGlow, radius: 20, y: 8)
                        Image(systemName: Icon.layers)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Theme.buttonText)
                    }
                    .scaleEffect(logoIn ? 1 : 0.4)
                    .opacity(logoIn ? 1 : 0)

                    Text("Build Layer")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(logoIn ? 1 : 0)
                        .offset(y: logoIn ? 0 : 14)

                    Text("Stack the layers, stop the heat loss.")
                        .font(.bl(14, .semibold))
                        .foregroundColor(Theme.subtitle)
                        .opacity(logoIn ? 1 : 0)
                }
                .scaleEffect(exiting ? 1.3 : 1.0)
                .opacity(exiting ? 0 : 1)

                Spacer()
            }
            .padding()
        }
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    // MARK: Subviews

    private var crossSection: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<demoLayers.count, id: \.self) { i in
                    let layer = demoLayers[i]
                    Rectangle()
                        .fill(layer.color)
                        .frame(width: geo.size.width * layer.w)
                        .overlay(layer.insulation ? Rectangle().stroke(Theme.primaryHi, lineWidth: 2) : nil)
                        .opacity(i < visibleLayers ? 1 : 0)
                        .scaleEffect(y: i < visibleLayers ? 1 : 0.2, anchor: .bottom)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: visibleLayers)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private var heatArrow: some View {
        VStack(spacing: 4) {
            Image(systemName: Icon.heat)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.primary)
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(Theme.primaryHi)
        }
        .opacity(Double(heatStrength))
        .scaleEffect(0.7 + heatStrength * 0.5)
        .animation(.easeInOut(duration: 0.5), value: heatStrength)
    }

    private var rScale: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("R").font(.bl(12, .heavy)).foregroundColor(Theme.subtitle)
                Spacer()
                Text("building…").font(.bl(11, .semibold)).foregroundColor(Theme.titleDim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.bgDeep.opacity(0.7))
                    Capsule().fill(Theme.heatGradient)
                        .frame(width: geo.size.width * rFraction)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: rFraction)
                }
            }
            .frame(height: 12)
        }
    }

    // MARK: Coordinator

    private func start() {
        isVisible = true
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { bgShift = true }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glowPulse = true }

        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard isVisible else { return }
            elapsed += 0.1

            // Phase 2 — add a layer roughly every 0.32s, weaken heat, grow R.
            let target = min(demoLayers.count, Int((elapsed - 0.3) / 0.32))
            if target > visibleLayers && target <= demoLayers.count {
                visibleLayers = target
                rFraction = CGFloat(visibleLayers) / CGFloat(demoLayers.count) * 0.92
                heatStrength = max(0.18, 1.0 - CGFloat(visibleLayers) * 0.18)
            }

            // Phase 3 — logo entrance.
            if elapsed >= 1.4 && !logoIn {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { logoIn = true }
            }

            // Phase 4 — designed exit then hand off.
            if elapsed >= 2.6 && !exiting {
                withAnimation(.easeIn(duration: 0.45)) { exiting = true }
                timer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if isVisible { onFinish() }
                }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func stop() {
        isVisible = false
        timer?.invalidate()
        timer = nil
        // Reset so no looping animation leaks into the main app.
        bgShift = false; glowPulse = false; visibleLayers = 0
        rFraction = 0; heatStrength = 1; logoIn = false; exiting = false; elapsed = 0
    }
}
