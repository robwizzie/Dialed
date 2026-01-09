//
//  WorkoutLogSheet.swift
//  Dialed
//
//  Comprehensive workout logging with exercise tracking
//

import SwiftUI
import SwiftData

struct WorkoutLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var dayLog: DayLog
    let onSave: () -> Void

    @State private var selectedTag: Constants.WorkoutTag = .general
    @State private var workoutScore: Int = 3
    @State private var notes: String = ""
    @State private var exercises: [ExerciseEntry] = []
    @State private var showAddExercise = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Workout Type Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workout Type")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Constants.WorkoutTag.allCases, id: \.self) { tag in
                                    Button(action: {
                                        selectedTag = tag
                                    }) {
                                        Text(tag.shortName)
                                            .font(.subheadline.bold())
                                            .foregroundColor(selectedTag == tag ? .white : .primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(selectedTag == tag ?
                                                        LinearGradient(
                                                            colors: [.green, .mint],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ) :
                                                        LinearGradient(
                                                            colors: [.ultraThinMaterial, .ultraThinMaterial],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(selectedTag == tag ? .clear : .white.opacity(0.1), lineWidth: 0.5)
                                                    )
                                                    .shadow(color: selectedTag == tag ? .green.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Quality Rating
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workout Quality")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 12) {
                            ForEach(1...5, id: \.self) { rating in
                                Button(action: {
                                    workoutScore = rating
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: rating <= workoutScore ? "star.fill" : "star")
                                            .font(.title2)
                                            .foregroundColor(rating <= workoutScore ? .yellow : .secondary.opacity(0.3))

                                        Text(ratingLabel(for: rating))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(rating <= workoutScore ? .yellow.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
                                            )
                                    )
                                }
                            }
                        }
                    }

                    // Exercises Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Exercises")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Button(action: {
                                showAddExercise = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Exercise")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)
                            }
                        }

                        if exercises.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary.opacity(0.3))

                                Text("No exercises logged yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Tap 'Add Exercise' to get started")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
                            VStack(spacing: 12) {
                                ForEach(exercises.indices, id: \.self) { index in
                                    ExerciseRow(
                                        exercise: $exercises[index],
                                        onDelete: {
                                            exercises.remove(at: index)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes (Optional)")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        TextField("How did the workout feel?", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
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
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveWorkout()
                    }
                }
            }
            .sheet(isPresented: $showAddExercise) {
                AddExerciseSheet(exercises: $exercises)
            }
        }
        .presentationDetents([.large])
    }

    private func ratingLabel(for rating: Int) -> String {
        switch rating {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Great"
        case 5: return "Perfect"
        default: return ""
        }
    }

    private func saveWorkout() {
        // Update day log
        dayLog.workoutTag = selectedTag.rawValue
        dayLog.workoutScore = workoutScore
        dayLog.workoutDetectedFromHealth = false

        // Create workout log
        let workoutLog = WorkoutLog(
            dayDate: dayLog.date,
            tag: selectedTag,
            workoutScore: workoutScore,
            notes: notes.isEmpty ? nil : notes,
            detectedFromHealth: false
        )

        // Add exercises
        var workoutExercises: [WorkoutExercise] = []
        for exercise in exercises {
            let workoutExercise = WorkoutExercise(
                exerciseName: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                weightLbs: exercise.weight,
                notes: exercise.notes
            )
            workoutExercise.workoutLog = workoutLog
            workoutExercises.append(workoutExercise)
            modelContext.insert(workoutExercise)
        }

        workoutLog.exercises = workoutExercises
        dayLog.workoutLog = workoutLog
        modelContext.insert(workoutLog)

        try? modelContext.save()

        onSave()
        dismiss()
    }
}

// MARK: - Exercise Entry Model

struct ExerciseEntry: Identifiable {
    let id = UUID()
    var name: String
    var sets: Int
    var reps: Int
    var weight: Double
    var notes: String?
    var previousSession: WorkoutExercise?
}

// MARK: - Exercise Row

