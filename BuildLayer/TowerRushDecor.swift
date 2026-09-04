//
//  TowerRushDecor.swift
//  BuildLayer
//
//  Decorative construction art. These views deliberately contain no state or
//  actions: they add the game-like Tower Rush atmosphere without touching the
//  calculator's data or navigation logic.
//

import SwiftUI

enum TowerAsset: String, CaseIterable {
    case crane = "tower-crane"
    case hardhat = "hardhat"
    case beam = "steel-beam"
    case concrete = "concrete-block"
    case blueprint = "blueprint"
    case hook = "crane-hook"
    case beacon = "beacon"
    case cone = "safety-cone"
    case bricks = "brick-pallet"
    case bolt = "bolt"
    case gloves = "work-gloves"
    case level = "spirit-level"
    case insulation = "insulation-roll"
    case mixer = "mixer"
    case survey = "survey-marker"
    case tower = "finished-tower"

    static func accent(for type: ElementType) -> TowerAsset {
        switch type {
        case .wall: return .bricks
        case .roof: return .crane
        case .floor: return .concrete
        }
    }
}

struct TowerRushOnboardingBackground: View {
    let page: Int

    var body: some View {
        ZStack {
            Image("tower-onboarding-\(page + 1)")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            LinearGradient(
                colors: [Theme.bgDeep.opacity(0.28), Theme.bgDeep.opacity(0.66), Theme.bgDeep.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            LinearGradient(
                colors: [Theme.bgDeep.opacity(0.18), .clear, Theme.bgDeep.opacity(0.22)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
        }
    }
}

struct TowerRushAsset: View {
    let asset: TowerAsset
    var size: CGFloat = 46
    var opacity: Double = 1

    var body: some View {
        Image(asset.rawValue)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .opacity(opacity)
            .accessibilityHidden(true)
    }
}

struct TowerRushProjectBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BUILD MODE")
                    .font(.bl(11, .heavy))
                    .foregroundColor(Theme.secondaryHi)
                    .tracking(1.1)
                Text("Every layer moves the tower forward.")
                    .font(.bl(17, .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            ZStack(alignment: .bottomTrailing) {
                TowerRushAsset(asset: .tower, size: 77)
                TowerRushAsset(asset: .crane, size: 38)
                    .offset(x: -42, y: -17)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Color(hex: "102C50"), Color(hex: "183A5E"), Color(hex: "0F203D")],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.secondary.opacity(0.55), lineWidth: 1))
        .shadow(color: Theme.warmGlow, radius: 12, y: 6)
    }
}

struct TowerRushToolStrip: View {
    var body: some View {
        HStack(spacing: 0) {
            tool(.blueprint, "Plan")
            tool(.beam, "Frame")
            tool(.insulation, "Insulate")
            tool(.beacon, "Check")
        }
        .padding(7)
        .background(Theme.bgSoft.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1))
    }

    private func tool(_ asset: TowerAsset, _ title: String) -> some View {
        VStack(spacing: 2) {
            TowerRushAsset(asset: asset, size: 30)
            Text(title).font(.bl(10, .bold)).foregroundColor(Theme.subtitle)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TowerRushCornerDecor: View {
    var body: some View {
        VStack {
            HStack {
                TowerRushAsset(asset: .hook, size: 39, opacity: 0.30)
                Spacer()
                TowerRushAsset(asset: .beacon, size: 30, opacity: 0.26)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .allowsHitTesting(false)
    }
}
