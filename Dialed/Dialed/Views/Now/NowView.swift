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
//    5. Timeline entry card — push into the full day timeline
//    6. Detailed tracking entry to the legacy screen (water/protein/checklist)
//    + floating voice-capture mic (FAB, bottom-trailing) for hands-free
//      ContextEvent capture via the Speech framework.
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
    @State private var showVoiceCapture: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var refreshSpin: Angle = .degrees(0)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppColors.nowBackground.ignoresSafeArea()
                ambientBackground

                ScrollView {
                    VStack(spacing: Spacing.sectionSpacing) {
                        headerSection
                        ringsGrid
                        if viewModel.nowBlock != nil || !viewModel.upcomingBlocks.isEmpty {
                            NowNextStrip(
                                current: viewModel.nowBlock,
                                upcoming: viewModel.upcomingBlocks
                            )
                        }
                        QuickAddBar(onTap: { presentedQuickAdd = $0 })
                        timelineEntryCard
                        legacyTrackingCard
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.xs)
                    .padding(.bottom, 48)
                }

                voiceFAB
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    refreshToolbarButton
                }
            }
            .task { await viewModel.refresh(context: modelContext) }
            .refreshable { await viewModel.refresh(context: modelContext) }
            .sheet(item: $presentedQuickAdd) { action in
                Group {
                    switch action {
                    case .water: WaterCaptureSheet()
                            .presentationDetents([.medium])
                    case .meal:  MealCaptureSheet()
                            .presentationDetents([.medium, .large])
                    case .mood:  MoodCaptureSheet()
                            .presentationDetents([.medium])
                    case .note:  NoteCaptureSheet()
                            .presentationDetents([.medium, .large])
                    }
                }
                .presentationBackground(.regularMaterial)
                .presentationDragIndicator(.hidden)  // we draw our own GrabberHandle
            }
            .sheet(isPresented: $showVoiceCapture) {
                VoiceCaptureSheet()
                    .presentationDetents([.large])
                    .presentationBackground(.regularMaterial)
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    // MARK: - Toolbar refresh

    private var refreshToolbarButton: some View {
        Button {
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            performRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .rotationEffect(refreshSpin)
                .frame(width: 44, height: 44)  // 44pt touch target
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Refresh scores")
    }

    private func performRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
            refreshSpin = .degrees(refreshSpin.degrees + 360)
        }
        Task {
            await viewModel.refresh(context: modelContext)
            withAnimation(.easeOut(duration: 0.3)) {
                refreshSpin = .degrees(0)
            }
            isRefreshing = false
        }
    }

    // MARK: - Voice capture FAB

    /// Floating mic, anchored to bottom-trailing. Lives outside the
    /// ScrollView so it stays pinned regardless of scroll position.
    /// Padding clears the system tab bar.
    private var voiceFAB: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showVoiceCapture = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(LinearGradient(
                            colors: AppColors.Pillar.recovery.gradient,
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .shadow(
                            color: AppColors.Pillar.recovery.gradient.last!.opacity(0.5),
                            radius: 18, x: 0, y: 8
                        )
                )
        }
        .buttonStyle(.dialedScale)
        .padding(.trailing, Spacing.md)
        .padding(.bottom, 40)
        .accessibilityLabel("Voice capture")
        .accessibilityHint("Records a voice note and parses it into a logged entry")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(viewModel.greeting)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(viewModel.headerDateLine)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rings grid (2x2)

    private var ringsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)]
        return LazyVGrid(columns: cols, spacing: Spacing.md) {
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
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.heroCardRadius, style: .continuous)
                .fill(AppColors.nowCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.heroCardRadius, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pillar.displayName) \(breakdown.score) of 100, \(breakdown.grade.displayLabel)")
    }

    // MARK: - Timeline entry card

    /// Push to the new Timeline view from the home tab. Lives above the
    /// legacy tracking card because in 2.0 the Timeline is the primary lens
    /// on a day, not the checklist.
    private var timelineEntryCard: some View {
        NavigationLink {
            TimelineView()
        } label: {
            HStack(spacing: 14) {
                DialedPillarIcon(icon: "clock.arrow.circlepath", pillar: .recovery)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open day timeline")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Everything you've logged today")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(Spacing.cardPadding)
            .dialedGlassCard(cornerRadius: Spacing.cardRadius)
        }
        .buttonStyle(.dialedScale)
        .accessibilityHint("Opens the full Timeline view")
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
                DialedPillarIcon(icon: "checklist", pillar: .energy)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Detailed tracking")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Water, protein, routine checklist")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(Spacing.cardPadding)
            .dialedGlassCard(cornerRadius: Spacing.cardRadius)
        }
        .buttonStyle(.dialedScale)
        .accessibilityHint("Opens the legacy water and routine tracker")
    }

    // MARK: - Ambient background

    /// Two soft, color-tinted radial blobs anchored to the top corners. Adds
    /// depth without visual noise. Tints follow the dominant pillar of the
    /// moment so the screen subtly shifts mood through the day.
    /// Sized off UIScreen rather than the GeometryReader proxy so the blobs
    /// don't drift during pull-to-refresh.
    private var ambientBackground: some View {
        #if os(iOS)
        let screenSize = UIScreen.main.bounds.size
        #else
        let screenSize = CGSize(width: 400, height: 800)
        #endif
        return ZStack {
            Circle()
                .fill(viewModel.ambientLeftTint)
                .frame(width: screenSize.width * 0.95)
                .blur(radius: 90)
                .offset(x: -screenSize.width * 0.35, y: -screenSize.height * 0.28)
                .opacity(0.5)

            Circle()
                .fill(viewModel.ambientRightTint)
                .frame(width: screenSize.width * 0.75)
                .blur(radius: 100)
                .offset(x: screenSize.width * 0.35, y: -screenSize.height * 0.18)
                .opacity(0.4)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.4), value: viewModel.ambientLeftTint)
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
