//
//  WorkoutDetailSheet.swift
//  Dialed
//
//  View and manage past workouts with clear edit/delete options
//

import SwiftUI
import SwiftData
import PhotosUI
import HealthKit

struct WorkoutDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let workout: WorkoutLog
    let onDelete: (() -> Void)?
    let onUpdate: (() -> Void)?
    
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var selectedPhotoIndex: Int?
    @State private var showPhotoViewer = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showHealthLinkSheet = false
    
    // For edit - now using full WorkoutLogSheet
    @State private var dayLogForEdit: DayLog?
    
    // For Health linking
    @State private var linkedHealthWorkout: HealthKitManager.WorkoutData?
    @State private var isLoadingLinkedWorkout = false
    
    init(workout: WorkoutLog, onDelete: (() -> Void)? = nil, onUpdate: (() -> Void)? = nil) {
        self.workout = workout
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
    
    private var tagDisplay: String {
        if let tag = Constants.WorkoutTag(rawValue: workout.tag) {
            return tag.shortName
        }
        return workout.tag
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: workout.dayDate)
    }
    
    private var totalVolume: Double {
        guard let exercises = workout.exercises else { return 0 }
        return exercises.reduce(0) { $0 + $1.totalVolume }
    }
    
    private var totalSets: Int {
        guard let exercises = workout.exercises else { return 0 }
        return exercises.reduce(0) { $0 + $1.totalSets }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    headerCard
                    
                    // Action buttons - prominent and clear
                    actionButtons
                    
                    // Stats row
                    statsRow
                    
                    // Apple Health linking section
                    appleHealthSection
                    
                    // Photos section
                    photosSection
                    
                    // Exercises section
                    if let exercises = workout.exercises, !exercises.isEmpty {
                        exercisesSection(exercises: exercises)
                    }
                    
                    // Notes section
                    if let notes = workout.notes, !notes.isEmpty {
                        notesSection(notes: notes)
                    }
                    
                    // Danger zone
                    dangerZone
                }
                .padding()
                .padding(.bottom, 20)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let dayLog = dayLogForEdit {
                    WorkoutLogSheet(
                        dayLog: Binding(
                            get: { dayLog },
                            set: { self.dayLogForEdit = $0 }
                        ),
                        onSave: {
                            onUpdate?()
                        }
                    )
                }
            }
            .sheet(isPresented: $showHealthLinkSheet) {
                AppleHealthLinkSheet(
                    workout: workout,
                    onLink: { healthWorkout in
                        linkHealthWorkout(healthWorkout)
                    }
                )
            }
            .fullScreenCover(isPresented: $showPhotoViewer) {
                if let photos = workout.photos, !photos.isEmpty, let index = selectedPhotoIndex {
                    PhotoViewerSheet(
                        photos: photos,
                        initialIndex: index,
                        onDelete: { photo in
                            deletePhoto(photo)
                        }
                    )
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let item = newItem {
                    loadAndSavePhoto(from: item)
                }
            }
            .alert("Delete Workout?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteWorkout()
                }
            } message: {
                Text("This will delete this workout from the Dialed app only. Your Apple Health/Fitness data will not be affected.")
            }
            .task {
                await loadLinkedHealthWorkout()
            }
        }
        .presentationDetents([.large])
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 16) {
            // Date and type
            VStack(spacing: 8) {
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(tagDisplay)
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                }
            }
            
            // Quality rating
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= workout.workoutScore ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundColor(index <= workout.workoutScore ? .yellow : Color.secondary.opacity(0.3))
                }
            }
            
            Text(qualityLabel(for: workout.workoutScore))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .elevatedGlassCard(cornerRadius: 20, padding: 20)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Edit button - prominent
            Button(action: {
                prepareForEdit()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.body.bold())
                    Text("Edit Workout")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
            }
            
            // Add Photo button
            Button(action: {
                showPhotoPicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.body.bold())
                    Text("Add Photo")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.purple.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    // MARK: - Stats Row
    
    private var statsRow: some View {
        HStack(spacing: 12) {
            // Duration
            StatCard(
                icon: "clock.fill",
                iconColors: [.blue, .cyan],
                value: workout.durationMinutes != nil ? "\(workout.durationMinutes!)" : "--",
                unit: "min",
                label: "Duration"
            )
            
            // Calories
            StatCard(
                icon: "flame.fill",
                iconColors: [.orange, .red],
                value: workout.caloriesBurned != nil ? "\(workout.caloriesBurned!)" : "--",
                unit: "cal",
                label: "Burned"
            )
            
            // Volume
            StatCard(
                icon: "scalemass.fill",
                iconColors: [.purple, .pink],
                value: totalVolume > 0 ? formatVolume(totalVolume) : "--",
                unit: "lbs",
                label: "Volume"
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
                
                if workout.isLinkedToHealth {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text("Linked")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                }
            }
            
            if isLoadingLinkedWorkout {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.secondary)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if workout.isLinkedToHealth {
                // Show linked workout info
                if let healthWorkout = linkedHealthWorkout {
                    LinkedHealthWorkoutCard(
                        healthWorkout: healthWorkout,
                        onUnlink: {
                            unlinkHealthWorkout()
                        }
                    )
                } else {
                    // Linked but couldn't load - maybe deleted from Health
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Linked workout not found in Apple Health")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button(action: {
                            unlinkHealthWorkout()
                        }) {
                            Text("Remove Link")
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
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
                            
                            Text("Connect with an Apple Fitness workout")
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
    
    // MARK: - Health Link Helpers
    
    private func loadLinkedHealthWorkout() async {
        guard let healthID = workout.healthKitWorkoutID else { return }
        
        isLoadingLinkedWorkout = true
        defer { isLoadingLinkedWorkout = false }
        
        do {
            linkedHealthWorkout = try await HealthKitManager.shared.fetchWorkout(byID: healthID)
        } catch {
            print("Failed to load linked health workout: \(error)")
        }
    }
    
    private func linkHealthWorkout(_ healthWorkout: HealthKitManager.WorkoutData) {
        workout.healthKitWorkoutID = healthWorkout.id.uuidString
        workout.healthKitWorkoutType = healthWorkout.workoutTypeName
        workout.detectedFromHealth = true
        
        // Update stats if they were missing
        if workout.durationMinutes == nil {
            workout.durationMinutes = healthWorkout.durationMinutes
        }
        if workout.caloriesBurned == nil {
            workout.caloriesBurned = healthWorkout.caloriesBurned
        }
        if workout.startTime == nil {
            workout.startTime = healthWorkout.startDate
        }
        if workout.endTime == nil {
            workout.endTime = healthWorkout.endDate
        }
        
        try? modelContext.save()
        linkedHealthWorkout = healthWorkout
        onUpdate?()
    }
    
    private func unlinkHealthWorkout() {
        workout.healthKitWorkoutID = nil
        workout.detectedFromHealth = false
        
        try? modelContext.save()
        linkedHealthWorkout = nil
        onUpdate?()
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
                
                if let photos = workout.photos, !photos.isEmpty {
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let photos = workout.photos, !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            Button(action: {
                                selectedPhotoIndex = index
                                showPhotoViewer = true
                            }) {
                                PhotoThumbnail(
                                    photo: photo,
                                    onDelete: {
                                        deletePhoto(photo)
                                    }
                                )
                            }
                        }
                        
                        // Add photo button
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
                }
            } else {
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
    
    // MARK: - Exercises Section
    
    private func exercisesSection(exercises: [WorkoutExercise]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(exercises.count) exercises • \(totalSets) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 10) {
                ForEach(exercises, id: \.id) { exercise in
                    ExerciseDetailCard(exercise: exercise)
                }
            }
        }
    }
    
    // MARK: - Notes Section
    
    private func notesSection(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text(notes)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    
    // MARK: - Danger Zone
    
    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            Button(action: {
                showDeleteConfirmation = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.body)
                    Text("Delete Workout")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.red.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            
            Text("Deleting only removes from Dialed. Apple Health data is not affected.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helpers
    
    private func qualityLabel(for score: Int) -> String {
        switch score {
        case 1: return "Poor workout"
        case 2: return "Fair workout"
        case 3: return "Good workout"
        case 4: return "Great workout"
        case 5: return "Perfect workout"
        default: return ""
        }
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
    
    private func prepareForEdit() {
        let targetDate = Calendar.current.startOfDay(for: workout.dayDate)
        let fetchDescriptor = FetchDescriptor<DayLog>(
            predicate: #Predicate { $0.date == targetDate }
        )
        
        if let existingDayLog = try? modelContext.fetch(fetchDescriptor).first {
            // Make sure the workoutLog relationship is set
            if existingDayLog.workoutLog == nil {
                existingDayLog.workoutLog = workout
                try? modelContext.save()
            }
            dayLogForEdit = existingDayLog
            showEditSheet = true
        } else {
            // Create a new DayLog if one doesn't exist
            let newDayLog = DayLog(date: targetDate)
            newDayLog.workoutLog = workout
            newDayLog.workoutTag = workout.tag
            newDayLog.workoutScore = workout.workoutScore
            newDayLog.workoutDurationMinutes = workout.durationMinutes
            newDayLog.workoutCaloriesBurned = workout.caloriesBurned
            newDayLog.workoutDetectedFromHealth = workout.detectedFromHealth
            modelContext.insert(newDayLog)
            try? modelContext.save()
            dayLogForEdit = newDayLog
            showEditSheet = true
        }
    }
    
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
            photo.workoutLog = workout
            photo.capturedAt = workout.dayDate // Use workout date, not current date
            
            await MainActor.run {
                modelContext.insert(photo)
                try? modelContext.save()
                selectedPhotoItem = nil
            }
        }
    }
    
    private func deletePhoto(_ photo: WorkoutPhoto) {
        // Delete the photo file from disk
        _ = PhotoManager.shared.deletePhoto(filename: photo.filename)
        
        // Delete from model context
        modelContext.delete(photo)
        try? modelContext.save()
    }
    
    private func deleteWorkout() {
        // Delete all exercises and sets first
        if let exercises = workout.exercises {
            for exercise in exercises {
                if let sets = exercise.workoutSets {
                    for set in sets {
                        modelContext.delete(set)
                    }
                }
                modelContext.delete(exercise)
            }
        }
        
        // Delete photos (files and records)
        if let photos = workout.photos {
            for photo in photos {
                _ = PhotoManager.shared.deletePhoto(filename: photo.filename)
                modelContext.delete(photo)
            }
        }
        
        // Delete the workout
        modelContext.delete(workout)
        
        try? modelContext.save()
        
        onDelete?()
        dismiss()
    }
}

// MARK: - Photo Thumbnail

private struct PhotoThumbnail: View {
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

// MARK: - Photo Viewer Sheet

struct PhotoViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let photos: [WorkoutPhoto]
    let initialIndex: Int
    var onDelete: ((WorkoutPhoto) -> Void)?
    
    @State private var currentIndex: Int
    @State private var images: [UUID: UIImage] = [:]
    @State private var failedImages: Set<UUID> = []
    @State private var loadingImages: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    
    init(photos: [WorkoutPhoto], initialIndex: Int, onDelete: ((WorkoutPhoto) -> Void)? = nil) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDelete = onDelete
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if photos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No photos")
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        ZStack {
                            if let image = images[photo.id] {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if failedImages.contains(photo.id) {
                                // Error state with retry
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.red.opacity(0.7))
                                    
                                    Text("Image not found")
                                        .font(.headline)
                                        .foregroundStyle(.white.opacity(0.8))
                                    
                                    Text("The photo file may have been moved or deleted")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                    
                                    Button(action: {
                                        retryLoadImage(for: photo)
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Retry")
                                        }
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(.white.opacity(0.2))
                                        )
                                    }
                                }
                                .padding()
                            } else {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(1.2)
                                    Text("Loading...")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                        .tag(index)
                        .onAppear {
                            loadImage(for: photo)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
            
            // Header and controls
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    if !photos.isEmpty {
                        Text("\(currentIndex + 1) of \(photos.count)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Delete button
                    if onDelete != nil && photos.indices.contains(currentIndex) {
                        Button(action: { showDeleteConfirmation = true }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    } else {
                        Circle()
                            .fill(.clear)
                            .frame(width: 28, height: 28)
                    }
                }
                .padding()
                
                Spacer()
                
                // Photo info
                if photos.indices.contains(currentIndex) && !failedImages.contains(photos[currentIndex].id) {
                    VStack(spacing: 8) {
                        Text(formatDate(photos[currentIndex].capturedAt))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                        
                        if let notes = photos[currentIndex].notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial.opacity(0.7))
                    .cornerRadius(16)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 80)
                }
            }
        }
        .alert("Delete Photo?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCurrentPhoto()
            }
        } message: {
            Text("This photo will be permanently deleted.")
        }
        .task {
            // Pre-load all images
            for photo in photos {
                loadImage(for: photo)
            }
        }
    }
    
    private func loadImage(for photo: WorkoutPhoto) {
        guard images[photo.id] == nil && !loadingImages.contains(photo.id) && !failedImages.contains(photo.id) else { return }
        
        loadingImages.insert(photo.id)
        
        Task.detached(priority: .userInitiated) {
            let loadedImage = PhotoManager.shared.loadPhoto(filename: photo.filename)
            await MainActor.run {
                loadingImages.remove(photo.id)
                if let img = loadedImage {
                    images[photo.id] = img
                    failedImages.remove(photo.id)
                } else {
                    failedImages.insert(photo.id)
                }
            }
        }
    }
    
    private func retryLoadImage(for photo: WorkoutPhoto) {
        failedImages.remove(photo.id)
        loadImage(for: photo)
    }
    
    private func deleteCurrentPhoto() {
        guard photos.indices.contains(currentIndex) else { return }
        let photoToDelete = photos[currentIndex]
        
        // Delete the photo file
        _ = PhotoManager.shared.deletePhoto(filename: photoToDelete.filename)
        
        // Call the onDelete callback
        onDelete?(photoToDelete)
        
        // Dismiss if no more photos
        if photos.count <= 1 {
            dismiss()
        } else if currentIndex >= photos.count - 1 {
            currentIndex = max(0, currentIndex - 1)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let iconColors: [Color]
    let value: String
    let unit: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(
                    LinearGradient(
                        colors: iconColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                
                if value != "--" {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 14, padding: 12)
    }
}

// MARK: - Exercise Detail Card

private struct ExerciseDetailCard: View {
    let exercise: WorkoutExercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(exercise.exerciseName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(exercise.setsDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Sets
            if let sets = exercise.workoutSets, !sets.isEmpty {
                VStack(spacing: 6) {
                    ForEach(sets.sorted { $0.setNumber < $1.setNumber }, id: \.id) { set in
                        SetDetailRow(set: set)
                    }
                }
            }
            
            // Summary stats
            HStack(spacing: 16) {
                if let topSet = exercise.topSet {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("Top: \(Int(topSet.weightLbs)) × \(topSet.reps)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if exercise.totalVolume > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "scalemass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Vol: \(Int(exercise.totalVolume)) lbs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Notes
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
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

// MARK: - Set Detail Row

private struct SetDetailRow: View {
    let set: WorkoutSet
    
    var body: some View {
        HStack(spacing: 12) {
            // Set number
            Text("\(set.setNumber)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            // Warmup indicator
            if set.isWarmup {
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
            Text("\(Int(set.weightLbs)) lbs × \(set.reps)")
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // RPE
            if let rpe = set.rpe {
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
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Linked Health Workout Card

private struct LinkedHealthWorkoutCard: View {
    let healthWorkout: HealthKitManager.WorkoutData
    let onUnlink: () -> Void
    
    @State private var showUnlinkConfirmation = false
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: healthWorkout.startDate)
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
        VStack(spacing: 12) {
            // Workout info
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.red, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: healthWorkout.workoutTypeIcon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(healthWorkout.workoutTypeName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    
                    HStack(spacing: 8) {
                        Text(formattedTime)
                        Text("•")
                        Text(formattedDuration)
                        if let cals = healthWorkout.caloriesBurned {
                            Text("•")
                            Text("\(cals) cal")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    if let source = healthWorkout.sourceName {
                        Text("from \(source)")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                }
                
                Spacer()
            }
            
            // Unlink button
            Button(action: {
                showUnlinkConfirmation = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "link.badge.plus")
                        .rotationEffect(.degrees(45))
                    Text("Unlink")
                }
                .font(.caption.bold())
                .foregroundStyle(.red.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.red.opacity(0.1))
                )
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
        .alert("Unlink from Apple Health?", isPresented: $showUnlinkConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unlink", role: .destructive) {
                onUnlink()
            }
        } message: {
            Text("This will remove the connection to this Apple Health workout. The workout data in Dialed will remain, but it won't sync with Apple Health anymore.")
        }
    }
}

// MARK: - Apple Health Link Sheet

struct AppleHealthLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let workout: WorkoutLog
    let onLink: (HealthKitManager.WorkoutData) -> Void
    
    @State private var healthWorkouts: [HealthKitManager.WorkoutData] = []
    @State private var linkedWorkoutIDs: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    // Filter out already-linked workouts (except the current workout if re-linking)
    private var availableWorkouts: [HealthKitManager.WorkoutData] {
        healthWorkouts.filter { healthWorkout in
            let workoutIDString = healthWorkout.id.uuidString
            // Allow the current workout's linked health workout to still be shown
            if workout.healthKitWorkoutID == workoutIDString {
                return true
            }
            return !linkedWorkoutIDs.contains(workoutIDString)
        }
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
                            Text("All workouts from this day have already been linked to other entries.")
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
                                
                                if !linkedWorkoutIDs.isEmpty && linkedWorkoutIDs.count > (availableWorkouts.count < healthWorkouts.count ? 0 : 1) {
                                    Text("\(linkedWorkoutIDs.count) workout(s) already linked to other entries")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            
                            // Workout list
                            ForEach(availableWorkouts, id: \.id) { healthWorkout in
                                HealthWorkoutRow(
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
        
        do {
            healthWorkouts = try await HealthKitManager.shared.fetchWorkouts(for: workout.dayDate)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Health Workout Row

private struct HealthWorkoutRow: View {
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
    let workout = WorkoutLog(
        dayDate: Date().addingTimeInterval(-86400),
        tag: Constants.WorkoutTag.push,
        workoutScore: 4
    )
    workout.durationMinutes = 65
    workout.caloriesBurned = 420
    
    return WorkoutDetailSheet(workout: workout)
}
