//
//  NowView.swift
//  Dialed
//
//  The new Dialed 2.0 home screen. Replaces TodayView as the primary tab.
//
//  Composition:
//    1. Greeting + date header
//    2. Four-ring grid (Recovery / Readiness / Energy / Strain)
//    3. Now/Next strip — current and upcoming plan blocks
//    4. Quick-add bar — water / meal / mood / note
//    5. "Today's tracking" entry to the legacy screen (water/protein/checklist)
//
//  Visual language: Oura's typographic discipline, Apple Fitness's ring depth,
//  Luna's dark-glass cards, Whoop's color science for the state pillars.
//

import SwiftUI
import SwiftData

struct NowView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = NowViewModel()

    // Sheet routing for quick-add destinations.
    @State private var presentedQuickAdd: QuickAddBar.Action?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.nowBackground.ignoresSafeArea()
                ambientBackground

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        ringsGrid
                        if viewModel.nowBlock != nil || !viewModel.upcomingBlocks.isEmpty {
                            NowNextStrip(
                                current: viewModel.nowBlock,
                                upcoming: viewModel.upcomingBlocks
                            )
                        }
                        QuickAddBar(onTap: { presentedQuickAdd = $0 })
                        legacyTrackingCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh(context: modelContext) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
            .task { await viewModel.refresh(context: modelContext) }
            .refreshable { await viewModel.refresh(context: modelContext) }
            .sheet(item: $presentedQuickAdd) { action in
                QuickAddSheet(action: action)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.regularMaterial)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.greeting)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(viewModel.headerDateLine)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - Rings grid (2x2)

    private var ringsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 18) {
            ring(.recovery, breakdown: viewModel.recovery)
            ring(.readiness, breakdown: viewModel.readiness)
            ring(.energy, breakdown: viewModel.energy)
            ring(.strain, breakdown: viewModel.strain)
        }
    }

    private func ring(_ pillar: AppColors.Pillar, breakdown: StateEngine.ScoreBreakdown) -> some View {
        VStack {
            StateRing(
                pillar: pillar,
                score: breakdown.score,
                grade: breakdown.grade,
                confidence: breakdown.confidence
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColors.nowCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Legacy tracking card

    /// Bridge into the legacy TodayView so existing progress bars / checklist
    /// keep working during the transition. Lives at the bottom because it's
    /// detail-level — the rings are the headline.
    private var legacyTrackingCard: some View {
        NavigationLink {
            TodayView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.Pillar.energy.gradient,
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppColors.Pillar.energy.gradient.first!.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's tracking")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Water, protein, routine")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppColors.glassStroke, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ambient background

    /// Two soft, color-tinted radial blobs anchored to the top corners. Adds
    /// depth without visual noise. Tints follow the dominant pillar of the
    /// moment so the screen subtly shifts mood through the day.
    private var ambientBackground: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(viewModel.ambientLeftTint)
                    .frame(width: proxy.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(x: -proxy.size.width * 0.35, y: -proxy.size.height * 0.25)
                    .opacity(0.45)

                Circle()
                    .fill(viewModel.ambientRightTint)
                    .frame(width: proxy.size.width * 0.7)
                    .blur(radius: 100)
                    .offset(x: proxy.size.width * 0.35, y: -proxy.size.height * 0.15)
                    .opacity(0.35)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Quick-add sheet (placeholder body, real capture lands in Phase 4)

private struct QuickAddSheet: View {
    let action: QuickAddBar.Action

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                )
                .padding(.top, 24)

            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Quick capture lands in Phase 4 (Timeline + voice).")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch action {
        case .water: return "drop.fill"
        case .meal:  return "fork.knife"
        case .mood:  return "face.smiling.fill"
        case .note:  return "square.and.pencil"
        }
    }

    private var title: String {
        switch action {
        case .water: return "Log water"
        case .meal:  return "Log a meal"
        case .mood:  return "How are you feeling?"
        case .note:  return "Add a note"
        }
    }

    private var gradient: [Color] {
        switch action {
        case .water: return AppColors.Pillar.readiness.gradient
        case .meal:  return AppColors.Pillar.energy.gradient
        case .mood:  return AppColors.Pillar.recovery.gradient
        case .note:  return AppColors.Pillar.strain.gradient
        }
    }
}

// Required so QuickAddBar.Action can drive .sheet(item:).
extension QuickAddBar.Action: Identifiable {
    var id: Self { self }
}

#Preview {
    NowView()
        .preferredColorScheme(.dark)
}
