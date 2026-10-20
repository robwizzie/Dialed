//
//  PRCelebrationView.swift
//  Dialed
//
//  The moment you save a workout with a personal record: a burst of
//  stars and flames from the middle of the screen and a trophy card
//  ("New PR! Bench press 155 × 8 · est. max 196"). Plain SwiftUI shapes
//  and SF Symbols, no particle emitter. Tap anywhere to move on.
//

import SwiftUI

struct PRCelebrationView: View {
    let prs: [StrengthMilestones.PR]
    var onDone: () -> Void

    @State private var burst = false
    @State private var shown = false

    /// Fixed pieces (angle, distance, symbol, tint, size) so the burst looks
    /// the same every time and costs nothing to compute.
    private static let pieces: [(Double, Double, String, Color, CGFloat)] = (0..<22).map { i in
        let symbols = ["star.fill", "sparkle", "flame.fill", "bolt.fill"]
        let tints: [Color] = [Neka.amber, Neka.orange, Neka.green, Neka.sky, Neka.rose]
        let angle = Double(i) / 22 * 2 * .pi + (i.isMultiple(of: 2) ? 0.12 : -0.08)
        let distance = 130 + Double((i * 37) % 90)
        return (angle, distance, symbols[i % symbols.count], tints[i % tints.count], CGFloat(14 + (i * 7) % 14))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.45 : 0)
                .ignoresSafeArea()

            ForEach(0..<Self.pieces.count, id: \.self) { i in
                let p = Self.pieces[i]
                Image(systemName: p.2)
                    .font(.system(size: p.4, weight: .bold))
                    .foregroundStyle(p.3)
                    .offset(x: burst ? cos(p.0) * p.1 : 0, y: burst ? sin(p.0) * p.1 - 40 : -40)
                    .scaleEffect(burst ? 1 : 0.2)
                    .opacity(burst ? 0 : 1)
                    .rotationEffect(.degrees(burst ? Double(i * 40) : 0))
            }

            VStack(spacing: 10) {
                Text("🏆")
                    .font(.system(size: 54))
                Text(prs.count == 1 ? "New PR!" : "\(prs.count) new PRs!")
                    .font(Neka.display(28, weight: .bold))
                    .foregroundColor(Neka.ink)
                ForEach(prs.indices, id: \.self) { i in
                    Text(headline(prs[i]))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous).fill(Neka.surface))
            .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { shown = true }
            withAnimation(.easeOut(duration: 1.4)) { burst = true }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "Bench press 155 × 8 · est. max 196"
    private func headline(_ pr: StrengthMilestones.PR) -> String {
        "\(pr.exercise) \(formatPounds(pr.weight)) × \(pr.reps) · est. max \(formatPounds(pr.e1RM.rounded()))"
    }
}
