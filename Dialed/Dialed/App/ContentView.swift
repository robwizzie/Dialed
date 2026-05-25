//
//  ContentView.swift
//  Dialed
//
//  Main navigation container
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showWhatsNew: Bool = false

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
        // Once-per-version "what's new" sheet. Fires after onboarding is
        // complete and the persisted seen-version trails current. The
        // sheet itself calls AppState.markWhatsNewSeen on dismiss.
        .onAppear { showWhatsNewIfNeeded() }
        .onChange(of: appState.hasCompletedOnboarding) { _, _ in
            showWhatsNewIfNeeded()
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet()
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationBackground(.regularMaterial)
        }
    }

    private func showWhatsNewIfNeeded() {
        if appState.shouldShowWhatsNew {
            showWhatsNew = true
        }
    }
}

/// Stable identifiers for each tab. AppDelegate posts NavigateToToday /
/// NavigateToPlan / NavigateToHistory through NotificationCenter when a
/// notification action wants the user routed somewhere; the cases below
/// keep that wiring out of magic Int territory.
enum AppTab: Int, Hashable {
    case now = 0
    case plan = 1
    case calendar = 2
    case trends = 3
    case settings = 4
}

struct MainTabView: View {
    // Index-driven so notification deep-links can switch tabs.
    @State private var selectedTab: AppTab = .now

    var body: some View {
        TabView(selection: $selectedTab) {
            NowView()
                .tabItem {
                    Label("Now", systemImage: "bolt.heart.fill")
                }
                .tag(AppTab.now)

            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar.day.timeline.left")
                }
                .tag(AppTab.plan)

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(AppTab.calendar)

            PillarTrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.trends)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        // Use the first stop of the readiness gradient — distinctly
        // Dialed against the system blue, more legible on dark.
        .tint(AppColors.Pillar.readiness.gradient.first!)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToToday"))) { _ in
            selectedTab = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPlan"))) { _ in
            selectedTab = .plan
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHistory"))) { _ in
            selectedTab = .calendar
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
