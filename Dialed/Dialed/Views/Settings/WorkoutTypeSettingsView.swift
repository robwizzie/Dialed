//
//  WorkoutTypeSettingsView.swift
//  Dialed
//
//  Manage workout type tracking and custom types
//

import SwiftUI
import SwiftData

struct WorkoutTypeSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CustomWorkoutType.createdAt) private var customTypes: [CustomWorkoutType]
    @State private var preferences = WorkoutTypePreferences.load()
    @State private var showAddCustomType = false

    var body: some View {
        NavigationStack {
            List {
                // Filtering section
                Section {
                    Toggle(isOn: $preferences.trackOnlyTraditionalStrength) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Traditional Strength Only")
                                .font(.body)
                            Text("Only track Traditional Strength Training workouts from HealthKit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: preferences.trackOnlyTraditionalStrength) { _, _ in
                        preferences.save()
                    }
                } header: {
                    Text("Workout Filtering")
                } footer: {
                    Text("When enabled, only Traditional Strength Training workouts will be tracked. Other workout types will be ignored.")
                }

                // Built-in workout types
                Section {
                    ForEach(Constants.WorkoutTag.allCases, id: \.self) { tag in
                        Toggle(isOn: Binding(
                            get: { preferences.enabledBuiltInTypes.contains(tag.rawValue) },
                            set: { enabled in
                                if enabled {
                                    preferences.enabledBuiltInTypes.insert(tag.rawValue)
                                } else {
                                    preferences.enabledBuiltInTypes.remove(tag.rawValue)
                                }
                                preferences.save()
                            }
                        )) {
                            HStack {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .foregroundStyle(.green)
                                Text(tag.shortName)
                            }
                        }
                    }
                } header: {
                    Text("Built-In Workout Types")
                } footer: {
                    Text("Select which workout types to show in the workout log")
                }

                // Custom workout types
                Section {
                    ForEach(customTypes) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(Color(hex: type.colorHex))

                            Text(type.shortName)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { type.isEnabled },
                                set: { newValue in
                                    type.isEnabled = newValue
                                    try? modelContext.save()
                                }
                            ))
                            .labelsHidden()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(type)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button(action: {
                        showAddCustomType = true
                    }) {
                        Label("Add Custom Type", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Custom Workout Types")
                } footer: {
                    Text("Create your own workout categories (e.g., Cardio, Yoga, Sports)")
                }
            }
            .navigationTitle("Workout Types")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddCustomType) {
                AddCustomWorkoutTypeSheet(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Add Custom Workout Type Sheet

struct AddCustomWorkoutTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let modelContext: ModelContext

    @State private var name: String = ""
    @State private var shortName: String = ""
    @State private var selectedIcon: String = "dumbbell.fill"
    @State private var selectedColor: Color = .green

    private let iconOptions = [
        "dumbbell.fill", "figure.run", "figure.yoga",
        "figure.cycling", "figure.boxing", "figure.soccer",
        "figure.basketball", "figure.tennis", "heart.fill",
        "bolt.fill", "flame.fill", "star.fill"
    ]

    private let colorOptions: [(name: String, color: Color, hex: String)] = [
        ("Green", .green, "#00C853"),
        ("Blue", .blue, "#2196F3"),
        ("Purple", .purple, "#9C27B0"),
        ("Orange", .orange, "#FF9800"),
        ("Red", .red, "#F44336"),
        ("Pink", .pink, "#E91E63"),
        ("Cyan", .cyan, "#00BCD4"),
        ("Indigo", .indigo, "#3F51B5")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Full Name", text: $name)
                        .autocorrectionDisabled()

                    TextField("Short Name", text: $shortName)
                        .autocorrectionDisabled()
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                            }) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(selectedIcon == icon ? selectedColor : .gray)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedIcon == icon ? selectedColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedIcon == icon ? selectedColor : .clear, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                        ForEach(colorOptions, id: \.name) { option in
                            Button(action: {
                                selectedColor = option.color
                            }) {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Circle()
                                            .stroke(.white, lineWidth: selectedColor == option.color ? 3 : 0)
                                    )
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Add Workout Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveCustomType()
                    }
                    .disabled(name.isEmpty || shortName.isEmpty)
                }
            }
        }
    }

    private func saveCustomType() {
        let hexColor = colorOptions.first { $0.color == selectedColor }?.hex ?? "#00C853"

        let customType = CustomWorkoutType(
            name: name,
            shortName: shortName,
            icon: selectedIcon,
            colorHex: hexColor,
            isEnabled: true
        )

        modelContext.insert(customType)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    WorkoutTypeSettingsView()
}
