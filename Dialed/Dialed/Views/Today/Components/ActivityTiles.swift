//
//  ActivityTiles.swift
//  Dialed
//
//  Tiles showing sleep, workouts, and activity metrics
//

import SwiftUI

// MARK: - Sleep Tile

struct SleepTile: View {
    let sleepScore: Int?
    let duration: Int?  // minutes
    let deepSleep: Int?  // minutes
    let efficiency: Double?

    private var durationText: String {
        guard let duration = duration else { return "--" }
        let hours = duration / 60
        let minutes = duration % 60
        return "\(hours)h \(minutes)m"
    }

    private var scoreColor: Color {
        guard let score = sleepScore else { return AppColors.textSecondary }
        switch score {
        case 4...5: return AppColors.success
        case 3: return AppColors.primary
        case 2: return AppColors.warning
        default: return AppColors.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Sleep")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                if let score = sleepScore {
                    HStack(spacing: 6) {
                        Text("\(score)")
                            .font(.title2.bold())
                            .foregroundColor(scoreColor)
                        Text("/5")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "moon.stars.fill")
                            .font(.caption)
                            .foregroundColor(scoreColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(scoreColor.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .stroke(scoreColor.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }

            // Metrics with glass dividers
            HStack(spacing: 16) {
                // Duration
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(durationText)
                        .font(.callout.bold())
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 30)
                    .overlay(.ultraThinMaterial)

                // Deep sleep
                if let deep = deepSleep {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deep")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(deep)m")
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                // Efficiency
                if let eff = efficiency {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Efficiency")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(eff * 100))%")
                            .font(.callout.bold())
                            .foregroundColor(eff >= 0.85 ? .green : .primary)
                    }
                }
            }

            if sleepScore == nil && duration == nil {
                Text("No sleep data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .elevatedGlassCard(cornerRadius: 16, padding: 16)
    }
}

// MARK: - Workout Tile

struct WorkoutTile: View {
    let workoutDetected: Bool
    let workoutTag: String?
    let workoutScore: Int?
    let duration: Int?  // minutes
    let calories: Int?
    let isLinkedToHealth: Bool
    let exerciseCount: Int?
    let totalSets: Int?
    let totalVolume: Double?
    
    // Default initializer for compatibility
    init(workoutDetected: Bool, workoutTag: String?, workoutScore: Int?, duration: Int?, calories: Int?, isLinkedToHealth: Bool = false, exerciseCount: Int? = nil, totalSets: Int? = nil, totalVolume: Double? = nil) {
        self.workoutDetected = workoutDetected
        self.workoutTag = workoutTag
        self.workoutScore = workoutScore
        self.duration = duration
        self.calories = calories
        self.isLinkedToHealth = isLinkedToHealth
        self.exerciseCount = exerciseCount
        self.totalSets = totalSets
        self.totalVolume = totalVolume
    }

    private var tagDisplay: String {
        guard let tag = workoutTag,
              let workoutType = Constants.WorkoutTag(rawValue: tag) else {
            return workoutTag ?? "Workout"
        }
        return workoutType.shortName
    }
    
    private var volumeDisplay: String {
        guard let volume = totalVolume, volume > 0 else { return "" }
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
    
    private var hasExerciseData: Bool {
        if let count = exerciseCount, count > 0 { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                Text("Today's Workout")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                if workoutDetected {
                    HStack(spacing: 6) {
                        if isLinkedToHealth {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
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
                }
            }

            if workoutDetected {
                // Workout details
                VStack(alignment: .leading, spacing: 12) {
                    // Type and stats row
                    HStack(spacing: 10) {
                        // Tag
                        Text(tagDisplay)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .mint],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )

                        Spacer()
                        
                        // Duration
                        if let duration = duration {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text("\(duration) min")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(.primary)
                        }

                        // Calories
                        if let calories = calories {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("\(calories)")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    
                    // Exercise stats row (if exercises were logged)
                    if hasExerciseData {
                        HStack(spacing: 12) {
                            // Exercise count
                            if let count = exerciseCount, count > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "dumbbell.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                    Text("\(count) exercise\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                            
                            // Total sets
                            if let sets = totalSets, sets > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "repeat")
                                        .font(.caption2)
                                        .foregroundStyle(.cyan)
                                    Text("\(sets) sets")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                            
                            // Volume
                            if let volume = totalVolume, volume > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "scalemass.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.pink)
                                    Text("\(volumeDisplay) lbs")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }
                    }

                    // Quality score row
                    HStack(spacing: 6) {
                        if let score = workoutScore {
                            ForEach(1...5, id: \.self) { index in
                                Image(systemName: index <= score ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundColor(index <= score ? .yellow : Color.secondary.opacity(0.3))
                            }
                            
                            Text(qualityText(for: score))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text("Tap to Edit")
                                .font(.caption2.bold())
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                }
            } else {
                // Empty state - prompt to log workout
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log Today's Workout")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            
                            Text("Track your training session")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .elevatedGlassCard(cornerRadius: 16, padding: 16)
    }
    
    private func qualityText(for score: Int) -> String {
        switch score {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Great"
        case 5: return "Perfect"
        default: return ""
        }
    }
}

// MARK: - Mile Tile

struct MileTile: View {
    let mileCompleted: Bool
    let distance: Double?  // miles
    let timeSeconds: Int?
    let score: Int?

    private var paceText: String {
        guard let distance = distance, distance > 0, let timeSeconds = timeSeconds else {
            return "--"
        }
        let paceSeconds = Int(Double(timeSeconds) / distance)
        let minutes = paceSeconds / 60
        let seconds = paceSeconds % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    private var timeText: String {
        guard let timeSeconds = timeSeconds else { return "--" }
        let minutes = timeSeconds / 60
        let seconds = timeSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var scoreColor: Color {
        guard let score = score else { return AppColors.textSecondary }
        switch score {
        case 4...5: return AppColors.success
        case 3: return AppColors.primary
        case 2: return AppColors.warning
        default: return AppColors.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Mile Run")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                if mileCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .green.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }

            if mileCompleted {
                // Mile details
                HStack(spacing: 16) {
                    // Distance
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distance")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f mi", distance ?? 0))
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }

                    Divider()
                        .frame(height: 30)
                        .overlay(.ultraThinMaterial)

                    // Time
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(timeText)
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }

                    Divider()
                        .frame(height: 30)
                        .overlay(.ultraThinMaterial)

                    // Pace
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pace")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(paceText)
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                }

                // Quality score
                if let score = score {
                    HStack(spacing: 4) {
                        Text("Quality:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(1...5, id: \.self) { index in
                            Image(systemName: index <= score ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundColor(index <= score ? .yellow : .secondary.opacity(0.3))
                        }
                    }
                }
            } else {
                Text("No mile run logged today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .elevatedGlassCard(cornerRadius: 16, padding: 16)
    }
}

// MARK: - Activity Tile (Steps, Calories)

struct ActivityTile: View {
    let steps: Int?
    let activeEnergy: Int?

    var body: some View {
        HStack(spacing: 12) {
            // Steps card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Steps")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }

                if let steps = steps {
                    Text(steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000.0) : "\(steps)")
                        .font(.title2.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14, padding: 14)

            // Active Energy card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }

                if let energy = activeEnergy {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(energy)")
                            .font(.title2.bold())
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.primary, .primary.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("cal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 14, padding: 14)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SleepTile(
            sleepScore: 4,
            duration: 450,
            deepSleep: 95,
            efficiency: 0.89
        )

        SleepTile(
            sleepScore: nil,
            duration: nil,
            deepSleep: nil,
            efficiency: nil
        )

        WorkoutTile(
            workoutDetected: true,
            workoutTag: Constants.WorkoutTag.push.rawValue,
            workoutScore: 4,
            duration: 65,
            calories: 420,
            isLinkedToHealth: true,
            exerciseCount: 5,
            totalSets: 18,
            totalVolume: 12500
        )

        WorkoutTile(
            workoutDetected: false,
            workoutTag: nil,
            workoutScore: nil,
            duration: nil,
            calories: nil,
            isLinkedToHealth: false,
            exerciseCount: nil,
            totalSets: nil,
            totalVolume: nil
        )

        ActivityTile(steps: 8450, activeEnergy: 520)
    }
    .padding()
    .background(AppColors.background)
}
