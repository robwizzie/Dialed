//
//  RecentWorkoutsCard.swift
//  Dialed
//
//  Shows workout history on the dashboard for quick access
//

import SwiftUI
import SwiftData

struct RecentWorkoutsCard: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \WorkoutLog.dayDate, order: .reverse) private var allWorkouts: [WorkoutLog]
    
    @State private var selectedWorkout: WorkoutLog?
    @State private var showWorkoutDetail = false
    
    let onWorkoutDeleted: (() -> Void)?
    
    init(onWorkoutDeleted: (() -> Void)? = nil) {
        self.onWorkoutDeleted = onWorkoutDeleted
    }
    
    // Filter to exclude today's workout and limit to 5
    private var recentWorkouts: [WorkoutLog] {
        let today = Calendar.current.startOfDay(for: Date())
        return allWorkouts
            .filter { Calendar.current.startOfDay(for: $0.dayDate) < today }
            .prefix(5)
            .map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Workout History")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !recentWorkouts.isEmpty {
                    Text("\(allWorkouts.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if recentWorkouts.isEmpty {
                emptyState
            } else {
                workoutsList
            }
        }
        .elevatedGlassCard(cornerRadius: 16, padding: 16)
        .sheet(isPresented: $showWorkoutDetail) {
            if let workout = selectedWorkout {
                WorkoutDetailSheet(
                    workout: workout,
                    onDelete: {
                        showWorkoutDetail = false
                        onWorkoutDeleted?()
                    }
                )
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.3))
            
            Text("No workout history yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("Log workouts to track your progress")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var workoutsList: some View {
        VStack(spacing: 8) {
            ForEach(recentWorkouts) { workout in
                Button(action: {
                    selectedWorkout = workout
                    showWorkoutDetail = true
                }) {
                    RecentWorkoutRow(workout: workout)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Recent Workout Row

struct RecentWorkoutRow: View {
    let workout: WorkoutLog
    
    private var tagDisplay: String {
        if let tag = Constants.WorkoutTag(rawValue: workout.tag) {
            return tag.shortName
        }
        return workout.tag
    }
    
    private var relativeDate: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let workoutDay = calendar.startOfDay(for: workout.dayDate)
        
        let days = calendar.dateComponents([.day], from: workoutDay, to: today).day ?? 0
        
        switch days {
        case 1:
            return "Yesterday"
        case 2...6:
            return "\(days) days ago"
        case 7:
            return "1 week ago"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: workout.dayDate)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Workout type indicator
            VStack(spacing: 4) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(.green.opacity(0.1))
            )
            
            // Workout info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tagDisplay)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Text(relativeDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 12) {
                    if let duration = workout.durationMinutes {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                            Text("\(duration) min")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    if let calories = workout.caloriesBurned {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                            Text("\(calories)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    // Exercise count
                    if let exercises = workout.exercises, !exercises.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "dumbbell.fill")
                                .font(.caption2)
                            Text("\(exercises.count)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Quality stars
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= workout.workoutScore ? "star.fill" : "star")
                        .font(.system(size: 8))
                        .foregroundColor(index <= workout.workoutScore ? .yellow : .secondary.opacity(0.3))
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

#Preview {
    RecentWorkoutsCard()
        .padding()
        .background(AppColors.background)
}
