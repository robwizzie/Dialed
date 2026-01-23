//
//  DaySummarySheet.swift
//  Dialed
//
//  Shows a summary of a selected day from the calendar
//

import SwiftUI
import SwiftData
import PhotosUI

struct DaySummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let date: Date
    let dayLog: DayLog?
    
    @State private var showWorkoutDetail = false
    @State private var showWorkoutEdit = false
    @State private var dayLogBinding: DayLog?
    @State private var photos: [WorkoutPhoto] = []
    @State private var selectedPhotoIndex: Int?
    @State private var showPhotoViewer = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
    
    private var score: Int {
        dayLog?.dailyScoreFinal ?? dayLog?.dailyScoreProvisional ?? 0
    }
    
    private var scoreGrade: String {
        AppColors.scoreGrade(for: score)
    }
    
    private var scoreColor: Color {
        AppColors.scoreColor(for: score)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Score header
                    scoreHeader
                    
                    // Photos section
                    photosSection
                    
                    if let log = dayLog {
                        // Activity summary
                        activitySummary(log: log)
                        
                        // Nutrition summary
                        nutritionSummary(log: log)
                        
                        // Workout summary
                        if let workout = log.workoutLog {
                            workoutSummary(workout: workout)
                        }
                        
                        // Checklist summary
                        if let items = log.checklistItems, !items.isEmpty {
                            checklistSummary(items: items)
                        }
                    } else {
                        noDataView
                    }
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showWorkoutDetail) {
                if let workout = dayLog?.workoutLog {
                    WorkoutDetailSheet(workout: workout)
                }
            }
            .sheet(isPresented: $showWorkoutEdit) {
                if let dayLog = dayLogBinding {
                    WorkoutLogSheet(
                        dayLog: Binding(
                            get: { dayLog },
                            set: { self.dayLogBinding = $0 }
                        ),
                        onSave: {}
                    )
                }
            }
            .fullScreenCover(isPresented: $showPhotoViewer) {
                if let index = selectedPhotoIndex, !photos.isEmpty {
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
            .onAppear {
                loadPhotos()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Load Photos
    
    private func loadPhotos() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let fetchDescriptor = FetchDescriptor<WorkoutPhoto>(
            predicate: #Predicate { photo in
                photo.capturedAt >= startOfDay && photo.capturedAt < endOfDay
            },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        
        if let fetchedPhotos = try? modelContext.fetch(fetchDescriptor) {
            photos = fetchedPhotos
        }
    }
    
    // MARK: - Score Header
    
    private var scoreHeader: some View {
        VStack(spacing: 16) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: 12)
                
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor, scoreColor.opacity(0.7)],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(score)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    
                    Text(scoreGrade)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
                
                if !photos.isEmpty {
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if photos.isEmpty {
                // Empty state with add button
                Button(action: {
                    showPhotoPicker = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        
                        Text("Add Photo")
                            .font(.subheadline.bold())
                            .foregroundStyle(.purple)
                        
                        Text("Document your progress for this day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            Button(action: {
                                selectedPhotoIndex = index
                                showPhotoViewer = true
                            }) {
                                DayPhotoThumbnail(photo: photo)
                            }
                        }
                        
                        // Add more button
                        Button(action: {
                            showPhotoPicker = true
                        }) {
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.purple)
                            }
                            .frame(width: 80, height: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.purple.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(.purple.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Save Photo
    
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
            photo.capturedAt = date // Use the day's date
            
            // Associate with workout if one exists
            if let workout = dayLog?.workoutLog {
                photo.workoutLog = workout
            }
            
            await MainActor.run {
                modelContext.insert(photo)
                try? modelContext.save()
                selectedPhotoItem = nil
                loadPhotos() // Refresh the photos list
            }
        }
    }
    
    private func deletePhoto(_ photo: WorkoutPhoto) {
        // Delete the photo file from disk
        _ = PhotoManager.shared.deletePhoto(filename: photo.filename)
        
        // Delete from model context
        modelContext.delete(photo)
        try? modelContext.save()
        loadPhotos() // Refresh the list
    }
    
    // MARK: - Activity Summary
    
    private func activitySummary(log: DayLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                // Steps
                MiniStatCard(
                    icon: "figure.walk",
                    iconColor: .blue,
                    value: log.steps != nil ? "\(log.steps!)" : "--",
                    label: "Steps"
                )
                
                // Active calories
                MiniStatCard(
                    icon: "flame.fill",
                    iconColor: .orange,
                    value: log.activeEnergyBurned != nil ? "\(log.activeEnergyBurned!)" : "--",
                    label: "Active Cal"
                )
                
                // Sleep
                MiniStatCard(
                    icon: "bed.double.fill",
                    iconColor: .purple,
                    value: log.sleepDurationMinutes != nil ? formatSleep(log.sleepDurationMinutes!) : "--",
                    label: "Sleep"
                )
            }
        }
    }
    
    // MARK: - Nutrition Summary
    
    private func nutritionSummary(log: DayLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrition")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                // Protein
                MiniStatCard(
                    icon: "p.circle.fill",
                    iconColor: .blue,
                    value: "\(Int(log.proteinGrams))g",
                    label: "Protein"
                )
                
                // Calories
                MiniStatCard(
                    icon: "flame.fill",
                    iconColor: .orange,
                    value: "\(Int(log.caloriesConsumed))",
                    label: "Calories"
                )
                
                // Water
                MiniStatCard(
                    icon: "drop.fill",
                    iconColor: .cyan,
                    value: "\(Int(log.waterOz)) oz",
                    label: "Water"
                )
            }
        }
    }
    
    // MARK: - Workout Summary
    
    private func workoutSummary(workout: WorkoutLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Button(action: {
                showWorkoutDetail = true
            }) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.green.opacity(0.1))
                        )
                    
                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workoutTagDisplay(workout.tag))
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 12) {
                            if let duration = workout.durationMinutes {
                                Text("\(duration) min")
                                    .font(.caption)
                            }
                            if let calories = workout.caloriesBurned {
                                Text("\(calories) cal")
                                    .font(.caption)
                            }
                            if let exercises = workout.exercises, !exercises.isEmpty {
                                Text("\(exercises.count) exercises")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stars
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { index in
                            Image(systemName: index <= workout.workoutScore ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(index <= workout.workoutScore ? .yellow : Color.secondary.opacity(0.3))
                        }
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.green.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Checklist Summary
    
    private func checklistSummary(items: [ChecklistItem]) -> some View {
        let completed = items.filter { $0.checklistStatus == .done }.count
        let total = items.count
        let progress = total > 0 ? Double(completed) / Double(total) : 0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Checklist")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(completed)/\(total)")
                    .font(.subheadline.bold())
                    .foregroundStyle(progress >= 1.0 ? .green : .secondary)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.green.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 8)
            
            // Completed items preview
            VStack(spacing: 6) {
                ForEach(items.filter { $0.checklistStatus == .done }.prefix(3), id: \.id) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        
                        Text(item.displayTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                }
                
                if items.filter({ $0.checklistStatus == .done }).count > 3 {
                    Text("+ \(items.filter { $0.checklistStatus == .done }.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - No Data View
    
    private var noDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No data for this day")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Start tracking to see your progress")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Helpers
    
    private func formatSleep(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
    
    private func workoutTagDisplay(_ tag: String) -> String {
        if let workoutTag = Constants.WorkoutTag(rawValue: tag) {
            return workoutTag.shortName
        }
        return tag
    }
}

// MARK: - Day Photo Thumbnail

private struct DayPhotoThumbnail: View {
    let photo: WorkoutPhoto
    @State private var image: UIImage?
    @State private var loadFailed = false
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: photo.capturedAt)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if loadFailed {
                    // Error state
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.6))
                                Text("Error")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay(
                            ProgressView()
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(loadFailed ? .red.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
            )
            
            Text(timeString)
                .font(.caption2)
                .foregroundStyle(.secondary)
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

// MARK: - Mini Stat Card

private struct MiniStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(iconColor)
            
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

#Preview {
    DaySummarySheet(date: Date(), dayLog: nil)
}
