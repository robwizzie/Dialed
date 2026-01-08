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
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal)
                .padding(.top)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ChecklistRow(item: item, onToggle: { onToggle(item) })

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .background(AppColors.surface.opacity(0.5))
        .cornerRadius(12)
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

    private var iconColor: Color {
        switch item.checklistStatus {
        case .done:
            return AppColors.success
        case .skipped:
            return AppColors.textSecondary
        case .open:
            return AppColors.textSecondary.opacity(0.3)
        }
    }

    private var timeString: String {
        let hour = item.scheduledTime.hour ?? 0
        let minute = item.scheduledTime.minute ?? 0

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        // Create a date from components
        let calendar = Calendar.current
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
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    if let type = item.checklistType {
                        Text(type.rawValue)
                            .font(.subheadline.bold())
                            .foregroundColor(item.checklistStatus == .done ? AppColors.textSecondary : AppColors.textPrimary)
                            .strikethrough(item.checklistStatus == .done)

                        Text(type.description)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                // Time
                Text(timeString)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(AppColors.textSecondary)
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