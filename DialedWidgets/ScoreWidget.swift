//
//  ScoreWidget.swift
//  DialedWidgets
//
//  Today's day score as your avatar's mood — On fire, Locked in, Getting
//  there, Running on empty — with what each pillar contributed and the
//  one move that would lift it most.
//

import SwiftUI
import WidgetKit

struct DialedScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DialedScoreWidget", provider: DialedProvider()) { entry in
            ScoreWidgetView(entry: entry)
        }
        .configurationDisplayName("Day Score")
        .description("Your avatar's mood for today and the next move that lifts your score.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct ScoreWidgetView: View {
    let entry: DialedEntry
    @Environment(\.widgetFamily) private var family

    private var score: WidgetInsights.Score? { entry.insights?.score }
    private var accent: Color { score.map { Color(hexString: $0.accentHex) } ?? Theme.green }

    private var wash: Theme.Wash {
        switch score?.mood {
        case "onFire":         return .peach
        case "lockedIn":       return .mint
        case "gettingThere":   return .sky
        case "runningOnEmpty": return .lavender
        default:               return .paper
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(score?.value ?? 0), in: 0...100) {
                    Text(score?.emoji ?? "–")
                } currentValueLabel: {
                    Text(score.map { "\($0.value)" } ?? "–")
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
            case .systemMedium:
                medium.dialedBackground(wash)
            default:
                small.dialedBackground(wash)
            }
        }
        .widgetURL(WidgetLink.score.url)
    }

    // MARK: Sizes

    @ViewBuilder
    private var small: some View {
        if let score {
            VStack(spacing: 6) {
                ZStack {
                    ProgressRing(progress: Double(score.value) / 100, tint: accent, lineWidth: 7)
                    MoodFace(avatar: entry.avatar, emoji: score.emoji, accent: accent, size: 64)
                }
                .frame(width: 84, height: 84)
                .overlay(alignment: .bottom) {
                    Text("\(score.value)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                        .offset(y: 8)
                        .widgetAccentable()
                }
                Spacer(minLength: 8)
                Text(score.title)
                    .font(Theme.display(15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let boost = score.boost {
                    Text(boost)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let score {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: Double(score.value) / 100, tint: accent, lineWidth: 8)
                    MoodFace(avatar: entry.avatar, emoji: score.emoji, accent: accent, size: 92)
                }
                .frame(width: 116, height: 116)
                .overlay(alignment: .bottom) {
                    Text("\(score.value)")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                        .offset(y: 6)
                        .widgetAccentable()
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(score.title)
                        .font(Theme.display(18))
                        .foregroundStyle(Theme.ink)
                    Text(score.tagline)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    partsGrid(score.parts)
                    Spacer(minLength: 6)
                    if let boost = score.boost {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.circle.fill")
                                .foregroundStyle(accent)
                                .widgetAccentable()
                            Text(boost)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                    }
                }
            }
        } else {
            emptyState
        }
    }

    // MARK: Pieces

    /// Each pillar's share of the score, two columns of mini bars.
    private func partsGrid(_ parts: [WidgetInsights.Score.Part]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(parts.prefix(6), id: \.name) { part in
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    CapsuleBar(progress: part.progress, tint: tint(for: part.name), height: 4)
                }
            }
        }
    }

    private func tint(for part: String) -> Color {
        switch part {
        case "Water":    return Theme.water
        case "Steps":    return Theme.green
        case "Protein":  return Theme.protein
        case "Sleep":    return Theme.lavender
        case "Weigh-in": return Theme.sky
        default:         return Theme.orange
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("✨").font(.system(size: 34))
            Text("Your day score")
                .font(Theme.display(14))
                .foregroundStyle(Theme.ink)
            SyncHint()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Small", as: .systemSmall) { DialedScoreWidget() } timeline: { DialedEntry.preview }
#Preview("Medium", as: .systemMedium) { DialedScoreWidget() } timeline: { DialedEntry.preview }
