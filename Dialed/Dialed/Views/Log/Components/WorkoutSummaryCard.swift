//
//  WorkoutSummaryCard.swift
//  Dialed
//
//  Compact workout summary card for the Log view
//

import SwiftUI

struct WorkoutSummaryCard: View {
    let tag: String?
    let score: Int?
    let duration: Int?
    let calories: Int?
    let exerciseCount: Int
    let onTap: () -> Void
    
    private var tagDisplay: String {
        guard let tag = tag else { return "Workout" }
        if let workoutTag = Constants.WorkoutTag(rawValue: tag) {
            return workoutTag.shortName
        }
        return tag
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.caption)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Workout")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Details
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        // Tag
                        Text(tagDisplay)
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(.blue.opacity(0.15))
                                    .overlay(
                                        Capsule()
                                            .stroke(.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        
                        if let duration = duration {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                Text("\(duration) min")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        if let calories = calories {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                Text("\(calories)")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    HStack {
                        // Quality score
                        if let score = score {
                            HStack(spacing: 4) {
                                ForEach(1...5, id: \.self) { index in
                                    Image(systemName: index <= score ? "star.fill" : "star")
                                        .font(.caption)
                                        .foregroundColor(index <= score ? .yellow : .secondary.opacity(0.3))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Exercise count
                        if exerciseCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.caption2)
                                Text("\(exerciseCount) exercises")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        // View details indicator
                        HStack(spacing: 4) {
                            Text("View details")
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(.blue)
                    }
                }
            }
            .elevatedGlassCard(cornerRadius: 16, padding: 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Empty Workout Card

struct EmptyWorkoutCard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.caption)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Workout")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Log a workout")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Text("Track your exercises and sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }
            .elevatedGlassCard(cornerRadius: 16, padding: 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 16) {
        WorkoutSummaryCard(
            tag: Constants.WorkoutTag.push.rawValue,
            score: 4,
            duration: 65,
            calories: 420,
            exerciseCount: 5,
            onTap: {}
        )
        
        EmptyWorkoutCard(onTap: {})
    }
    .padding()
    .background(AppColors.background)
}
