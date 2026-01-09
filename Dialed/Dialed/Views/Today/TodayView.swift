//
//  TodayView.swift
//  Dialed
//
//  Main dashboard view - Live daily scoring and progress tracking
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: TodayViewModel

    @State private var showWaterEntry = false
    @State private var showProteinEntry = false

    init() {
        // Note: ViewModel will be properly initialized with injected context
        // This temporary initialization will be replaced when view appears
        let container = try! ModelContainer(for: DayLog.self, FoodEntry.self, WorkoutLog.self, ChecklistItem.self)
        _viewModel = StateObject(wrappedValue: TodayViewModel(modelContext: container.mainContext))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with score ring
                    headerSection

                    // Progress bars
                    progressSection

                    // Activity tiles
                    activitySection

                    // Checklist
                    checklistSection
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(formattedDate)
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.refreshData()
                        }
                    }) {
                        Image(systemName: viewModel.isSyncing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                            .foregroundColor(AppColors.primary)
                            .symbolEffect(.rotate, isActive: viewModel.isSyncing)
                    }
                    .disabled(viewModel.isSyncing)
                }
            }
            .refreshable {
                await viewModel.refreshData()
            }
            .task {
                // Auto-refresh on appear
                await viewModel.quickRefresh()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            DailyScoreRing(
                score: viewModel.provisionalScore,
                isProvisional: !viewModel.dayLog.isFinalized
            )

            if viewModel.currentStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(AppColors.warning)
                    Text("\(viewModel.currentStreak)-day streak")
                        .font(.subheadline.bold())
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.surface)
                .cornerRadius(20)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 12) {
            Text("Today's Progress")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                showWaterEntry = true
            }) {
                WaterProgressBar(
                    current: viewModel.dayLog.waterOz,
                    target: viewModel.settings.waterTargetOz
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showWaterEntry) {
                WaterEntrySheet(
                    currentAmount: Binding(
                        get: { viewModel.dayLog.waterOz },
                        set: { newValue in
                            viewModel.dayLog.waterOz = newValue
                            viewModel.updateDailyScore()
                        }
                    ),
                    target: viewModel.settings.waterTargetOz
                )
            }

            Button(action: {
                showProteinEntry = true
            }) {
                ProteinProgressBar(
                    current: viewModel.dayLog.proteinGrams,
                    target: viewModel.settings.proteinTargetGrams
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showProteinEntry) {
                ProteinEntrySheet(
                    currentAmount: Binding(
                        get: { viewModel.dayLog.proteinGrams },
                        set: { newValue in
                            viewModel.dayLog.proteinGrams = newValue
                            viewModel.updateDailyScore()
                        }
                    ),
                    target: viewModel.settings.proteinTargetGrams
                )
            }

            if viewModel.settings.calorieTarget != nil {
                CaloriesProgressBar(
                    current: viewModel.dayLog.caloriesConsumed,
                    target: viewModel.settings.calorieTarget
                )
            }
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(spacing: 12) {
            Text("Activity")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Sleep tile
            SleepTile(
                sleepScore: viewModel.sleepSummary.score,
                duration: viewModel.sleepSummary.duration,
                deepSleep: viewModel.sleepSummary.deepSleep,
                efficiency: viewModel.sleepSummary.efficiency
            )

            // Workout tile
            WorkoutTile(
                workoutDetected: viewModel.workoutSummary.detected,
                workoutTag: viewModel.workoutSummary.tag,
                workoutScore: viewModel.workoutSummary.score,
                duration: viewModel.workoutSummary.duration,
                calories: viewModel.workoutSummary.calories
            )

            // Mile tile
            MileTile(
                mileCompleted: viewModel.dayLog.mileCompleted,
                distance: viewModel.dayLog.mileDistance,
                timeSeconds: viewModel.dayLog.mileTimeSeconds,
                score: viewModel.dayLog.mileScore
            )

            // Activity metrics
            ActivityTile(
                steps: viewModel.activityMetrics.steps,
                activeEnergy: viewModel.activityMetrics.activeEnergy
            )
        }
    }

    // MARK: - Checklist Section

    private var checklistSection: some View {
        ChecklistCard(
            items: viewModel.checklistItems,
            onToggle: { item in
                viewModel.toggleChecklistItem(item)
            }
        )
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: viewModel.dayLog.date)
    }
}

#Preview {
    TodayView()
}
