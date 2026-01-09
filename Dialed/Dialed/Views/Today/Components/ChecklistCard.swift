//
//  ChecklistCard.swift
//  Dialed
//
//  Daily routine checklist with tap-to-complete
//

import SwiftUI

struct ChecklistCard: View {
    let items: [ChecklistItem]
    let onToggle: (ChecklistItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Routine")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ChecklistRow(item: item, onToggle: { onToggle(item) })

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                            .overlay(.ultraThinMaterial)
                    }
                }
            }
        }
        .elevatedGlassCard(cornerRadius: 16, padding: 16)
    }
}

struct ChecklistRow: View {
    let item: ChecklistItem
    let onToggle: () -> Void

    private var iconName: String {
        switch item.checklistStatus {
        case .done:
            return "checkmark.circle.fill"
        case .skipped:
            return "xmark.circle.fill"
        case .open:
            return "circle"
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.checklistStatus {
        case .done:
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
        case .skipped:
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
        case .open:
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary.opacity(0.3))
        }
    }

    private var timeString: String {
        let hour = item.scheduledTime.hour ?? 0
        let minute = item.scheduledTime.minute ?? 0

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        // Create a date from components
        var calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()

        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: {
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()

            onToggle()
        }) {
            HStack(spacing: 12) {
                // Checkbox icon
                iconView
                    .frame(width: 32, height: 32)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    if let type = item.checklistType {
                        Text(type.rawValue)
                            .font(.subheadline.bold())
                            .foregroundStyle(item.checklistStatus == .done ? .secondary : .primary)
                            .strikethrough(item.checklistStatus == .done)

                        Text(type.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Time with glass pill
                Text(timeString)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )
                    )
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let sampleItems = [
        ChecklistItem(type: .amSkincare, dayDate: today),
        ChecklistItem(type: .lunchVitamins, dayDate: today),
        ChecklistItem(type: .creatine, dayDate: today),
        ChecklistItem(type: .pmSkincare, dayDate: today),
    ]

    sampleItems[0].markDone()
    sampleItems[1].markDone()

    return ChecklistCard(items: sampleItems, onToggle: { _ in })
        .padding()
        .background(AppColors.background)
}
