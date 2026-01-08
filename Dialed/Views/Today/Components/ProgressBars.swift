//
//  ProgressBars.swift
//  Dialed
//
//  Progress bar components for water, protein, calories
//

import SwiftUI

// MARK: - Water Progress Bar (Liquid Fill)

struct WaterProgressBar: View {
    let current: Double  // oz
    let target: Double   // oz

    private var progress: Double {
        min(current / target, 1.0)
    }

    private var displayCurrent: String {
        String(format: "%.0f", current)
    }

    private var displayTarget: String {
        String(format: "%.0f", target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(AppColors.primary)
                Text("Water")
                    .font(.subheadline.bold())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text("\(displayCurrent) / \(displayTarget) oz")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.surface)

                    // Fill
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.primary.opacity(0.6), AppColors.primary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress)
                        .animation(.spring(response: 0.6), value: progress)
                }
            }
            .frame(height: 12)

            // Percentage
            Text("\(Int(progress * 100))%")
                .font(.caption2.bold())
                .foregroundColor(progress >= 1.0 ? AppColors.success : AppColors.primary)
        }
        .padding()
        .background(AppColors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Protein Progress Bar ("Steak Bar")

struct ProteinProgressBar: View {
    let current: Double  // grams
    let target: Double   // grams

    private var progress: Double {
        min(current / target, 1.0)
    }

    private var displayCurrent: String {
        String(format: "%.0f", current)
    }

    private var displayTarget: String {
        String(format: "%.0f", target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(AppColors.danger)
                Text("Protein")
                    .font(.subheadline.bold())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text("\(displayCurrent) / \(displayTarget) g")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            // Progress bar with "steak" gradient
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.surface)

                    // Fill (red gradient for protein)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.danger.opacity(0.6), AppColors.danger],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress)
                        .animation(.spring(response: 0.6), value: progress)
                }
            }
            .frame(height: 12)

            // Percentage with bonus indicator
            HStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.caption2.bold())
                    .foregroundColor(progress >= 1.0 ? AppColors.success : AppColors.danger)

                if progress >= 1.0 {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(AppColors.success)
                    Text("+2 bonus")
                        .font(.caption2)
                        .foregroundColor(AppColors.success)
                }
            }
        }
        .padding()
        .background(AppColors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Calories Progress Bar

struct CaloriesProgressBar: View {
    let current: Double
    let target: Double?

    private var progress: Double {
        guard let target = target, target > 0 else { return 0 }
        return min(current / target, 1.0)
    }

    private var displayCurrent: String {
        String(format: "%.0f", current)
    }

    private var isOverTarget: Bool {
        guard let target = target else { return false }
        return current > target
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(AppColors.warning)
                Text("Calories")
                    .font(.subheadline.bold())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if let target = target {
                    Text("\(displayCurrent) / \(String(format: "%.0f", target)) cal")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                } else {
                    Text("\(displayCurrent) cal")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            if target != nil {
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.surface)

                        // Fill
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        isOverTarget ? AppColors.warning.opacity(0.6) : AppColors.success.opacity(0.6),
                                        isOverTarget ? AppColors.warning : AppColors.success
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress)
                            .animation(.spring(response: 0.6), value: progress)
                    }
                }
                .frame(height: 12)

                // Status
                HStack(spacing: 4) {
                    if let target = target {
                        let remaining = target - current
                        if remaining > 0 {
                            Text("\(String(format: "%.0f", remaining)) remaining")
                                .font(.caption2)
                                .foregroundColor(AppColors.textSecondary)
                        } else {
                            Text("\(String(format: "%.0f", -remaining)) over")
                                .font(.caption2.bold())
                                .foregroundColor(AppColors.warning)
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppColors.surface.opacity(0.5))
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 16) {
        WaterProgressBar(current: 85, target: 120)
        ProteinProgressBar(current: 165, target: 190)
        ProteinProgressBar(current: 195, target: 190)  // Over target with bonus
        CaloriesProgressBar(current: 1850, target: 2200)
        CaloriesProgressBar(current: 1450, target: nil)  // No target
    }
    .padding()
    .background(AppColors.background)
}