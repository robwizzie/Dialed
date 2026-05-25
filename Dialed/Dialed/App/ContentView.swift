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
    var body: some View {
        TabView {
            NowView()
                .tabItem {
                    Label("Now", systemImage: "bolt.heart.fill")
                }

            PlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar.day.timeline.left")
                }

            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(AppColors.Pillar.readiness.gradient.last!)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
