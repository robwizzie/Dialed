//
//  AppDirectoryView.swift
//  Dialed
//
//  "Everything in Dialed": every screen, grouped and searchable, so nothing
//  hides behind a menu. Opened from the Today menu, Settings and Home's
//  Explore row. Picking an entry closes the sheet, then goes there.
//

import SwiftUI

struct AppDirectoryView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let groups = AppDirectory.search(query)
                if groups.isEmpty {
                    Text("Nothing matches \"\(query)\".")
                        .font(.system(size: 14))
                        .foregroundColor(Neka.inkSecondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(groups) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            Button { open(entry.target) } label: { row(entry) }
                                .listRowBackground(Neka.surface)
                        }
                    } header: {
                        Text(section.group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .nekaPageBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find anything")
            .navigationTitle("Everything")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ entry: AppDirectory.Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint(entry.group))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill(entry.group)))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(entry.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func tint(_ g: AppDirectory.Group) -> Color {
        switch g {
        case .food:     return Neka.orange
        case .body:     return Neka.lavender
        case .move:     return Neka.green
        case .plan:     return Neka.sky
        case .compete:  return Neka.rose
        case .progress: return Neka.amber
        case .setup:    return Neka.inkSecondary
        }
    }

    private func fill(_ g: AppDirectory.Group) -> Color {
        switch g {
        case .food:     return Neka.orangeSoft
        case .body:     return Neka.lavenderSoft
        case .move:     return Neka.greenSoft
        case .plan:     return Neka.skySoft
        case .compete:  return Neka.roseSoft
        case .progress: return Neka.amberSoft
        case .setup:    return Neka.track
        }
    }

    /// Close first, then go — a sheet can't present over itself.
    private func open(_ target: AppDirectory.Target) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            router.go(to: target)
        }
    }
}

extension AppRouter {
    /// Where each directory entry lives.
    func go(to target: AppDirectory.Target) {
        switch target {
        case .foodLog:           openHome(HomeDestination.foodLog)
        case .mealPlan:          openHome(HomeDestination.mealPlan)
        case .eatingOut:         quickLog = .eatingOut
        case .scanBarcode:       quickLog = .scanFood
        case .trendWeight:       openHome(HomeDestination.weightTrend)
        case .metabolism:        openHome(HomeDestination.metabolism)
        case .progressPhotos:    openHome(HomeDestination.progressPhotos)
        case .strength:          openHome(HomeDestination.strength)
        case .sleep:             openHealth(.sleep)
        case .body:              openHealth(.body)
        case .workoutPlan:       openHome(HomeDestination.workout)
        case .mileHistory:       openHome(HomeDestination.mileHistory)
        case .suggestedActivity: openHome(HomeDestination.activity)
        case .pulse:             openHome(HomeDestination.pulse)
        case .schedule:          openHome(HomeDestination.schedule)
        case .wakeUp:            openHome(HomeDestination.wakeUp)
        case .calendars:         openHome(HomeDestination.calendars)
        case .challenge, .sideBets: select(.challenge)
        case .weeklyReport:      openChallenge(.report)
        case .wrapped:           openChallenge(.wrapped)
        case .badges:            openHome(HomeDestination.badges)
        case .habitHeatmap:      openHome(HomeDestination.habits)
        case .weekInReview:      openHome(HomeDestination.weeklyReview)
        case .scoreCalendar:     openHome(HomeDestination.calendar)
        case .timeline:          openHome(HomeDestination.timeline)
        case .devices:           openHome(HomeDestination.devices)
        case .customizeHome:     openHome(HomeView.HomeSheet.customize)
        case .notifications:     openHome(HomeDestination.notifications)
        }
    }
}

/// The "Suggested activity" page: the Home card on its own, plus anything
/// still waiting from recent days.
struct SuggestedActivityPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomeRecentSuggestionsCard()
                HomeFunCard()
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Suggested activity")
        .navigationBarTitleDisplayMode(.inline)
    }
}
