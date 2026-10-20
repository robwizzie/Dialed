//
//  AvatarEvolutionViews.swift
//  Dialed
//
//  The avatar's fitness stage, shown three ways: a small "Lv 3 · Building"
//  badge on the hero, a stage card in the avatar sheet (progress to the
//  next stage, streak glow), and a before/after "leveled up" moment when
//  you reach a new stage. All of it works without Image Playground too.
//

import SwiftUI

/// Gradient for a stage: cool at the start, warm gold at the top.
enum AvatarStageStyle {
    static func colors(_ level: Int) -> [Color] {
        switch level {
        case 1:  return [Neka.sky, Neka.blue]
        case 2:  return [Neka.green, Color(hex: "9BE2AE")]
        case 3:  return [Neka.green, Neka.sky]
        case 4:  return [Neka.lavender, Neka.blue]
        case 5:  return [Neka.orange, Neka.rose]
        default: return [Neka.amber, Neka.orange]
        }
    }
}

/// "Lv 3 · Building" with up to three glow sparks for streaks.
struct AvatarStageBadge: View {
    let reading: AvatarEvolution.Reading

    var body: some View {
        HStack(spacing: 5) {
            Text("Lv \(reading.stage.level)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient(colors: AvatarStageStyle.colors(reading.stage.level),
                                                          startPoint: .leading, endPoint: .trailing)))
            Text(reading.stage.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.ink)
            if reading.glow > 0 {
                HStack(spacing: 1) {
                    ForEach(0..<reading.glow, id: \.self) { _ in
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Neka.amber)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(Neka.surface.opacity(0.92)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Avatar level \(reading.stage.level), \(reading.stage.name)")
    }
}

/// Stage, what it means, and how far to the next one.
struct AvatarStageCard: View {
    let reading: AvatarEvolution.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: AvatarStageStyle.colors(reading.stage.level),
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("\(reading.stage.level)")
                        .font(Neka.display(22, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 48, height: 48)
                .shadow(color: AvatarStageStyle.colors(reading.stage.level)[0].opacity(0.25 + 0.15 * Double(reading.glow)),
                        radius: 4 + 4 * CGFloat(reading.glow))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVATAR LEVEL · \(reading.stage.name.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(Neka.inkTertiary)
                    Text(reading.stage.blurb)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Neka.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let next = reading.next {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Neka.track)
                            Capsule()
                                .fill(LinearGradient(colors: AvatarStageStyle.colors(next.level),
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * reading.toNext))
                        }
                    }
                    .frame(height: 8)
                    Text(nextText(next))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            } else {
                Text("Top level. Hold it and enjoy it.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.greenText)
            }
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
                    Image(systemName: i <= reading.glow ? "sparkle" : "circle.dotted")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(i <= reading.glow ? Neka.amber : Neka.inkTertiary)
                }
                Text(glowText)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func nextText(_ next: AvatarEvolution.Stage) -> String {
        if let lbs = reading.lbsToNext, lbs > 0.05 {
            return "\(String(format: "%.1f", lbs)) lb of trend weight to Lv \(next.level) · \(next.name)"
        }
        return "Lv \(next.level) · \(next.name) is right there"
    }

    private var glowText: String {
        switch reading.glow {
        case 3:  return "Max glow: 14+ day streak"
        case 2:  return "Glowing: 7+ day streak. 14 for max"
        case 1:  return "A spark: 3+ day streak. 7 to glow"
        default: return "Keep a 3-day streak to start glowing"
        }
    }
}

/// "Your avatar leveled up" — before and after, then dismiss.
struct AvatarLevelUpCard: View {
    let levelUp: AvatarStudio.LevelUp
    /// The new look, once it's drawn (nil while it's being made).
    let after: UIImage?
    let isDrawing: Bool
    var onDismiss: () -> Void

    @State private var shown = false

    var body: some View {
        let to = AvatarEvolution.stage(level: levelUp.to)
        VStack(spacing: 14) {
            Text("🎉 Your avatar leveled up")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Neka.ink)
            HStack(spacing: 12) {
                look(levelUp.before, label: "Lv \(levelUp.from)")
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
                look(after, label: "Lv \(levelUp.to)", loading: isDrawing && after == nil)
                    .scaleEffect(shown ? 1 : 0.85)
            }
            Text("\(to.name): \(to.blurb)")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Nice", action: onDismiss)
                .buttonStyle(.nekaPrimary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: AvatarStageStyle.colors(levelUp.to).map { $0.opacity(0.18) },
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .stroke(LinearGradient(colors: AvatarStageStyle.colors(levelUp.to), startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2)
        )
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) { shown = true }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
    }

    private func look(_ image: UIImage?, label: String, loading: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Neka.track)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if loading {
                    ProgressView()
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 34))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Neka.inkSecondary)
        }
    }
}