struct ExerciseRow: View {
    @Binding var exercise: ExerciseEntry

    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exercise.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(exercise.sets)")
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 30)
                    .overlay(.ultraThinMaterial)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Reps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(exercise.reps)")
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 30)
                    .overlay(.ultraThinMaterial)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Weight")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(exercise.weight)) lbs")
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()
            }

            // Progress indicator
            if let previous = exercise.previousSession {
                HStack(spacing: 6) {
                    let improved = exercise.weight > previous.weightLbs ||
                                   (exercise.weight == previous.weightLbs && exercise.reps > previous.reps)

                    Image(systemName: improved ? "arrow.up.circle.fill" : "minus.circle.fill")
                        .font(.caption)
                        .foregroundColor(improved ? .green : .secondary)

                    Text(improved ? "Improved from last time!" : "Same as last time")
                        .font(.caption2)
                        .foregroundStyle(improved ? .green : .secondary)

                    Text("(\(Int(previous.weightLbs))lbs × \(previous.reps))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var exercises: [ExerciseEntry]

    @State private var exerciseName: String = ""
    @State private var sets: Int = 3
    @State private var reps: Int = 10
    @State private var weight: Double = 0
    @State private var selectedCategory: String = "Chest"
    @State private var useCustomName = false

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Exercise Selection
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Select Exercise")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Button(action: {
                                useCustomName.toggle()
                                if useCustomName {
                                    isNameFocused = true
                                }
                            }) {
                                Text(useCustomName ? "Use Preset" : "Custom")
                                    .font(.caption.bold())
                                    .foregroundColor(.blue)
                            }
                        }

                        if useCustomName {
                            TextField("Exercise name", text: $exerciseName)
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
                                .focused($isNameFocused)
                        } else {
                            // Category tabs
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(WorkoutExercise.CommonExercise.grouped.keys.sorted()), id: \.self) { category in
                                        Button(action: {
                                            selectedCategory = category
                                        }) {
                                            Text(category)
                                                .font(.subheadline)
                                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(
                                                    Capsule()
                                                        .fill(selectedCategory == category ? AppColors.primary : .ultraThinMaterial)
                                                        .overlay(
                                                            Capsule()
                                                                .stroke(selectedCategory == category ? .clear : .white.opacity(0.1), lineWidth: 0.5)
                                                        )
                                                )
                                        }
                                    }
                                }
                            }

                            // Exercise buttons
                            let categoryExercises = WorkoutExercise.CommonExercise.grouped[selectedCategory] ?? []
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(categoryExercises, id: \.self) { exercise in
                                    Button(action: {
                                        exerciseName = exercise.rawValue
                                        loadPreviousSession(for: exercise.rawValue)
                                    }) {
                                        Text(exercise.rawValue)
                                            .font(.subheadline)
                                            .foregroundColor(exerciseName == exercise.rawValue ? .white : .primary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(exerciseName == exercise.rawValue ?
                                                        LinearGradient(
                                                            colors: [.blue, .cyan],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ) :
                                                        LinearGradient(
                                                            colors: [.ultraThinMaterial, .ultraThinMaterial],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(exerciseName == exercise.rawValue ? .clear : .white.opacity(0.1), lineWidth: 0.5)
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                    }

                    // Sets, Reps, Weight
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Details")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 16) {
                            // Sets
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Stepper("\(sets)", value: $sets, in: 1...10)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)

                            // Reps
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Reps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Stepper("\(reps)", value: $reps, in: 1...50)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Weight
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weight (lbs)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                TextField("0", value: $weight, format: .number)
                                    .keyboardType(.decimalPad)
                                    .font(.title2.bold())
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

                                Text("lbs")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addExercise()
                    }
                    .disabled(exerciseName.isEmpty || weight == 0)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func loadPreviousSession(for exerciseName: String) {
        // Try to load previous session data
        if let previous = WorkoutExercise.getPreviousSession(
            for: exerciseName,
            before: Date(),
            context: modelContext
        ) {
            // Pre-fill with previous values
            sets = previous.sets
            reps = previous.reps
            weight = previous.weightLbs
        }
    }

    private func addExercise() {
        let previousSession = WorkoutExercise.getPreviousSession(
            for: exerciseName,
            before: Date(),
            context: modelContext
        )

        let entry = ExerciseEntry(
            name: exerciseName,
            sets: sets,
            reps: reps,
            weight: weight,
            previousSession: previousSession
        )

        exercises.append(entry)
        dismiss()
    }
}

#Preview {
    @Previewable @State var dayLog = DayLog(date: Date())
    WorkoutLogSheet(dayLog: $dayLog, onSave: {})
}
