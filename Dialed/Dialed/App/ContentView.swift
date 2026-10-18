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
    case home = 0
    case challenge = 1
    case plan = 2
    case trends = 3
    case settings = 4
}

struct MainTabView: View {
    // Index-driven so notification deep-links can switch tabs.
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onOpenChallenge: { selectedTab = .challenge })
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            ChallengeView()
                .tabItem {
                    Label("Challenge", systemImage: "flag.2.crossed.fill")
                }
                .tag(AppTab.challenge)

            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar.day.timeline.left")
                }
                .tag(AppTab.plan)

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
        // Mid-tone green reads on both the light (Home, Challenge) and
        // dark (Plan, Trends, Settings) tab bars.
        .tint(Neka.green)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToToday"))) { _ in
            selectedTab = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPlan"))) { _ in
            selectedTab = .plan
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHistory"))) { _ in
            // The score calendar now lives under Home.
            selectedTab = .home
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
