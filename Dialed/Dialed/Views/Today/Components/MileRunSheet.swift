//
//  MileRunSheet.swift
//  Dialed
//
//  Mile run logging and detail view with split times
//

import SwiftUI
import SwiftData

// MARK: - Mile Run Entry/Detail Sheet

struct MileRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var dayLog: DayLog
    let onSave: () -> Void

    @State private var distance: Double
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var splitTimes: [SplitTime]
    @State private var mileScore: Int
    @State private var showSplitEntry: Bool = false
    
    // Apple Health integration
    @State private var showHealthPicker = false
    @State private var linkedWorkoutID: String?
    @State private var isLoadingSplits = false

    init(dayLog: Binding<DayLog>, onSave: @escaping () -> Void) {
        _dayLog = dayLog
        self.onSave = onSave

        // Initialize from existing data
        _distance = State(initialValue: dayLog.wrappedValue.mileDistance ?? 1.0)
        let totalSeconds = dayLog.wrappedValue.mileTimeSeconds ?? 0
        _minutes = State(initialValue: totalSeconds / 60)
        _seconds = State(initialValue: totalSeconds % 60)
        _mileScore = State(initialValue: dayLog.wrappedValue.mileScore ?? 3)

        // Initialize split times
        if let splits = dayLog.wrappedValue.mileSplitTimes, !splits.isEmpty {
            _splitTimes = State(initialValue: splits.enumerated().map { index, time in
                SplitTime(lapNumber: index + 1, seconds: time)
            })
        } else {
            _splitTimes = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Apple Health import
                    appleHealthSection
                    
                    // Distance and Time
                    distanceTimeSection

                    // Split Times
                    splitTimesSection

                    // Quality Rating
                    qualityRatingSection
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Mile Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMileRun()
                    }
                }
            }
            .sheet(isPresented: $showSplitEntry) {
                AddSplitTimeSheet(splitTimes: $splitTimes)
            }
            .sheet(isPresented: $showHealthPicker) {
                RunningWorkoutPickerSheet(
                    date: dayLog.date,
                    onSelect: { workout in
                        linkRunningWorkout(workout)
                    }
                )
            }
        }
        .presentationDetents([.large])
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
                
                if linkedWorkoutID != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text("Linked")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                }
            }
            
            if linkedWorkoutID != nil {
                // Show linked state
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
                        
                        Image(systemName: "figure.run")
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Apple Fitness Run")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        
                        Text("Data imported from Apple Health")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        linkedWorkoutID = nil
                    }) {
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
                // Show import option
                Button(action: {
                    showHealthPicker = true
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.1))
                                .frame(width: 44, height: 44)
                            
                            if isLoadingSplits {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Image(systemName: "heart.fill")
                                    .font(.body)
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import from Apple Health")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            
                            Text("Auto-fill distance, time, and splits")
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
                .disabled(isLoadingSplits)
            }
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }
    
    // MARK: - Link Running Workout
    
    private func linkRunningWorkout(_ workout: HealthKitManager.WorkoutData) {
        linkedWorkoutID = workout.id.uuidString
        
        // Auto-fill distance and time
        if let distanceMeters = workout.distance {
            distance = distanceMeters / 1609.34 // Convert to miles
        }
        
        let totalSeconds = workout.durationMinutes * 60
        minutes = totalSeconds / 60
        seconds = totalSeconds % 60
        
        // Fetch split times
        isLoadingSplits = true
        Task {
            do {
                if let splits = try await HealthKitManager.shared.fetchSplitTimes(for: workout.id) {
                    await MainActor.run {
                        splitTimes = splits.enumerated().map { index, time in
                            SplitTime(lapNumber: index + 1, seconds: time)
                        }
                        isLoadingSplits = false
                    }
                } else {
                    await MainActor.run {
                        isLoadingSplits = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingSplits = false
                }
                print("Error fetching split times: \(error)")
            }
        }
    }

    // MARK: - View Components

    private var distanceTimeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Distance & Time")
                .font(.headline)
                .foregroundStyle(.primary)

            // Distance
            VStack(alignment: .leading, spacing: 8) {
                Text("Distance (miles)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("1.0", value: $distance, format: .number)
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

                    Text("mi")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Time
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Time")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    // Minutes
                    VStack(spacing: 4) {
                        TextField("0", value: $minutes, format: .number)
                            .keyboardType(.numberPad)
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                        Text("min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(":")
                        .font(.title.bold())
                        .foregroundStyle(.secondary)

                    // Seconds
                    VStack(spacing: 4) {
                        TextField("00", value: $seconds, format: .number)
                            .keyboardType(.numberPad)
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                        Text("sec")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Pace calculation
            if distance > 0 {
                let totalSecs = minutes * 60 + seconds
                if totalSecs > 0 {
                    let paceSeconds = Int(Double(totalSecs) / distance)
                    let paceMin = paceSeconds / 60
                    let paceSec = paceSeconds % 60
                    HStack {
                        Image(systemName: "gauge")
                            .foregroundStyle(.orange)
                        Text("Pace: \(paceMin):\(String(format: "%02d", paceSec)) /mi")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.orange.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .stroke(.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }

    private var splitTimesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Split Times")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: {
                    showSplitEntry = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Split")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
                }
            }

            if splitTimes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.3))

                    Text("No split times recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(splitTimes.indices, id: \.self) { index in
                        SplitTimeRow(
                            split: splitTimes[index],
                            onDelete: {
                                splitTimes.remove(at: index)
                            }
                        )
                    }
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }

    private var qualityRatingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Quality")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { rating in
                    ratingButton(rating)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 16)
    }

    private func ratingButton(_ rating: Int) -> some View {
        Button(action: {
            mileScore = rating
        }) {
            VStack(spacing: 6) {
                Image(systemName: rating <= mileScore ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundColor(rating <= mileScore ? .yellow : .secondary.opacity(0.3))

                Text(ratingLabel(for: rating))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(rating <= mileScore ? .yellow.opacity(0.3) : .white.opacity(0.1), lineWidth: 1)
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

    private func saveMileRun() {
        dayLog.mileCompleted = true
        dayLog.mileDistance = distance
        dayLog.mileTimeSeconds = (minutes * 60) + seconds
        dayLog.mileScore = mileScore
        dayLog.mileSplitTimes = splitTimes.isEmpty ? nil : splitTimes.map { $0.seconds }

        onSave()
        dismiss()
    }
}

// MARK: - Split Time Model

struct SplitTime: Identifiable {
    let id = UUID()
    var lapNumber: Int
    var seconds: Int

    var formattedTime: String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Split Time Row

struct SplitTimeRow: View {
    let split: SplitTime
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("Lap \(split.lapNumber)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Spacer()

            Text(split.formattedTime)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
    }
}

// MARK: - Add Split Time Sheet

struct AddSplitTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var splitTimes: [SplitTime]

    @State private var minutes: Int = 0
    @State private var seconds: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Add Split Time")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .padding(.top, 24)

                Text("Lap \(splitTimes.count + 1)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    // Minutes
                    VStack(spacing: 8) {
                        TextField("0", value: $minutes, format: .number)
                            .keyboardType(.numberPad)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                        Text("minutes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(":")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.secondary)

                    // Seconds
                    VStack(spacing: 8) {
                        TextField("00", value: $seconds, format: .number)
                            .keyboardType(.numberPad)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                        Text("seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let totalSeconds = (minutes * 60) + seconds
                        let split = SplitTime(
                            lapNumber: splitTimes.count + 1,
                            seconds: totalSeconds
                        )
                        splitTimes.append(split)
                        dismiss()
                    }
                    .disabled(minutes == 0 && seconds == 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Running Workout Picker Sheet

struct RunningWorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let date: Date
    let onSelect: (HealthKitManager.WorkoutData) -> Void
    
    @State private var runningWorkouts: [HealthKitManager.WorkoutData] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.red)
                        Text("Loading runs from Apple Health...")
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
                } else if runningWorkouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary.opacity(0.5))
                        
                        Text("No Running Workouts")
                            .font(.headline)
                        
                        Text("No running or walking workouts were recorded on this day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select a run to import")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Text("Distance, time, and split times will be automatically filled.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            
                            // Workout list
                            ForEach(runningWorkouts, id: \.id) { workout in
                                RunningWorkoutRow(
                                    workout: workout,
                                    onSelect: {
                                        onSelect(workout)
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
            .navigationTitle("Import Run")
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
        
        do {
            runningWorkouts = try await HealthKitManager.shared.fetchRunningWorkouts(for: date)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Running Workout Row

private struct RunningWorkoutRow: View {
    let workout: HealthKitManager.WorkoutData
    let onSelect: () -> Void
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: workout.startDate)
    }
    
    private var formattedDuration: String {
        let hours = workout.durationMinutes / 60
        let minutes = workout.durationMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
    
    private var formattedDistance: String {
        guard let distance = workout.distance else { return "-- mi" }
        let miles = distance / 1609.34
        return String(format: "%.2f mi", miles)
    }
    
    private var formattedPace: String? {
        guard let distance = workout.distance, distance > 0 else { return nil }
        let totalSeconds = Double(workout.durationMinutes * 60)
        let paceSecondsPerMile = totalSeconds / (distance / 1609.34)
        let paceMinutes = Int(paceSecondsPerMile) / 60
        let paceSeconds = Int(paceSecondsPerMile) % 60
        return String(format: "%d:%02d /mi", paceMinutes, paceSeconds)
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Workout icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: workout.workoutTypeIcon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                // Workout details
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutTypeName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Text(formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.run")
                                .font(.caption2)
                            Text(formattedDistance)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(formattedDuration)
                        }
                        
                        if let pace = formattedPace {
                            HStack(spacing: 4) {
                                Image(systemName: "gauge")
                                    .font(.caption2)
                                Text(pace)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Select indicator
                VStack {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.green)
                    
                    Text("Import")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
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
    MileRunSheet(dayLog: $dayLog, onSave: {})
}
