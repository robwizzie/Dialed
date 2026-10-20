//
//  SleepScoreExplainer.swift
//  Dialed
//
//  "How your score works": Dialed's sleep score for a night broken into
//  its four parts, with what each one rewards.
//

import SwiftUI

struct SleepScoreExplainer: View {
    let night: HealthInsights.Night
    @Environment(\.dismiss) private var dismiss

    private var parts: HealthInsights.ScoreBreakdown { HealthInsights.scoreBreakdown(night) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scores
                    dialedCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .nekaPageBackground()
            .navigationTitle("How your score works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Score

    private var scores: some View {
        scoreTile("Dialed", parts.total, tint: Neka.lavenderText, fill: Neka.lavenderSoft)
    }

    private func scoreTile(_ name: String, _ score: Int, tint: Color, fill: Color) -> some View {
        VStack(spacing: 4) {
            Text(name.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(tint)
            Text("\(score)")
                .font(Neka.display(40, weight: .bold))
                .foregroundColor(Neka.ink)
            Text(HealthInsights.label(for: score))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
    }

    // MARK: - Dialed

    private var dialedCard: some View {
        let asleep = "\(night.asleepMinutes / 60)h \(night.asleepMinutes % 60)m"
        let stage: String = {
            guard let d = night.deepMinutes, let r = night.remMinutes, night.asleepMinutes > 0 else { return "No stage data, so 12 points by default" }
            return "\(Int(Double(d + r) / Double(night.asleepMinutes) * 100))% deep + REM · full marks at 40%"
        }()
        return VStack(alignment: .leading, spacing: 14) {
            HealthCardHeader(title: "Dialed's score", trailing: "\(parts.total) / 100")
            bar("Duration", parts.duration, of: 50, note: "\(asleep) asleep · full marks at 7.5 h")
            bar("Time asleep in bed", parts.efficiency, of: 20,
                note: "\(Int(night.efficiency * 100))% of your time in bed · 75% scores 0, 95% scores full")
            bar("Deep + REM", parts.restorative, of: 20, note: stage)
            bar("Wake-ups", parts.wakeUps, of: 10,
                note: night.awakenings.map { "\($0) wake-up\($0 == 1 ? "" : "s") · −1.5 each" } ?? "Unknown, so 7 by default")
        }
        .padding(16)
        .nekaCard()
    }

    private func bar(_ title: String, _ points: Double, of max: Double, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Text("\(Int(points.rounded())) / \(Int(max))")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(Neka.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track)
                    Capsule().fill(LinearGradient(colors: [Neka.lavender, Neka.sky], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * Swift.max(0.02, Swift.min(1, points / max)))
                }
            }
            .frame(height: 8)
            Text(note)
                .font(.system(size: 11))
                .foregroundColor(Neka.inkSecondary)
        }
    }

}
