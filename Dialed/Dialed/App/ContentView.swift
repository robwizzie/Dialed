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
    // Shared with the bottom bar's nested menus and the tabs they drive.
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.tab) {
                HomeView(onOpenChallenge: { router.select(.challenge) })
                    .tabContent()
                    .tag(AppTab.home)

                ChallengeView()
                    .tabContent()
                    .tag(AppTab.challenge)

                PlanView()
                    .tabContent()
                    .tag(AppTab.plan)

                PillarTrendsView()
                    .tabContent()
                    .tag(AppTab.trends)

                SettingsView()
                    .tabContent()
                    .tag(AppTab.settings)
            }

            NestedNavBar(router: router)
                .ignoresSafeArea(.keyboard)
        }
        .environmentObject(router)
        .tint(Neka.green)
        .sheet(item: $router.quickLog, onDismiss: {
            NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
        }) { item in
            quickLogSheet(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToToday"))) { _ in
            router.select(.home)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToPlan"))) { _ in
            router.select(.plan)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHistory"))) { _ in
            router.openHome(.calendar)
        }
    }

    @ViewBuilder
    private func quickLogSheet(_ item: QuickLog) -> some View {
        switch item {
        case .water:
            WaterCaptureSheet()
                .environment(\.colorScheme, .dark)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        case .weighIn:
            WeighInSheet(lastWeight: nil)
                .presentationDetents([.medium])
        case .meal:
            AIMealSheet()
                .presentationDetents([.large])
        case .voice:
            VoiceCaptureSheet()
                .environment(\.colorScheme, .dark)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }
}

private extension View {
    /// Hide the system tab bar (the custom bar replaces it) and keep
    /// scrolling content clear of the floating bar.
    func tabContent() -> some View {
        self
            .toolbar(.hidden, for: .tabBar)
            .safeAreaPadding(.bottom, NestedNavBar.height)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
