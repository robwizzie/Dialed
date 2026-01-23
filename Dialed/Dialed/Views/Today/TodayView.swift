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
    @State private var showWorkoutLog = false
    @State private var showWorkoutDetail = false
    @State private var showMileRun = false
    @State private var trackingPreferences = TrackingPreferences.load()

    init() {
        // Note: ViewModel will be properly initialized with injected context
        // This temporary initialization will be replaced when view appears
        let container = try! ModelContainer(for: DayLog.self, FoodEntry.self, WorkoutLog.self, WorkoutExercise.self, WorkoutSet.self, WorkoutPhoto.self, ChecklistItem.self, CustomWorkoutType.self, WorkoutTemplate.self, TemplateExercise.self, TemplateSet.self)
        _viewModel = StateObject(wrappedValue: TodayViewModel(modelContext: container.mainContext))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.sectionSpacing) {
                    // Header with score ring
                    headerSection

                    // Progress bars (conditional)
                    if trackingPreferences.trackWater || trackingPreferences.trackProtein {
                        progressSection
                    }

                    // Activity tiles (conditional)
                    activitySection

                    // Checklist (conditional)
                    if trackingPreferences.trackChecklist {
                        checklistSection
                    }
                }
                .padding(Spacing.screenPadding)
                .padding(.bottom, Spacing.xl)
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
                            .rotationEffect(.degrees(viewModel.isSyncing ? 360 : 0))
                            .animation(
                                viewModel.isSyncing ? 
                                    Animation.linear(duration: 1).repeatForever(autoreverses: false) : 
                                    .default,
                                value: viewModel.isSyncing
                            )
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
            .onAppear {
                // Refresh tracking preferences on appear
                trackingPreferences = TrackingPreferences.load()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: Spacing.lg) {
            DailyScoreRing(
                score: viewModel.provisionalScore,
                isProvisional: !viewModel.dayLog.isFinalized
            )

            if viewModel.currentStreak > 0 {
                HStack(spacing: Spacing.xs) {
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
        VStack(spacing: Spacing.md) {
            Text("Today's Progress")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if trackingPreferences.trackWater {
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
            }

            if trackingPreferences.trackProtein {
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
            // Only show section if any activity categories are enabled
            if trackingPreferences.trackSleep || trackingPreferences.trackWorkout || trackingPreferences.trackMile {
                Text("Activity")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sleep tile (conditional)
            if trackingPreferences.trackSleep {
                SleepTile(
                    sleepScore: viewModel.sleepSummary.score,
                    duration: viewModel.sleepSummary.duration,
                    deepSleep: viewModel.sleepSummary.deepSleep,
                    efficiency: viewModel.sleepSummary.efficiency
                )
            }

            // Workout tile (conditional)
            if trackingPreferences.trackWorkout {
                Button(action: {
                    if viewModel.dayLog.workoutLog != nil {
                        // Existing workout - show details/edit
                        showWorkoutDetail = true
                    } else {
                        // No workout - log new one
                        showWorkoutLog = true
                    }
                }) {
                    WorkoutTile(
                        workoutDetected: viewModel.workoutSummary.detected,
                        workoutTag: viewModel.workoutSummary.tag,
                        workoutScore: viewModel.workoutSummary.score,
                        duration: viewModel.workoutSummary.duration,
                        calories: viewModel.workoutSummary.calories,
                        isLinkedToHealth: viewModel.dayLog.workoutLog?.isLinkedToHealth ?? false,
                        exerciseCount: viewModel.workoutExerciseStats.exerciseCount,
                        totalSets: viewModel.workoutExerciseStats.totalSets,
                        totalVolume: viewModel.workoutExerciseStats.totalVolume
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .sheet(isPresented: $showWorkoutLog) {
                    WorkoutLogSheet(
                        dayLog: Binding(
                            get: { viewModel.dayLog },
                            set: { newValue in
                                viewModel.dayLog = newValue
                            }
                        ),
                        onSave: {
                            Task {
                                await viewModel.refreshData()
                            }
                        }
                    )
                }
                .sheet(isPresented: $showWorkoutDetail) {
                    if let workout = viewModel.dayLog.workoutLog {
                        WorkoutDetailSheet(
                            workout: workout,
                            onDelete: {
                                Task {
                                    await viewModel.refreshData()
                                }
                            },
                            onUpdate: {
                                Task {
                                    await viewModel.refreshData()
                                }
                            }
                        )
                    }
                }
            }

            // Mile tile (conditional)
            if trackingPreferences.trackMile {
                Button(action: {
                    showMileRun = true
                }) {
                    MileTile(
                        mileCompleted: viewModel.dayLog.mileCompleted,
                        distance: viewModel.dayLog.mileDistance,
                        timeSeconds: viewModel.dayLog.mileTimeSeconds,
                        score: viewModel.dayLog.mileScore
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .sheet(isPresented: $showMileRun) {
                    MileRunSheet(
                        dayLog: Binding(
                            get: { viewModel.dayLog },
                            set: { newValue in
                                viewModel.dayLog = newValue
                            }
                        ),
                        onSave: {
                            Task {
                                await viewModel.refreshData()
                            }
                        }
                    )
                }
            }

            // Activity metrics (always shown if available - general step tracking)
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
