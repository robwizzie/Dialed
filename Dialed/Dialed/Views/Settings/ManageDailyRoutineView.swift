//
//  ManageDailyRoutineView.swift
//  Dialed
//
//  Manage custom daily routine tasks
//

import SwiftUI
import SwiftData

struct ManageDailyRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showAddTask = false
    @State private var routineTemplates: [RoutineTaskTemplate] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily Routine Tasks")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Customize your daily routine checklist. Add custom tasks, set times, and track your consistency.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Automatic points info
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.fill")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart Point Distribution")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)

                            Text("The 10 routine points are automatically distributed equally among all your tasks. More tasks = fewer points each, ensuring your total never exceeds 100.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.green.opacity(0.3), lineWidth: 1)
                            )
                    )

                    // Default tasks section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Default Tasks")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text("These are the built-in tasks. They cannot be edited or removed, but you can add your own custom tasks below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            ForEach(Constants.ChecklistType.allCases, id: \.self) { type in
                                DefaultTaskRow(type: type)
                            }
                        }
                    }

                    // Custom tasks section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Custom Tasks")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)

                            Spacer()

                            Button(action: {
                                showAddTask = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Task")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                            }
                        }

                        if routineTemplates.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary.opacity(0.3))

                                Text("No custom tasks yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Tap 'Add Task' to create your first custom routine item")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                        } else {
                            VStack(spacing: 8) {
                                ForEach(routineTemplates) { template in
                                    CustomTaskRow(template: template, onDelete: {
                                        deleteTemplate(template)
                                    })
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Daily Routine")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddTask) {
                AddCustomTaskSheet(onSave: { template in
                    routineTemplates.append(template)
                    saveTemplates()
                })
            }
            .onAppear {
                loadTemplates()
            }
        }
    }

    private func loadTemplates() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "routineTaskTemplates"),
           let templates = try? JSONDecoder().decode([RoutineTaskTemplate].self, from: data) {
            routineTemplates = templates
        }
    }

    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(routineTemplates) {
            UserDefaults.standard.set(data, forKey: "routineTaskTemplates")
        }
    }

    private func deleteTemplate(_ template: RoutineTaskTemplate) {
        routineTemplates.removeAll { $0.id == template.id }
        saveTemplates()
    }
}

// MARK: - Default Task Row

struct DefaultTaskRow: View {
    let type: Constants.ChecklistType

    private var timeString: String {
        let hour = type.defaultTime.hour ?? 0
        let minute = type.defaultTime.minute ?? 0

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()

        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Custom Task Row

struct CustomTaskRow: View {
    let template: RoutineTaskTemplate
    let onDelete: () -> Void

    private var timeString: String {
        let hour = template.scheduledTime.hour ?? 0
        let minute = template.scheduledTime.minute ?? 0

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()

        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                if let description = template.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
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

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Add Custom Task Sheet

struct AddCustomTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (RoutineTaskTemplate) -> Void

    @State private var taskTitle: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedHour: Int = 9
    @State private var selectedMinute: Int = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Task Name")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        TextField("e.g., Morning Meditation", text: $taskTitle)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                    }

                    // Description (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Description")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text("(Optional)")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }

                        TextField("e.g., 10 minutes of breathing exercises", text: $taskDescription)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                    }

                    // Info about automatic points
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("Point values are automatically calculated based on your total number of tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.blue.opacity(0.2), lineWidth: 1)
                            )
                    )

                    // Time
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scheduled Time")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            // Hour picker
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hour")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Picker("Hour", selection: $selectedHour) {
                                    ForEach(0..<24) { hour in
                                        Text("\(hour)").tag(hour)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 100)
                                .clipped()
                            }
                            .frame(maxWidth: .infinity)

                            // Minute picker
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Minute")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Picker("Minute", selection: $selectedMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 100)
                                .clipped()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                )
                        )
                    }
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Add Custom Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let template = RoutineTaskTemplate(
                            title: taskTitle,
                            description: taskDescription.isEmpty ? nil : taskDescription,
                            points: 0,  // Points are calculated dynamically
                            scheduledTime: DateComponents(hour: selectedHour, minute: selectedMinute)
                        )
                        onSave(template)
                        dismiss()
                    }
                    .disabled(taskTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    ManageDailyRoutineView()
}
