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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("Water")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(displayCurrent) / \(displayTarget) oz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Liquid glass progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track with material
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )

                    // Liquid fill with shimmer
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .blue.opacity(0.7),
                                    .cyan.opacity(0.8),
                                    .blue
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            // Shimmer effect
                            LinearGradient(
                                colors: [
                                    .white.opacity(0),
                                    .white.opacity(0.3),
                                    .white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .blur(radius: 3)
                        )
                        .mask(
                            RoundedRectangle(cornerRadius: 10)
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        .frame(width: geometry.size.width * progress)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 14)

            // Percentage with glass pill
            HStack(spacing: 6) {
                Text("\(Int(progress * 100))%")
                    .font(.caption2.bold())
                    .foregroundColor(progress >= 1.0 ? .green : .blue)

                if progress >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("Protein")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(displayCurrent) / \(displayTarget) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Protein "steak bar" with liquid glass
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track with material
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )

                    // Protein fill with "meat" gradient
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .red.opacity(0.6),
                                    .pink.opacity(0.7),
                                    .red.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            // Shimmer/sear marks effect
                            LinearGradient(
                                colors: [
                                    .white.opacity(0),
                                    .white.opacity(0.25),
                                    .white.opacity(0),
                                    .white.opacity(0.2),
                                    .white.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .blur(radius: 2)
                        )
                        .mask(
                            RoundedRectangle(cornerRadius: 10)
                        )
                        .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                        .frame(width: geometry.size.width * progress)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 14)

            // Percentage with bonus indicator
            HStack(spacing: 6) {
                Text("\(Int(progress * 100))%")
                    .font(.caption2.bold())
                    .foregroundColor(progress >= 1.0 ? .green : .red)

                if progress >= 1.0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text("+2 bonus")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.green.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .stroke(.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("Calories")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                if let target = target {
                    Text("\(displayCurrent) / \(String(format: "%.0f", target)) cal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(displayCurrent) cal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if target != nil {
                // Calories progress bar with energy gradient
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track with material
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )

                        // Energy fill
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: isOverTarget ? [
                                        .orange.opacity(0.7),
                                        .red.opacity(0.6)
                                    ] : [
                                        .green.opacity(0.7),
                                        .mint.opacity(0.8)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                // Shimmer effect
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0),
                                        .white.opacity(0.3),
                                        .white.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .blur(radius: 3)
                            )
                            .mask(
                                RoundedRectangle(cornerRadius: 10)
                            )
                            .shadow(
                                color: (isOverTarget ? Color.orange : Color.green).opacity(0.3),
                                radius: 4,
                                x: 0,
                                y: 2
                            )
                            .frame(width: geometry.size.width * progress)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 14)

                // Status indicator
                if let target = target {
                    let remaining = target - current
                    HStack(spacing: 6) {
                        if remaining > 0 {
                            Text("\(String(format: "%.0f", remaining)) remaining")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                Text("\(String(format: "%.0f", -remaining)) over")
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
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
            }
        }
        .glassCard(cornerRadius: 16, padding: 14)
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
