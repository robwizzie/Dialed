//
//  TrackingSettingsView.swift
//  Dialed
//
//  Customize which categories to track
//

import SwiftUI

struct TrackingSettingsView: View {
    @State private var preferences = TrackingPreferences.load()
    @State private var showScorePreview = false

    var body: some View {
        List {
            // Summary section
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tracking \(preferences.enabledCount) categories")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text(preferences.trackingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        showScorePreview.toggle()
                    }) {
                        Image(systemName: showScorePreview ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if showScorePreview {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Score Calculation")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)

                        if preferences.hasAnyEnabled {
                            Text("Each category's points are scaled to total 100 points")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text("Scale Factor:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(String(format: "%.2fx", preferences.scaleFactor))
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                            }
                        } else {
                            Text("Enable at least one category to start tracking")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                            )
                    )
                }
            } header: {
                Text("Overview")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )

            // Category toggles
            Section {
                ForEach(TrackingPreferences.categories, id: \.info.name) { item in
                    CategoryToggleRow(
                        isEnabled: Binding(
                            get: { preferences[keyPath: item.keyPath] },
                            set: { newValue in
                                preferences[keyPath: item.keyPath] = newValue
                                savePreferences()
                            }
                        ),
                        info: item.info,
                        scaleFactor: preferences.scaleFactor
                    )
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Disable categories you don't want to track. Your score adjusts automatically.")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
            )

            // Info section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("How it works")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(text: "Each category has a base point value")
                        InfoRow(text: "When you disable categories, remaining points scale up")
                        InfoRow(text: "Your daily score always maxes at 100")
                        InfoRow(text: "Disabled categories won't show on your dashboard")
                    }
                }
            } header: {
                Text("About Scoring")
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("What to Track")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func savePreferences() {
        preferences.save()

        // Trigger score recalculation (will be handled by TodayViewModel refresh)
    }
}

// MARK: - Category Toggle Row

struct CategoryToggleRow: View {
    @Binding var isEnabled: Bool
    let info: TrackingPreferences.CategoryInfo
    let scaleFactor: Double

    private var adjustedPoints: Int {
        Int((info.basePoints * scaleFactor).rounded())
    }

    var body: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $isEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: info.icon)
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: info.gradientColors.map { colorFromString($0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Text(info.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(colorFromString(info.gradientColors[0]))

            if isEnabled {
                HStack {
                    Text("Points:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(adjustedPoints)")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    if scaleFactor != 1.0 {
                        Text("(base: \(Int(info.basePoints)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    private func colorFromString(_ string: String) -> Color {
        switch string.lowercased() {
        case "indigo": return .indigo
        case "purple": return .purple
        case "green": return .green
        case "mint": return .mint
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        case "cyan": return .cyan
        case "yellow": return .yellow
        default: return .blue
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.blue)
                .frame(width: 12)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        TrackingSettingsView()
    }
}
