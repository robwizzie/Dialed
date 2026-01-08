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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(AppColors.primary)
                Text("Sleep")
                    .font(.subheadline.bold())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if let score = sleepScore {
                    HStack(spacing: 4) {
                        Text("\(score)/5")
                            .font(.title3.bold())
                            .foregroundColor(scoreColor)
                        Image(systemName: "moon.stars.fill")
                            .font(.caption)
                            .foregroundColor(scoreColor)
                    }
                }
            }

            // Metrics
            HStack(spacing: 16) {
                // Duration
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration")
                        .font(.caption2)
                        .foregroundColor(AppColors.textSecondary)
                    Text(durationText)
                        .font(.callout.bold())
                        .foregroundColor(AppColors.textPrimary)
                }

                Divider()
                    .frame(height: 30)

                // Deep sleep
                if let deep = deepSleep {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deep")
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary)
                        Text("\(deep)m")
                            .font(.callout.bold())
                            .foregroundColor(AppColors.textPrimary)
                    }
                }

                Spacer()

                // Efficiency
                if let eff = efficiency {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Efficiency")
                            .font(.caption2)
                            .foregroundColor(AppColors.textSecondary)
                        Text("\(Int(eff * 100))%")
                            .font(.callout.bold())
                            .foregroundColor(eff >= 0.85 ? AppColors.success : AppColors.textPrimary)
                    }
                }
            }

            if sleepScore == nil && duration == nil {
                Text("No sleep data yet")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding()
        .background(AppColors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Workout Tile

struct WorkoutTile: View {
    let workoutDetected: Bool
    let workoutTag: String?
    let workoutScore: Int?
    let duration: Int?  // minutes
    let calories: Int?

    private var tagDisplay: String {
        guard let tag = workoutTag,
              let workoutType = Constants.WorkoutTag(rawValue: tag) else {
            return "Workout"
        }
        return workoutType.shortName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(AppColors.success)
                Text("Workout")
                    .font(.subheadline.bold())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if workoutDetected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.success)
                }
            }

            if workoutDetected {
                // Workout details
                HStack(spacing: 12) {
                    // Tag
                    Text(tagDisplay)
                        .font(.caption.bold())
                        .foregroundColor(AppColors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.primary.opacity(0.2))
                        .cornerRadius(6)

                    if let duration = duration {
                        Text("\(duration) min")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    if let calories = calories {
                        Text("\(calories) cal")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Quality score
                    if let score = workoutScore {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { index in
                                Image(systemName: index <= score ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundColor(index <= score ? AppColors.warning : AppColors.textSecondary)
                            }
                        }
                    } else {
                        Text("Tap to rate")
                            .font(.caption)
                            .foregroundColor(AppColors.primary)
                    }
                }
            } else {
                Text("No workout detected today")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding()
        .background(AppColors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Activity Tile (Steps, Calories)

struct ActivityTile: View {
    let steps: Int?
    let activeEnergy: Int?

    var body: some View {
        HStack(spacing: 16) {
            // Steps
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                        .foregroundColor(AppColors.primary)
                    Text("Steps")
                        .font(.caption.bold())
                        .foregroundColor(AppColors.textPrimary)
                }

                if let steps = steps {
                    Text(steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000.0) : "\(steps)")
                        .font(.title2.bold())
                        .foregroundColor(AppColors.textPrimary)
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppColors.surface.opacity(0.5))
            .cornerRadius(12)

            // Active Energy
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundColor(AppColors.warning)
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundColor(AppColors.textPrimary)
                }

                if let energy = activeEnergy {
                    Text("\(energy)")
                        .font(.title2.bold())
                        .foregroundColor(AppColors.textPrimary)
                    + Text(" cal")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                } else {
                    Text("--")
                        .font(.title2.bold())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppColors.surface.opacity(0.5))
            .cornerRadius(12)
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
            calories: 420
        )

        WorkoutTile(
            workoutDetected: false,
            workoutTag: nil,
            workoutScore: nil,
            duration: nil,
            calories: nil
        )

        ActivityTile(steps: 8450, activeEnergy: 520)
    }
    .padding()
    .background(AppColors.background)
}