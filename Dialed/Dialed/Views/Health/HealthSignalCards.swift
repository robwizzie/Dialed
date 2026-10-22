//
//  HealthSignalCards.swift
//  Dialed
//
//  Stress and Illness Watch: the Body page's full cards, and the compact
//  Body Check card Home shows. Both read your overnight vitals against
//  your own baseline (see HealthInsights.stress / illnessCheck).
//

import SwiftUI

extension HealthInsights.Stress {
    var tint: Color {
        switch score {
        case ..<30:   return Neka.greenText
        case 30..<55: return Neka.skyText
        case 55..<75: return Neka.orangeText
        default:      return Neka.roseText
        }
    }

    var ringColors: [Color] {
        switch score {
        case ..<30:   return [Neka.green, Color(hex: "9BE2AE")]
        case 30..<55: return [Neka.sky, Neka.blue]
        case 55..<75: return [Neka.amber, Neka.orange]
        default:      return [Neka.orange, Neka.rose]
        }
    }

    var summary: String {
        switch score {
        case ..<30:   return "Your body is well recovered and relaxed."
        case 30..<55: return "Right around your normal."
        case 55..<75: return "Your body is under more load than usual."
        default:      return "High physiological stress — keep today light."
        }
    }
}

extension HealthInsights.IllnessCheck.Level {
    var icon: String {
        switch self {
        case .clear: return "checkmark.shield.fill"
        case .watch: return "exclamationmark.triangle.fill"
        case .alert: return "cross.case.fill"
        }
    }

    var tint: Color {
        switch self {
        case .clear: return Neka.greenText
        case .watch: return Neka.orangeText
        case .alert: return Neka.roseText
        }
    }

    var soft: Color {
        switch self {
        case .clear: return Neka.greenSoft
        case .watch: return Neka.orangeSoft
        case .alert: return Neka.roseSoft
        }
    }
}

// MARK: - Stress

struct HealthStressCard: View {
    let stress: HealthInsights.Stress?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HealthCardHeader(title: "Stress", trailing: "vs your 2-week baseline")
            if let stress {
                HStack(spacing: 16) {
                    ZStack {
                        NekaMiniRing(progress: Double(stress.score) / 100, colors: stress.ringColors, lineWidth: 8)
                        Text("\(stress.score)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .contentTransition(.numericText())
                    }
                    .frame(width: 78, height: 78)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stress.label)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(stress.tint)
                        Text(stress.summary)
                            .font(.system(size: 13))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 10) {
                    ForEach(stress.contributors) { c in
                        contributorRow(c)
                    }
                }
                Text("0 = fully relaxed · ~40 = your normal · 100 = maxed out")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            } else {
                Text("Needs HRV or resting heart rate plus a few days of history. Wear your watch overnight and it fills in.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    /// Name, a bar centered on "your normal", and the reading.
    private func contributorRow(_ c: HealthInsights.Stress.Contributor) -> some View {
        let color: Color = c.load > 0.6 ? Neka.orange : (c.load < 0.4 ? Neka.green : Neka.sky)
        return HStack(spacing: 10) {
            Text(c.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.ink)
                .frame(width: 74, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track)
                    Capsule().fill(color)
                        .frame(width: max(6, w * CGFloat(c.load)))
                    // Tick at your normal.
                    Rectangle()
                        .fill(Neka.ink.opacity(0.35))
                        .frame(width: 1.5, height: 12)
                        .offset(x: w / 2 - 0.75)
                }
            }
            .frame(height: 8)
            Text(c.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 128, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.name): \(c.detail)")
    }
}

// MARK: - Illness watch

struct HealthIllnessCard: View {
    let check: HealthInsights.IllnessCheck?
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HealthCardHeader(title: "Illness Watch", trailing: "last night vs your usual")
            if let check {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.level.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(check.level.tint)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(check.level.soft))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.headline)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(check.advice)
                            .font(.system(size: 13))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(check.signals) { signal in
                        signalRow(signal)
                        if signal.id != check.signals.last?.id { Divider().overlay(Neka.hairline) }
                    }
                }
                Text("Not a diagnosis — a heads-up when several vitals drift together, often a day before you feel it.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(isToday
                     ? "Waiting on last night's vitals. Once your watch syncs resting HR, HRV and breathing (and a few nights of baseline), this checks them every morning."
                     : "Not enough overnight vitals for this day.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .nekaCard(wash: check.map { $0.level == .clear ? .plain : .rose } ?? .plain)
    }

    private func signalRow(_ s: HealthInsights.IllnessCheck.Signal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(s.flagged ? Neka.orangeText : Neka.inkSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(s.flagged ? Neka.orangeSoft : Neka.track))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.ink)
                Text(s.change.isEmpty ? s.usual : "\(s.usual) · \(s.change)")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            }
            Spacer(minLength: 6)
            Text(s.value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            NekaPill(text: s.flagged ? "Off" : "Normal",
                     tint: s.flagged ? Neka.orangeText : Neka.greenText,
                     fill: s.flagged ? Neka.orangeSoft : Neka.greenSoft)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Home

/// Home's one-glance version: stress score and the illness verdict side by
/// side. Taps through to the Body page.
struct HomeBodyCheckCard: View {
    let stress: HealthInsights.Stress?
    let illness: HealthInsights.IllnessCheck?
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        NekaMiniRing(progress: Double(stress?.score ?? 0) / 100,
                                     colors: stress?.ringColors ?? [Neka.muted, Neka.muted], lineWidth: 5)
                        Text(stress.map { "\($0.score)" } ?? "–")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stress")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                        Text(stress?.label ?? "No data")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(stress?.tint ?? Neka.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(Neka.hairline).frame(width: 1, height: 40)
                    .padding(.horizontal, 12)

                HStack(spacing: 10) {
                    let level = illness?.level
                    Image(systemName: level?.icon ?? "shield")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(level?.tint ?? Neka.inkSecondary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(level?.soft ?? Neka.track))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Illness Watch")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                        Text(shortVerdict)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(level?.tint ?? Neka.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(16)
            .nekaCard(wash: illness.map { $0.level == .clear ? .plain : .rose } ?? .plain)
        }
        .buttonStyle(.dialedScale)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Body in Health")
    }

    private var shortVerdict: String {
        switch illness?.level {
        case .clear?: return "All clear"
        case .watch?: return "Take it easy"
        case .alert?: return "Possible illness"
        case nil:     return "Learning"
        }
    }
}
