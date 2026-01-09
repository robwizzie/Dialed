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
        .postWorkoutLog: (19, 0),
        .closeTheDay: (20, 30)
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
        var customTimesDict: [String: ScheduledTime] = [:]
        for (type, time) in customTimes {
            customTimesDict[type.rawValue] = ScheduledTime(hour: time.hour, minute: time.minute)
        }
        updatedSettings.customChecklistTimes = customTimesDict.isEmpty ? nil : customTimesDict

        updatedSettings.save()
    }
}

#Preview {
    NavigationStack {
        ChecklistSettingsView()
    }
}
