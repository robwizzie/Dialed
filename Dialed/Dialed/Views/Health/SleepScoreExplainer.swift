//
//  SleepScoreExplainer.swift
//  Dialed
//
//  "How your score works": Dialed's sleep score for a night broken into
//  its four parts, next to Google's (Fitbit / Pixel Watch) score for the
//  same night when the watch sent one, and why the two can disagree.
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
                    googleCard
                    differences
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

    // MARK: - Side by side

    private var scores: some View {
        HStack(spacing: 12) {
            scoreTile("Dialed", parts.total, tint: Neka.lavenderText, fill: Neka.lavenderSoft)
            if let google = night.vendorScore {
                scoreTile("Google", google, tint: Neka.skyText, fill: Neka.skySoft)
            } else {
                VStack(spacing: 4) {
                    Text("Google")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Neka.inkTertiary)
                    Text("—")
                        .font(Neka.display(36, weight: .bold))
                        .foregroundColor(Neka.inkTertiary)
                    Text("No watch score this night")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Neka.track))
            }
        }
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

    // MARK: - Google

    private var googleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HealthCardHeader(title: "Google's score", trailing: "Fitbit / Pixel Watch")
            googleRow("Time asleep", "up to 50", "Time asleep against your sleep goal, minus time awake and restless.")
            googleRow("Deep & REM", "up to 25", "How much of the night was deep and REM sleep.")
            googleRow("Restoration", "up to 25", "How calm the night was: movement, plus your sleeping heart rate compared with your daytime resting rate (lower is better).")
            Text("Google calls 90–100 excellent, 80–89 good, 60–79 fair and under 60 poor. Most people land in the 70s and low 80s.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .nekaCard()
    }

    private func googleRow(_ title: String, _ points: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(points)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Neka.skyText)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Why they differ

    private var differences: some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthCardHeader(title: "Why they differ")
            bullet("Dialed rewards sleeping efficiently: lying awake in bed or waking up a lot costs points directly.")
            bullet("Google's restoration part uses your sleeping heart rate, which Dialed doesn't score, so a night with a calm heart rate can score higher there.")
            bullet("Google weighs deep + REM a little more (25 vs 20 points) and judges duration against your own sleep goal; Dialed uses 7.5 hours for everyone.")
            bullet("Dialed computes its score the same way for any watch or Apple Health, so nights stay comparable if you switch devices.")
            Text("Dialed's score is the one used across the app: Home, quests, badges and patterns.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .nekaCard()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Neka.lavender).frame(width: 5, height: 5).padding(.top, 6)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
