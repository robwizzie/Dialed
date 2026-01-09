//
//  ChecklistComponents.swift
//  Dialed
//
//  Shared, reusable checklist UI components (DRY principle)
//

import SwiftUI

// MARK: - Checklist Item Row
struct ChecklistItemRow: View {
    let item: Constants.ChecklistType
    let isSelected: Bool
    let time: (hour: Int, minute: Int)
    let onToggle: () -> Void
    let onTimeTap: () -> Void

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        isSelected ?
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [.secondary.opacity(0.3), .secondary.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isSelected ? .green.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Time button
                if isSelected {
                    Button(action: onTimeTap) {
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
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppColors.primary.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Time Picker Item (Identifiable wrapper)
struct TimePickerItem: Identifiable {
    let type: Constants.ChecklistType
    var id: String { type.rawValue }
}

// MARK: - Time Picker Sheet
struct TimePickerSheet: View {
    let item: Constants.ChecklistType
    @Binding var time: (hour: Int, minute: Int)
    let onDismiss: () -> Void

    @State private var selectedHour: Int
    @State private var selectedMinute: Int

    init(item: Constants.ChecklistType, time: Binding<(hour: Int, minute: Int)>, onDismiss: @escaping () -> Void) {
        self.item = item
        self._time = time
        self.onDismiss = onDismiss
        self._selectedHour = State(initialValue: time.wrappedValue.hour)
        self._selectedMinute = State(initialValue: time.wrappedValue.minute)
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: {
                            Calendar.current.date(from: DateComponents(hour: selectedHour, minute: selectedMinute)) ?? Date()
                        },
                        set: { newDate in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            selectedHour = components.hour ?? 12
                            selectedMinute = components.minute ?? 0
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Spacer()
            }
            .navigationTitle(item.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        time = (hour: selectedHour, minute: selectedMinute)
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
