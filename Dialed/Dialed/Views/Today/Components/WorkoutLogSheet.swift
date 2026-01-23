//
//  WorkoutLogSheet.swift
//  Dialed
//
//  Comprehensive workout logging with set-by-set tracking
//

import SwiftUI
import SwiftData
import PhotosUI

struct WorkoutLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var dayLog: DayLog
    let onSave: () -> Void

    @Query(
        filter: #Predicate<CustomWorkoutType> { $0.isEnabled },
        sort: \CustomWorkoutType.createdAt
    ) private var customWorkoutTypes: [CustomWorkoutType]

    @Query(sort: \WorkoutTemplate.lastUsedAt, order: .reverse) private var templates: [WorkoutTemplate]

    @State private var selectedTag: Constants.WorkoutTag = .push
    @State private var selectedCustomType: CustomWorkoutType?
    @State private var workoutScore: Int = 3
    @State private var notes: String = ""
    @State private var exercises: [ExerciseEntry] = []
    @State private var showAddExercise = false
    @State private var showPhotoPrompt = false
    @State private var savedWorkoutLog: WorkoutLog?
    @State private var showTemplates = false
    @State private var showSaveAsTemplate = false
    
    // Photo management
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoViewer = false
    @State private var selectedPhotoIndex: Int?
    @State private var workoutPhotos: [WorkoutPhoto] = []
    
    // Apple Health linking
    @State private var showHealthLinkSheet = false
    @State private var linkedHealthWorkout: HealthKitManager.WorkoutData?
    @State private var healthWorkoutID: String?
    @State private var durationMinutes: Int?
    @State private var caloriesBurned: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Workout Type Selection
                    workoutTypeSection

                    // Quality Rating
                    qualityRatingSection
                    
                    // Apple Health linking
                    appleHealthSection

                    // Exercises Section
                    exercisesSection
                    
                    // Photos Section
                    photosSection

                    // Notes
                    notesSection
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(dayLog.workoutLog != nil ? "Edit Workout" : "Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Menu {
                        Button(action: { showTemplates = true }) {
                            Label("Load Template", systemImage: "doc.fill")
                        }

                        if !exercises.isEmpty {
                            Button(action: { showSaveAsTemplate = true }) {
                                Label("Save as Template", systemImage: "square.and.arrow.down")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.blue)
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
            .sheet(isPresented: $showTemplates) {
                TemplatePickerSheet(
                    templates: templates,
                    onSelect: { template in
                        loadTemplate(template)
                    },
                    modelContext: modelContext
                )
            }
            .sheet(isPresented: $showSaveAsTemplate) {
                SaveAsTemplateSheet(
                    exercises: exercises,
                    workoutTag: selectedCustomType?.name ?? selectedTag.rawValue,
                    notes: notes,
                    modelContext: modelContext
                )
            }
            .fullScreenCover(isPresented: $showPhotoViewer) {
                if !workoutPhotos.isEmpty, let index = selectedPhotoIndex {
                    PhotoViewerSheet(
                        photos: workoutPhotos,
                        initialIndex: index,
                        onDelete: { photo in
                            deletePhoto(photo)
                        }
                    )
                }
            }
            .sheet(isPresented: $showHealthLinkSheet) {
                HealthWorkoutPickerSheet(
                    date: dayLog.date,
                    modelContext: modelContext,
                    onLink: { healthWorkout in
                        linkHealthWorkout(healthWorkout)
                    }
                )
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let item = newItem {
                    loadAndSavePhoto(from: item)
                }
            }
            .onAppear {
                loadExistingWorkout()
            }
            .alert("Add Progress Photo?", isPresented: $showPhotoPrompt) {
                Button("Take Photo") {
                    // Show photo capture
                    if savedWorkoutLog != nil {
                        // Will be handled by TodayView through notification
                        Task {
                            await NotificationManager.shared.sendWorkoutPhotoReminder()
                        }
                    }
                    dismiss()
                }
                Button("Later") {
                    dismiss()
                }
            } message: {
                Text("Document your progress with a photo")
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
                    let setData = (exercise.workoutSets ?? []).map { workoutSet in
                        ExerciseEntry.SetData(
                            reps: workoutSet.reps,
                            weightLbs: workoutSet.weightLbs,
                            restSeconds: workoutSet.restSeconds,
                            notes: workoutSet.notes,
                            isWarmup: workoutSet.isWarmup,
                            rpe: workoutSet.rpe
                        )
                    }
                    return ExerciseEntry(
                        name: exercise.exerciseName,
                        sets: setData,
                        notes: exercise.notes,
                        previousSession: nil
                    )
                }
            }
            
            // Load photos
            if let photos = workoutLog.photos {
                workoutPhotos = photos
            }
            
            // Load Apple Health link data
            healthWorkoutID = workoutLog.healthKitWorkoutID
            durationMinutes = workoutLog.durationMinutes
            caloriesBurned = workoutLog.caloriesBurned
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
                    // Built-in types (filtered by preferences)
                    let prefs = WorkoutTypePreferences.load()
                    ForEach(Constants.WorkoutTag.allCases, id: \.self) { tag in
                        if prefs.enabledBuiltInTypes.contains(tag.rawValue) {
                            workoutTagButton(tag)
                        }
                    }

                    // Custom types
                    ForEach(customWorkoutTypes) { customType in
                        customWorkoutTagButton(customType)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func workoutTagButton(_ tag: Constants.WorkoutTag) -> some View {
        Button(action: {
            selectedTag = tag
            selectedCustomType = nil
        }) {
            Text(tag.shortName)
                .font(.subheadline.bold())
                .foregroundColor(selectedTag == tag && selectedCustomType == nil ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(workoutTagBackground(isSelected: selectedTag == tag && selectedCustomType == nil))
        }
    }

    private func customWorkoutTagButton(_ customType: CustomWorkoutType) -> some View {
        Button(action: {
            selectedCustomType = customType
        }) {
            HStack(spacing: 6) {
                Image(systemName: customType.icon)
                    .font(.caption)
                Text(customType.shortName)
                    .font(.subheadline.bold())
            }
            .foregroundColor(selectedCustomType?.id == customType.id ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(customWorkoutTagBackground(
                isSelected: selectedCustomType?.id == customType.id,
                colorHex: customType.colorHex
            ))
        }
    }

    private func customWorkoutTagBackground(isSelected: Bool, colorHex: String) -> some View {
        let color = Color(hex: colorHex)
        return Capsule()
            .fill(isSelected ?
                LinearGradient(
                    colors: [color, color.opacity(0.8)],
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
            .shadow(color: isSelected ? color.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
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
                ExerciseCard(
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
    
    // MARK: - Apple Health Section
    
    private var appleHealthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("Apple Health")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if healthWorkoutID != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text("Linked")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                }
            }
            
            if healthWorkoutID != nil {
                // Show linked workout info
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.red, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Apple Fitness Workout")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        
                        HStack(spacing: 8) {
                            if let duration = durationMinutes {
                                Text("\(duration) min")
                                    .font(.caption)
                            }
                            if let calories = caloriesBurned {
                                Text("\(calories) cal")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Unlink button
                    Button(action: unlinkHealthWorkout) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.red.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.red.opacity(0.15), lineWidth: 1)
                        )
                )
            } else {
                // Not linked - show option to link
                Button(action: {
                    showHealthLinkSheet = true
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.1))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "heart.fill")
                                .font(.body)
                                .foregroundStyle(.red)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link to Apple Health")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            
                            Text("Sync duration, calories from Apple Fitness")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.red.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.red.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Photos Section
    
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Progress Photos")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !workoutPhotos.isEmpty {
                    Text("\(workoutPhotos.count) photo\(workoutPhotos.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if !workoutPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(workoutPhotos.enumerated()), id: \.element.id) { index, photo in
                            Button(action: {
                                selectedPhotoIndex = index
                                showPhotoViewer = true
                            }) {
                                WorkoutPhotoThumbnail(
                                    photo: photo,
                                    onDelete: {
                                        deletePhoto(photo)
                                    }
                                )
                            }
                        }
                        
                        // Add photo button
                        addPhotoButton
                    }
                }
            } else {
                // Empty state with add button
                Button(action: {
                    showPhotoPicker = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        
                        Text("Add Progress Photo")
                            .font(.subheadline.bold())
                            .foregroundStyle(.purple)
                        
                        Text("Document your progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.purple.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.purple.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }
    
    private var addPhotoButton: some View {
        Button(action: {
            showPhotoPicker = true
        }) {
            VStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
            }
            .frame(width: 100, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.purple.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.purple.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Apple Health Helpers
    
    private func linkHealthWorkout(_ healthWorkout: HealthKitManager.WorkoutData) {
        healthWorkoutID = healthWorkout.id.uuidString
        durationMinutes = healthWorkout.durationMinutes
        caloriesBurned = healthWorkout.caloriesBurned
        linkedHealthWorkout = healthWorkout
    }
    
    private func unlinkHealthWorkout() {
        healthWorkoutID = nil
        durationMinutes = nil
        caloriesBurned = nil
        linkedHealthWorkout = nil
    }
    
    // MARK: - Photo Helpers
    
    private func loadAndSavePhoto(from item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                return
            }
            
            // Save to disk
            guard let filename = PhotoManager.shared.savePhoto(uiImage) else {
                return
            }
            
            // Create WorkoutPhoto record
            let photo = WorkoutPhoto(filename: filename)
            photo.capturedAt = dayLog.date
            
            // If we're editing an existing workout, link the photo
            if let workoutLog = dayLog.workoutLog {
                photo.workoutLog = workoutLog
                modelContext.insert(photo)
                try? modelContext.save()
            }
            
            await MainActor.run {
                workoutPhotos.append(photo)
                selectedPhotoItem = nil
            }
        }
    }
    
    private func deletePhoto(_ photo: WorkoutPhoto) {
        // Delete the photo file from disk
        _ = PhotoManager.shared.deletePhoto(filename: photo.filename)
        
        // Remove from local array
        workoutPhotos.removeAll { $0.id == photo.id }
        
        // Delete from model context if it's persisted
        modelContext.delete(photo)
        try? modelContext.save()
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
        // Get workout tag
        let workoutTag = selectedCustomType?.name ?? selectedTag.rawValue

        // Capture the date as a local variable for the Predicate
        let targetDate = dayLog.date

        // Fetch or create WorkoutLog in the current context
        let workoutLog: WorkoutLog
        let fetchDescriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate { $0.dayDate == targetDate }
        )

        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            // Update existing workout
            workoutLog = existing
            workoutLog.tag = workoutTag
            workoutLog.workoutScore = workoutScore
            workoutLog.notes = notes.isEmpty ? nil : notes
            workoutLog.detectedFromHealth = healthWorkoutID != nil
            
            // Update Apple Health link data
            workoutLog.healthKitWorkoutID = healthWorkoutID
            workoutLog.durationMinutes = durationMinutes
            workoutLog.caloriesBurned = caloriesBurned

            // Delete old exercises and their sets
            if let oldExercises = workoutLog.exercises {
                for oldExercise in oldExercises {
                    // Delete sets first
                    if let oldSets = oldExercise.workoutSets {
                        for oldSet in oldSets {
                            modelContext.delete(oldSet)
                        }
                    }
                    modelContext.delete(oldExercise)
                }
            }
        } else {
            // Create new workout log
            workoutLog = WorkoutLog(
                dayDate: dayLog.date,
                tag: workoutTag,
                workoutScore: workoutScore,
                notes: notes.isEmpty ? nil : notes,
                detectedFromHealth: healthWorkoutID != nil
            )
            
            // Set Apple Health link data
            workoutLog.healthKitWorkoutID = healthWorkoutID
            workoutLog.durationMinutes = durationMinutes
            workoutLog.caloriesBurned = caloriesBurned

            // Insert new workout log
            modelContext.insert(workoutLog)
        }

        // Save to ensure workoutLog has a persistent identifier before adding exercises
        try? modelContext.save()

        // Add exercises with sets
        for exercise in exercises {
            let workoutExercise = WorkoutExercise(
                exerciseName: exercise.name,
                notes: exercise.notes
            )
            // Establish relationship before inserting
            workoutExercise.workoutLog = workoutLog
            modelContext.insert(workoutExercise)

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
                // Establish relationship before inserting
                workoutSet.exercise = workoutExercise
                modelContext.insert(workoutSet)
            }
        }

        // Link any photos that were added during this session
        for photo in workoutPhotos {
            if photo.workoutLog == nil {
                photo.workoutLog = workoutLog
                modelContext.insert(photo)
            }
        }
        
        // CRITICAL: Establish the relationship between DayLog and WorkoutLog
        dayLog.workoutLog = workoutLog
        
        // Sync DayLog fields with workout data for quick access
        dayLog.workoutTag = workoutTag
        dayLog.workoutScore = workoutScore
        dayLog.workoutDurationMinutes = workoutLog.durationMinutes
        dayLog.workoutCaloriesBurned = workoutLog.caloriesBurned
        dayLog.workoutDetectedFromHealth = workoutLog.detectedFromHealth

        // Final save to persist exercises, sets, photos, and relationships
        try? modelContext.save()

        onSave()

        // Save workout log reference and show photo prompt only if no photos were added
        savedWorkoutLog = workoutLog
        if workoutPhotos.isEmpty {
            showPhotoPrompt = true
        } else {
            dismiss()
        }
    }

    private func loadTemplate(_ template: WorkoutTemplate) {
        // Set workout tag if template has one
        if let tag = template.workoutTag,
           let workoutTag = Constants.WorkoutTag(rawValue: tag) {
            selectedTag = workoutTag
            selectedCustomType = nil
        }

        // Load notes
        notes = template.notes ?? ""

        // Load exercises
        let templateExercises = (template.templateExercises ?? []).sorted { $0.orderIndex < $1.orderIndex }
        exercises = templateExercises.map { templateExercise in
            let sets = (templateExercise.templateSets ?? [])
                .sorted { $0.setNumber < $1.setNumber }
                .map { templateSet in
                    ExerciseEntry.SetData(
                        reps: templateSet.reps,
                        weightLbs: templateSet.weightLbs,
                        restSeconds: templateSet.restSeconds,
                        notes: templateSet.notes,
                        isWarmup: templateSet.isWarmup,
                        rpe: nil
                    )
                }

            return ExerciseEntry(
                name: templateExercise.exerciseName,
                sets: sets,
                notes: templateExercise.notes,
                previousSession: nil
            )
        }

        // Update template's last used date
        template.lastUsedAt = Date()
        try? modelContext.save()
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
                            },
                            onDuplicate: {
                                // Create a copy of the current set
                                let duplicatedSet = ExerciseEntry.SetData(
                                    reps: exercise.sets[index].reps,
                                    weightLbs: exercise.sets[index].weightLbs,
                                    restSeconds: exercise.sets[index].restSeconds,
                                    notes: exercise.sets[index].notes,
                                    isWarmup: exercise.sets[index].isWarmup,
                                    rpe: exercise.sets[index].rpe
                                )
                                // Insert right after the current set
                                exercise.sets.insert(duplicatedSet, at: index + 1)
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
    let onDuplicate: () -> Void

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

            // Duplicate
            Button(action: onDuplicate) {
                Image(systemName: "plus.square.on.square")
                    .font(.caption)
                    .foregroundColor(.blue)
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

    @Binding var exercises: [ExerciseEntry]
    let modelContext: ModelContext?

    @State private var exerciseName: String = ""
    @State private var selectedCategory: String = "Chest"
    @State private var useCustomName = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    exerciseSelectionSection
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
    
    private func addExercise() {
        guard let modelContext = modelContext else { return }
        
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

// MARK: - Template Picker Sheet

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let templates: [WorkoutTemplate]
    let onSelect: (WorkoutTemplate) -> Void
    let modelContext: ModelContext

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.5))

                        Text("No Templates Yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Create a template by logging a workout and selecting 'Save as Template'")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(templates) { template in
                        Button(action: {
                            onSelect(template)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(template.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if let tag = template.workoutTag {
                                        Text(tag)
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(.blue.opacity(0.15))
                                            )
                                    }
                                }

                                if let exercises = template.templateExercises, !exercises.isEmpty {
                                    Text("\(exercises.count) exercises")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let lastUsed = template.lastUsedAt {
                                    Text("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(template)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workout Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Save As Template Sheet

struct SaveAsTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercises: [ExerciseEntry]
    let workoutTag: String
    let notes: String
    let modelContext: ModelContext

    @State private var templateName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template Name", text: $templateName)
                        .autocorrectionDisabled()
                } header: {
                    Text("Template Name")
                } footer: {
                    Text("Give this workout template a memorable name (e.g., 'Push Day A', 'Full Body', 'Leg Day')")
                }

                Section {
                    HStack {
                        Text("Workout Type")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(workoutTag)
                            .foregroundStyle(.primary)
                    }

                    HStack {
                        Text("Exercises")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(exercises.count)")
                            .foregroundStyle(.primary)
                    }

                    ForEach(exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("\(exercise.sets.count) sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Template Preview")
                }
            }
            .navigationTitle("Save as Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(templateName.isEmpty)
                }
            }
        }
    }

    private func saveTemplate() {
        let template = WorkoutTemplate(
            name: templateName,
            workoutTag: workoutTag,
            notes: notes.isEmpty ? nil : notes
        )

        modelContext.insert(template)

        // Add exercises
        for (index, exercise) in exercises.enumerated() {
            let templateExercise = TemplateExercise(
                exerciseName: exercise.name,
                notes: exercise.notes,
                orderIndex: index
            )
            templateExercise.template = template
            modelContext.insert(templateExercise)

            // Add sets
            for setData in exercise.sets {
                let templateSet = TemplateSet(
                    setNumber: setData.id.hashValue, // Using hash as set number
                    reps: setData.reps,
                    weightLbs: setData.weightLbs,
                    restSeconds: setData.restSeconds,
                    notes: setData.notes,
                    isWarmup: setData.isWarmup
                )
                templateSet.exercise = templateExercise
                modelContext.insert(templateSet)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Workout Photo Thumbnail

private struct WorkoutPhotoThumbnail: View {
    let photo: WorkoutPhoto
    var onDelete: (() -> Void)?
    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if loadFailed {
                // Error state
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.red.opacity(0.6))
                            Text("Not found")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay(
                        ProgressView()
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(loadFailed ? .red.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
        )
        .contextMenu {
            if onDelete != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete Photo?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This photo will be permanently deleted.")
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedImage = PhotoManager.shared.loadPhoto(filename: photo.filename)
            DispatchQueue.main.async {
                if let loadedImage = loadedImage {
                    image = loadedImage
                } else {
                    loadFailed = true
                }
            }
        }
    }
}

// MARK: - Health Workout Picker Sheet

struct HealthWorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let date: Date
    let modelContext: ModelContext
    let onLink: (HealthKitManager.WorkoutData) -> Void
    
    @State private var healthWorkouts: [HealthKitManager.WorkoutData] = []
    @State private var linkedWorkoutIDs: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // Filter out already-linked workouts
    private var availableWorkouts: [HealthKitManager.WorkoutData] {
        healthWorkouts.filter { !linkedWorkoutIDs.contains($0.id.uuidString) }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.red)
                        Text("Loading Apple Health workouts...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        
                        Text("Unable to Load Workouts")
                            .font(.headline)
                        
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Try Again") {
                            Task {
                                await loadWorkouts()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else if availableWorkouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.5))
                        
                        Text("No Workouts Available")
                            .font(.headline)
                        
                        if healthWorkouts.isEmpty {
                            Text("No Apple Health workouts were recorded on this day.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("All workouts from this day have already been linked.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select a workout to link")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Text("Linking will sync duration, calories, and other data from Apple Health.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.8))
                                
                                if !linkedWorkoutIDs.isEmpty {
                                    Text("\(linkedWorkoutIDs.count) workout(s) already linked to other entries")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            
                            // Workout list
                            ForEach(availableWorkouts, id: \.id) { healthWorkout in
                                HealthWorkoutPickerRow(
                                    healthWorkout: healthWorkout,
                                    onSelect: {
                                        onLink(healthWorkout)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Link Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadWorkouts()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func loadWorkouts() async {
        isLoading = true
        errorMessage = nil
        
        // Fetch all WorkoutLogs to check which health workouts are already linked
        let fetchDescriptor = FetchDescriptor<WorkoutLog>()
        if let allWorkouts = try? modelContext.fetch(fetchDescriptor) {
            linkedWorkoutIDs = Set(allWorkouts.compactMap { $0.healthKitWorkoutID })
        }
        
        // Fetch health workouts for this date
        do {
            healthWorkouts = try await HealthKitManager.shared.fetchWorkouts(for: date)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Health Workout Picker Row

private struct HealthWorkoutPickerRow: View {
    let healthWorkout: HealthKitManager.WorkoutData
    let onSelect: () -> Void
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: healthWorkout.startDate)
        let end = formatter.string(from: healthWorkout.endDate)
        return "\(start) - \(end)"
    }
    
    private var formattedDuration: String {
        let hours = healthWorkout.durationMinutes / 60
        let minutes = healthWorkout.durationMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Workout icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.red, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: healthWorkout.workoutTypeIcon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                // Workout details
                VStack(alignment: .leading, spacing: 4) {
                    Text(healthWorkout.workoutTypeName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(formattedDuration)
                        }
                        
                        if let cals = healthWorkout.caloriesBurned {
                            HStack(spacing: 4) {
                                Image(systemName: "flame")
                                    .font(.caption2)
                                Text("\(cals) cal")
                            }
                        }
                        
                        if let distance = healthWorkout.distance, distance > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.walk")
                                    .font(.caption2)
                                Text(String(format: "%.1f mi", distance / 1609.34))
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Select indicator
                VStack {
                    Image(systemName: "link.circle")
                        .font(.title2)
                        .foregroundStyle(.red)
                    
                    Text("Link")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    @Previewable @State var dayLog = DayLog(date: Date())
    WorkoutLogSheet(dayLog: $dayLog, onSave: {})
}
