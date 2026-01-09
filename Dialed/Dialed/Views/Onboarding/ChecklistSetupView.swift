//
//  ChecklistSetupView.swift
//  Dialed
//
//  Customize daily routine checklist during onboarding
//

import SwiftUI

struct ChecklistSetupView: View {
    @Binding var selectedItems: Set<Constants.ChecklistType>
    @Binding var customTimes: [Constants.ChecklistType: (hour: Int, minute: Int)]

    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var showingTimePicker: Constants.ChecklistType?

    private let defaultTimes: [Constants.ChecklistType: (hour: Int, minute: Int)] = [
        .amSkincare: (7, 0),
        .lunchVitamins: (12, 0),
        .creatine: (16, 0),
        .pmSkincare: (21, 0),
        .stretching: (19, 0),
        .meditation: (7, 30)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Daily Routine")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Choose tasks you want to track daily. You can change these anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Checklist items
            ScrollView {
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
                .padding(.horizontal, 30)
            }

            Spacer()

            // Navigation buttons
            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedItems.isEmpty ? AppColors.primary.opacity(0.5) : AppColors.primary)
                                .shadow(color: selectedItems.isEmpty ? .clear : AppColors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                        )
                }
                .disabled(selectedItems.isEmpty)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
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
}

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
    ChecklistSetupView(
        selectedItems: .constant([.amSkincare, .lunchVitamins, .creatine]),
        customTimes: .constant([:]),
        onContinue: {},
        onBack: {}
    )
}
