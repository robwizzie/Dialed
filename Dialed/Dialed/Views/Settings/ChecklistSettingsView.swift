//
//  ChecklistSettingsView.swift
//  Dialed
//
//  Manage daily routine checklist items and reminder times
//

import SwiftUI

struct ChecklistSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = UserSettings.load()

    @State private var selectedItems: Set<Constants.ChecklistType>
    @State private var customTimes: [Constants.ChecklistType: (hour: Int, minute: Int)]

    @State private var showingTimePicker: Constants.ChecklistType?

    private let defaultTimes: [Constants.ChecklistType: (hour: Int, minute: Int)] = [
        .amSkincare: (7, 0),
        .lunchVitamins: (12, 0),
        .creatine: (16, 0),
        .pmSkincare: (21, 0),
        .stretching: (19, 0),
        .meditation: (7, 30)
    ]

    init() {
        let settings = UserSettings.load()

        // Load enabled items
        let enabledTypes = settings.enabledNotifications.compactMap { Constants.ChecklistType(rawValue: $0) }
        _selectedItems = State(initialValue: Set(enabledTypes))

        // Load custom times
        var times: [Constants.ChecklistType: (hour: Int, minute: Int)] = [:]
        if let customChecklistTimes = settings.customChecklistTimes {
            for (key, scheduledTime) in customChecklistTimes {
                if let type = Constants.ChecklistType(rawValue: key) {
                    times[type] = (hour: scheduledTime.hour, minute: scheduledTime.minute)
                }
            }
        }
        _customTimes = State(initialValue: times)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Info card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Daily Routine")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                    }

                    Text("Select tasks you want to track daily. Set reminder times for each item to stay consistent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.green.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.horizontal)

                // Checklist items
                VStack(spacing: 12) {
                    ForEach(Constants.ChecklistType.allCases, id: \.self) { item in
                        ChecklistItemRow(
                            item: item,
                            isSelected: selectedItems.contains(item),
                            time: customTimes[item] ?? defaultTimes[item] ?? (12, 0),
                            onToggle: {
                                if selectedItems.contains(item) {
                                    selectedItems.remove(item)
                                } else {
                                    selectedItems.insert(item)
                                    // Set default time if not already set
                                    if customTimes[item] == nil {
                                        customTimes[item] = defaultTimes[item] ?? (12, 0)
                                    }
                                }
                            },
                            onTimeTap: {
                                showingTimePicker = item
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Daily Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                    dismiss()
                }
                .disabled(selectedItems.isEmpty)
            }
        }
        .sheet(item: Binding(
            get: { showingTimePicker.map { TimePickerItem(type: $0) } },
            set: { showingTimePicker = $0?.type }
        )) { item in
            TimePickerSheet(
                item: item.type,
                time: Binding(
                    get: { customTimes[item.type] ?? defaultTimes[item.type] ?? (12, 0) },
                    set: { customTimes[item.type] = $0 }
                ),
                onDismiss: { showingTimePicker = nil }
            )
        }
    }

    private func saveChanges() {
        var updatedSettings = settings

        // Save enabled items
        updatedSettings.enabledNotifications = Set(selectedItems.map { $0.rawValue })

        // Save custom times
        var customTimesDict: [String: UserSettings.ScheduledTime] = [:]
        for (type, time) in customTimes {
            customTimesDict[type.rawValue] = UserSettings.ScheduledTime(hour: time.hour, minute: time.minute)
        }
        updatedSettings.customChecklistTimes = customTimesDict.isEmpty ? nil : customTimesDict

        updatedSettings.save()
    }
}

// Reuse components from ChecklistSetupView
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

struct TimePickerItem: Identifiable {
    let type: Constants.ChecklistType
    var id: String { type.rawValue }
}

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

#Preview {
    NavigationStack {
        ChecklistSettingsView()
    }
}
