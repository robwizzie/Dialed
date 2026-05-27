//
//  TimelineEventRow.swift
//  Dialed
//
//  Renders a single ContextEvent on the Timeline. Pulls icon/color/copy
//  from the event's kind so every kind looks distinct at a glance.
//

import SwiftUI

struct TimelineEventRow: View {
    let event: ContextEvent

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Time gutter
            Text(timeString)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
                .padding(.top, 4)

            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: gradient,
                        startPoint: .top,
                        endPoint: .bottom
                    ).opacity(0.22))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                    )
            }
            .frame(width: 32, height: 32)

            // Body
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if let badge = sourceBadge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(.white.opacity(0.08))
                            )
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                }
                if let annotation = event.aiAnnotation, !annotation.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                        Text(annotation)
                            .font(.system(size: 11, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(AppColors.Pillar.recovery.gradient.last)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm - 2)
        .padding(.horizontal, Spacing.sm)
        .background(
            // Use the nowCard token at full opacity — the previous
            // .ultraThinMaterial.opacity(0.4) washed out on a dark
            // background and cards looked nearly invisible.
            RoundedRectangle(cornerRadius: Spacing.md, style: .continuous)
                .fill(AppColors.nowCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.md, style: .continuous)
                        .stroke(gradient.first?.opacity(0.14) ?? AppColors.glassStroke, lineWidth: 0.6)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [timeString, title]
        if let s = subtitle { parts.append(s) }
        if let s = sourceBadge { parts.append("from \(s.capitalized)") }
        if let annotation = event.aiAnnotation, !annotation.isEmpty {
            parts.append("insight: \(annotation)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Derived presentation

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: event.timestamp)
    }

    private var icon: String {
        switch event.kind {
        case .meal:          return "fork.knife"
        case .water:         return "drop.fill"
        case .caffeine:      return "cup.and.saucer.fill"
        case .alcohol:       return "wineglass.fill"
        case .supplement:    return "pills.fill"
        case .workout:       return "figure.strengthtraining.traditional"
        case .steps:         return "figure.walk"
        case .mile:          return "figure.run"
        case .sleep:         return "moon.stars.fill"
        case .mood:          return "face.smiling.fill"
        case .energy:        return "bolt.fill"
        case .stress:        return "waveform.path"
        case .soreness:      return "bandage.fill"
        case .journal:       return "text.book.closed"
        case .note:          return "square.and.pencil"
        case .routineTask:   return "checkmark.circle.fill"
        case .biometricEvent: return "heart.fill"
        case .weather:       return "cloud.sun.fill"
        case .calendarEvent: return "calendar"
        case .location:      return "location.fill"
        case .aiInsight:     return "sparkles"
        }
    }

    private var gradient: [Color] {
        switch event.kind {
        case .water, .sleep:
            return AppColors.Pillar.readiness.gradient
        case .meal, .caffeine, .supplement, .alcohol, .steps, .mile:
            return AppColors.Pillar.energy.gradient
        case .mood, .journal, .note, .stress, .soreness:
            return AppColors.Pillar.recovery.gradient
        case .workout, .biometricEvent:
            return AppColors.Pillar.strain.gradient
        case .energy:
            return AppColors.Pillar.energy.gradient
        // Calendar/weather/location aren't pillar-owned but inherit the
        // readiness palette so they still feel of-a-piece rather than
        // dead inert grey.
        case .calendarEvent, .weather, .location:
            return AppColors.Pillar.readiness.gradient
        case .routineTask:
            return AppColors.Pillar.recovery.gradient
        case .aiInsight:
            return AppColors.Pillar.recovery.gradient
        }
    }

    private var title: String {
        switch event.kind {
        case .meal:
            let cals = event.value.map { "\(Int($0)) kcal" }
            let protein = event.secondaryValue.map { "\(Int($0))g protein" }
            return [cals, protein].compactMap { $0 }.joined(separator: " · ")
                .ifEmpty("Meal")
        case .water:
            return event.value.map { "\(Int($0)) oz water" } ?? "Water"
        case .caffeine:
            return event.value.map { "\(Int($0)) mg caffeine" } ?? "Caffeine"
        case .alcohol:
            return event.value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) drink\($0 == 1 ? "" : "s")" } ?? "Alcohol"
        case .supplement:
            return event.subtype?.capitalized ?? "Supplement"
        case .workout:
            let dur = event.value.map { "\(Int($0)) min" } ?? ""
            let type = event.subtype?.capitalized ?? "Workout"
            return [type, dur].filter { !$0.isEmpty }.joined(separator: " · ")
        case .steps:
            return event.value.map { "\(Int($0)) steps" } ?? "Steps"
        case .mile:
            return event.value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) mi" } ?? "Run"
        case .sleep:
            return "Sleep logged"
        case .mood:
            return event.value.map { "Mood \(Int($0))/5" } ?? "Mood check"
        case .energy:
            return event.value.map { "Energy \(Int($0))/5" } ?? "Energy check"
        case .stress:
            return event.value.map { "Stress \(Int($0))/5" } ?? "Stress check"
        case .soreness:
            return event.value.map { "Soreness \(Int($0))/5" } ?? "Soreness"
        case .journal:
            return "Journal"
        case .note:
            return event.text ?? "Note"
        case .routineTask:
            return event.text ?? "Routine task"
        case .biometricEvent:
            return event.text ?? "Biometric event"
        case .weather:
            return event.text ?? "Weather"
        case .calendarEvent:
            return event.text ?? "Calendar"
        case .location:
            return event.text ?? "Location"
        case .aiInsight:
            return event.text ?? "Insight"
        }
    }

    private var subtitle: String? {
        switch event.kind {
        case .note, .journal:
            return nil  // body lives in title for note, journal shows aiAnnotation
        case .mood, .energy:
            return event.text
        case .workout:
            if let cals = event.secondaryValue, cals > 0 {
                return "\(Int(cals)) kcal burned"
            }
            return event.text
        default:
            return event.text
        }
    }

    /// Source chip — only for non-manual entries.
    private var sourceBadge: String? {
        switch event.source {
        case .manual: return nil
        case .voice: return "VOICE"
        case .healthkit: return "HEALTH"
        case .fitbit: return "FITBIT"
        case .weatherkit: return "WEATHER"
        case .eventkit: return "CALENDAR"
        case .ai: return "AI"
        case .migration: return nil
        }
    }
}
