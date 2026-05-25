//
//  ContentView.swift
//  Dialed
//
//  Main navigation container
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
    }
}

struct MainTabView: View {
    // Index-driven so notification deep-links can switch tabs. AppDelegate
    // posts NavigateToToday / NavigateToPlan / NavigateToHistory; we map
    // those to the right tab here.
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NowView()
                .tabItem {
                    Label("Now", systemImage: "bolt.heart.fill")
                }
                .tag(0)

            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar.day.timeline.left")
                }
                .tag(1)

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(2)

            PillarTrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(AppColors.Pillar.readiness.gradient.last!)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToToday"))) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPlan"))) { _ in
            selectedTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHistory"))) { _ in
            selectedTab = 2
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
