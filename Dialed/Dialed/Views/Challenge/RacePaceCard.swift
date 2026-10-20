//
//  RacePaceCard.swift
//  Dialed
//
//  "You need 1.6 lb/week to beat Dave by Nov 19 — you're on 1.8."
//  The pace you need, your pace by the scale trend and by your food log
//  side by side, where your friend is headed, and the daily calories that
//  get you there. On Home and the Challenge tab.
//

import SwiftUI

struct RacePaceCard: View {
    let report: RacePace.Report

    private var r: RacePace.Result { report.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("PACE TO BEAT \(report.friendName.uppercased())")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.inkTertiary)
                Spacer()
                Text("\(Int((r.weeksLeft * 7).rounded())) days left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.needed <= 0.05 ? "Hold steady" : "\(Self.rate(r.needed)) lb/week")
                        .font(Neka.display(28, weight: .bold))
                        .foregroundColor(Neka.ink)
                    Text(r.needed <= 0.05 ? "You're far enough ahead to win standing still" : "needed from today to finish ahead by \(report.end.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                statusChip
            }

            if r.status != .unknown {
                VStack(spacing: 8) {
                    bar("Needed", r.needed, tint: Neka.inkTertiary)
                    if let t = r.trendRate { bar("Scale trend", t, tint: color(for: t)) }
                    if let f = r.foodRate { bar("Food log", f, tint: color(for: f)) }
                }
            }

            Text(storyLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Pieces

    private var statusChip: some View {
        let (text, tint, fill): (String, Color, Color) = {
            switch r.status {
            case .ahead:   return ("Ahead", Neka.greenText, Neka.greenSoft)
            case .onTrack: return ("On track", Neka.greenText, Neka.greenSoft)
            case .behind:  return ("Behind", Neka.orangeText, Neka.orangeSoft)
            case .unknown: return ("Need data", Neka.inkSecondary, Neka.track)
            }
        }()
        return Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
    }

    private var scale: Double {
        max(0.5, [r.needed, r.trendRate ?? 0, r.foodRate ?? 0].max() ?? 1) * 1.1
    }

    private func bar(_ title: String, _ value: Double, tint: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .frame(width: 74, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * max(0.02, min(1, value / scale)))
                    // The line you have to clear.
                    Rectangle().fill(Neka.ink.opacity(0.5))
                        .frame(width: 2)
                        .offset(x: geo.size.width * min(1, r.needed / scale) - 1)
                }
            }
            .frame(height: 8)
            Text(value < 0 ? "+\(Self.rate(-value))" : Self.rate(value))
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Neka.ink)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func color(for value: Double) -> Color {
        value >= r.needed ? Neka.green : Neka.orange
    }

    private var storyLine: String {
        let friend = report.friendName
        guard r.status != .unknown else {
            return r.friendProjectedLoss == nil
                ? "Once \(friend) shares a couple of weigh-ins, Dialed projects where they'll finish."
                : "A week of weigh-ins (or logged food) and Dialed can tell you if you're on pace."
        }
        var parts: [String] = []
        if let f = r.friendProjectedLoss, let y = r.yourProjectedLoss {
            parts.append("\(friend) is on pace for −\(String(format: "%.1f", f)) lb; you're headed for −\(String(format: "%.1f", y)).")
        }
        if r.needed > 0.05 {
            parts.append("About \(Int(report.targetCalories).formatted()) calories a day (plus what you burn) gets you there.")
        }
        if r.needed > 2 { parts.append("That's an aggressive pace, so protect your sleep and protein.") }
        return parts.joined(separator: " ")
    }

    static func rate(_ v: Double) -> String { String(format: "%.1f", v) }
}
