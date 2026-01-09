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

    @Binding var dayLog: DayLog
    let onSave: () -> Void

    @State private var selectedTag: Constants.WorkoutTag = .push
    @State private var workoutScore: Int = 3
    @State private var notes: String = ""
    @State private var exercises: [ExerciseEntry] = []
    @State private var showAddExercise = false
    
    // Use the dayLog's model context to ensure same context for relationships
    private var modelContext: ModelContext? {
        dayLog.modelContext
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    workoutTypeSection
                    qualityRatingSection
                    exercisesSection
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
                AddExerciseSheet(exercises: $exercises, modelContext: modelContext)
            }
            .onAppear {
                loadExistingWorkout()
            }
        }
        .presentationDetents([.large])
    }
    
    private func loadExistingWorkout() {
        // Load existing workout data if present
        if let workoutLog = dayLog.workoutLog {
            if let tag = Constants.WorkoutTag(rawValue: workoutLog.tag) {
                selectedTag = tag
            }
            workoutScore = workoutLog.workoutScore
            notes = workoutLog.notes ?? ""
            
            // Load exercises if any
            if let workoutExercises = workoutLog.exercises {
                exercises = workoutExercises.map { exercise in
                    ExerciseEntry(
                        name: exercise.exerciseName,
                        sets: exercise.sets,
                        reps: exercise.reps,
                        weight: exercise.weightLbs,
                        notes: exercise.notes,
                        previousSession: nil
                    )
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var workoutTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Type")
                .font(.headline)
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Constants.WorkoutTag.allCases, id: \.self) { tag in
                        workoutTagButton(tag)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func workoutTagButton(_ tag: Constants.WorkoutTag) -> some View {
        Button(action: {
            selectedTag = tag
        }) {
            Text(tag.shortName)
                .font(.subheadline.bold())
                .foregroundColor(selectedTag == tag ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(workoutTagBackground(isSelected: selectedTag == tag))
        }
    }
    
    private func workoutTagBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ?
                LinearGradient(
                    colors: [.green, .mint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) :
                LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? .clear : .white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: isSelected ? .green.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
    }
    
    private var qualityRatingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Quality")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { rating in
                    ratingButton(rating)
                }
            }
        }
    }
    
    private func ratingButton(_ rating: Int) -> some View {
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
            .background(ratingBackground(rating))
        }
    }
    
    private func ratingBackground(_ rating: Int) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(white: 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(rating <= workoutScore ? .yellow.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
            )
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
                exercisesList
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
                .fill(Color(white: 0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    private var exercisesList: some View {
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
                        .fill(Color(white: 0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
        }
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
        guard let modelContext = modelContext else { return }
        
        // Update day log
        dayLog.workoutTag = selectedTag.rawValue
        dayLog.workoutScore = workoutScore
        dayLog.workoutDetectedFromHealth = false

        // Check if we're updating an existing workout or creating a new one
        let workoutLog: WorkoutLog
        if let existing = dayLog.workoutLog {
            // Update existing workout
            workoutLog = existing
            workoutLog.tag = selectedTag.rawValue
            workoutLog.workoutScore = workoutScore
            workoutLog.notes = notes.isEmpty ? nil : notes
            workoutLog.detectedFromHealth = false
            
            // Delete old exercises
            if let oldExercises = workoutLog.exercises {
                for oldExercise in oldExercises {
                    modelContext.delete(oldExercise)
                }
            }
        } else {
            // Create new workout log
            workoutLog = WorkoutLog(
                dayDate: dayLog.date,
                tag: selectedTag,
                workoutScore: workoutScore,
                notes: notes.isEmpty ? nil : notes,
                detectedFromHealth: false
            )
            
            // Insert and save workout log first to get a persistent identifier
            modelContext.insert(workoutLog)
            dayLog.workoutLog = workoutLog
        }
        
        try? modelContext.save()

        // Add new exercises
        for exercise in exercises {
            let workoutExercise = WorkoutExercise(
                exerciseName: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                weightLbs: exercise.weight,
                notes: exercise.notes
            )
            workoutExercise.workoutLog = workoutLog
            modelContext.insert(workoutExercise)
        }
        
        // Save all changes
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

    @Binding var exercises: [ExerciseEntry]
    let modelContext: ModelContext?

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
                    exerciseSelectionSection
                    exerciseDetailsSection
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
    
    // MARK: - View Components
    
    private var exerciseSelectionSection: some View {
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
                customExerciseNameField
            } else {
                presetExerciseSelection
            }
        }
    }
    
    private var customExerciseNameField: some View {
        TextField("Exercise name", text: $exerciseName)
            .font(.body)
            .foregroundStyle(.primary)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .focused($isNameFocused)
    }
    
    private var presetExerciseSelection: some View {
        VStack(spacing: 12) {
            categoryTabs
            exerciseGrid
        }
    }
    
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(WorkoutExercise.CommonExercise.grouped.keys.sorted()), id: \.self) { category in
                    categoryButton(category)
                }
            }
        }
    }
    
    private func categoryButton(_ category: String) -> some View {
        Button(action: {
            selectedCategory = category
        }) {
            Text(category)
                .font(.subheadline)
                .foregroundColor(selectedCategory == category ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(categoryBackground(isSelected: selectedCategory == category))
        }
    }
    
    private func categoryBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? AppColors.primary : Color(white: 0.2))
            .overlay(
                Capsule()
                    .stroke(isSelected ? .clear : .white.opacity(0.1), lineWidth: 0.5)
            )
    }
    
    private var exerciseGrid: some View {
        let categoryExercises = WorkoutExercise.CommonExercise.grouped[selectedCategory] ?? []
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(categoryExercises, id: \.self) { exercise in
                exerciseButton(exercise)
            }
        }
    }
    
    private func exerciseButton(_ exercise: WorkoutExercise.CommonExercise) -> some View {
        Button(action: {
            exerciseName = exercise.rawValue
            loadPreviousSession(for: exercise.rawValue)
        }) {
            Text(exercise.rawValue)
                .font(.subheadline)
                .foregroundColor(exerciseName == exercise.rawValue ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(exerciseButtonBackground(isSelected: exerciseName == exercise.rawValue))
        }
    }
    
    private func exerciseButtonBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ?
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) :
                LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? .clear : .white.opacity(0.1), lineWidth: 0.5)
            )
    }
    
    private var exerciseDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                setsInput
                repsInput
            }
            
            weightInput
        }
    }
    
    private var setsInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sets")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper("\(sets)", value: $sets, in: 1...10)
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var repsInput: some View {
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
    
    private var weightInput: some View {
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
                            .fill(Color(white: 0.2))
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

    private func loadPreviousSession(for exerciseName: String) {
        guard let modelContext = modelContext else { return }
        
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
        guard let modelContext = modelContext else { return }
        
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
