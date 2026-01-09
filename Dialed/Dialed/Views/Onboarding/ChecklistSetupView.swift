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
        .postWorkoutLog: (19, 0),
        .closeTheDay: (20, 30)
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

#Preview {
    ChecklistSetupView(
        selectedItems: .constant([.amSkincare, .lunchVitamins, .creatine]),
        customTimes: .constant([:]),
        onContinue: {},
        onBack: {}
    )
}
