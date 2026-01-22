//
//  WorkoutLogSheet.swift
//  Dialed
//
//  Comprehensive workout logging with set-by-set tracking
//

import SwiftUI
import SwiftData

struct WorkoutLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var dayLog: DayLog
    let onSave: () -> Void

    @State private var selectedTag: Constants.WorkoutTag = .push
    @State private var workoutScore: Int = 3
    @State private var notes: String = ""
    @State private var exercises: [ExerciseEntry] = []
    @State private var showAddExercise = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Workout Type Selection
                    workoutTypeSection

                    // Quality Rating
                    qualityRatingSection

                    // Exercises Section
                    exercisesSection

                    // Notes
                    notesSection
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

    // MARK: - Sections

    private var workoutTypeSection: some View {
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
    }

    private var qualityRatingSection: some View {
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
    }

    private var exercisesSection: some View {
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
                emptyExercisesView
            } else {
                ForEach(exercises.indices, id: \.self) { index in
                    ExerciseCard(
                        exercise: $exercises[index],
                        onDelete: {
                            exercises.remove(at: index)
                        }
                    )
                }
            }
        }
    }

    private var emptyExercisesView: some View {
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
    }

    private var notesSection: some View {
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

    // MARK: - Helpers

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

        // Add exercises with sets
        for exercise in exercises {
            let workoutExercise = WorkoutExercise(
                exerciseName: exercise.name,
                notes: exercise.notes
            )
            workoutExercise.workoutLog = workoutLog

            // Add sets to exercise
            for (index, setData) in exercise.sets.enumerated() {
                let workoutSet = WorkoutSet(
                    setNumber: index + 1,
                    reps: setData.reps,
                    weightLbs: setData.weightLbs,
                    restSeconds: setData.restSeconds,
                    notes: setData.notes,
                    isWarmup: setData.isWarmup,
                    rpe: setData.rpe
                )
                workoutSet.exercise = workoutExercise
                modelContext.insert(workoutSet)
            }

            modelContext.insert(workoutExercise)
        }

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
    var sets: [SetData] = []
    var notes: String?
    var previousSession: WorkoutExercise?

    struct SetData: Identifiable {
        let id = UUID()
        var reps: Int
        var weightLbs: Double
        var restSeconds: Int?
        var notes: String?
        var isWarmup: Bool = false
        var rpe: Int?
    }
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    @Binding var exercise: ExerciseEntry
    let onDelete: () -> Void

    @State private var showAddSet = false
    @State private var expandedSetIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
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

            // Previous session summary
            if let previous = exercise.previousSession, let topSet = previous.topSet {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Last: \(Int(topSet.weightLbs)) lbs × \(topSet.reps) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Sets
            if exercise.sets.isEmpty {
                Button(action: { showAddSet = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Set")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.blue.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .foregroundColor(.blue)
            } else {
                VStack(spacing: 8) {
                    ForEach(exercise.sets.indices, id: \.self) { index in
                        SetRow(
                            setNumber: index + 1,
                            setData: $exercise.sets[index],
                            onDelete: {
                                exercise.sets.remove(at: index)
                            }
                        )
                    }

                    Button(action: { showAddSet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("Add Set")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
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
        .sheet(isPresented: $showAddSet) {
            AddSetSheet(
                exerciseName: exercise.name,
                previousSet: exercise.sets.last,
                onSave: { setData in
                    exercise.sets.append(setData)
                }
            )
        }
    }
}

// MARK: - Set Row

struct SetRow: View {
    let setNumber: Int
    @Binding var setData: ExerciseEntry.SetData
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Set number
            Text("\(setNumber)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 20)

            if setData.isWarmup {
                Text("W")
                    .font(.caption2.bold())
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.orange.opacity(0.2))
                    )
            }

            // Weight × Reps
            Text("\(Int(setData.weightLbs)) lbs × \(setData.reps)")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            // RPE if provided
            if let rpe = setData.rpe {
                Text("RPE \(rpe)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            }

            // Delete
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var exercises: [ExerciseEntry]

    @State private var exerciseName: String = ""
    @State private var selectedCategory: String = "Chest"
    @State private var useCustomName = false

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

                            // Exercise grid
                            let categoryExercises = WorkoutExercise.CommonExercise.grouped[selectedCategory] ?? []
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(categoryExercises, id: \.self) { exercise in
                                    Button(action: {
                                        exerciseName = exercise.rawValue
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
                    .disabled(exerciseName.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func addExercise() {
        let previousSession = WorkoutExercise.getPreviousSession(
            for: exerciseName,
            before: Date(),
            context: modelContext
        )

        let entry = ExerciseEntry(
            name: exerciseName,
            sets: [],
            previousSession: previousSession
        )

        exercises.append(entry)
        dismiss()
    }
}

// MARK: - Add Set Sheet

struct AddSetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exerciseName: String
    let previousSet: ExerciseEntry.SetData?
    let onSave: (ExerciseEntry.SetData) -> Void

    @State private var reps: Int
    @State private var weight: Double
    @State private var isWarmup: Bool = false
    @State private var restSeconds: Int = 90
    @State private var rpe: Int? = nil
    @State private var notes: String = ""

    init(exerciseName: String, previousSet: ExerciseEntry.SetData?, onSave: @escaping (ExerciseEntry.SetData) -> Void) {
        self.exerciseName = exerciseName
        self.previousSet = previousSet
        self.onSave = onSave

        // Pre-fill with previous set data
        _reps = State(initialValue: previousSet?.reps ?? 10)
        _weight = State(initialValue: previousSet?.weightLbs ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Exercise name
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exerciseName)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        if let previous = previousSet {
                            Text("Last set: \(Int(previous.weightLbs)) lbs × \(previous.reps) reps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Weight
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight (lbs)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("0", value: $weight, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.title.bold())
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

                    // Reps
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reps")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Stepper("\(reps) reps", value: $reps, in: 1...100)
                            .font(.title3.bold())
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

                    // Warmup toggle
                    Toggle(isOn: $isWarmup) {
                        HStack(spacing: 8) {
                            Image(systemName: "flame")
                                .foregroundStyle(.orange)
                            Text("Warmup Set")
                                .font(.body)
                                .foregroundStyle(.primary)
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
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Add Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let setData = ExerciseEntry.SetData(
                            reps: reps,
                            weightLbs: weight,
                            restSeconds: restSeconds,
                            notes: notes.isEmpty ? nil : notes,
                            isWarmup: isWarmup,
                            rpe: rpe
                        )
                        onSave(setData)
                        dismiss()
                    }
                    .disabled(weight == 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    @Previewable @State var dayLog = DayLog(date: Date())
    WorkoutLogSheet(dayLog: $dayLog, onSave: {})
}
