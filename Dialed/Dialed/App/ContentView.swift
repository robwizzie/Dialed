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
        // Widget taps → logs, fresh widget snapshot (Services/WidgetSync.swift).
        .widgetSync()
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
        guard appState.shouldShowWhatsNew else { return }
        // The app is built under the launch splash; wait for it to lift.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if appState.shouldShowWhatsNew { showWhatsNew = true }
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
    @State private var keyboardVisible = false

    init() {
        // The custom bar replaces the system one. Hiding it via appearance is
        // reliable across every tab and pushed screen, unlike per-view
        // `.toolbar(.hidden, for: .tabBar)`.
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        // A VStack, not an overlay: the bar takes real space, so every tab
        // (and every pushed screen) ends at its top edge. Nothing can scroll
        // underneath it, whatever each screen does with its safe area.
        VStack(spacing: 0) {
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

                HealthView()
                    .tabContent()
                    .tag(AppTab.trends)

                SettingsView()
                    .tabContent()
                    .tag(AppTab.settings)
            }

            if !keyboardVisible {
                NestedNavBar(router: router)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environmentObject(router)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = false }
        }
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
        // Smart reminders: re-plan on launch / foreground / after logging,
        // and open the right place when one is tapped.
        .smartReminders(router: router)
        // Wind-down and good-morning notes for the week ahead.
        .task { await WakeNotifications.reschedule() }
        // Widget taps (dialed://…, see WidgetLink).
        .onOpenURL { url in
            if let link = WidgetLink(url: url) { open(link) }
        }
    }

    private func open(_ link: WidgetLink) {
        switch link {
        case .home:      router.select(.home)
        case .water:     router.quickLog = .water
        case .meal:      router.quickLog = .meal
        case .weighIn:   router.quickLog = .weighIn
        case .food:      router.openHome(.foodLog)
        case .score:     router.openHome(.avatar)
        case .challenge: router.select(.challenge)
        case .sleep:     router.openHealth(.sleep)
        case .body:      router.openHealth(.body)
        }
    }

    @ViewBuilder
    private func quickLogSheet(_ item: QuickLog) -> some View {
        switch item {
        case .water:
            WaterLogSheet()
                .presentationDetents([.large])
        case .weighIn:
            WeighInSheet(lastWeight: nil)
                .presentationDetents([.medium])
        case .meal:
            AddFoodSheet()
                .presentationDetents([.large])
        case .snapMeal:
            AddFoodSheet(start: .photo)
                .presentationDetents([.large])
        case .scanFood:
            AddFoodSheet(start: .scan)
                .presentationDetents([.large])
        case .eatingOut:
            EatingOutSheet()
                .presentationDetents([.large])
        case .workout:
            WorkoutLoggerView(day: Calendar.current.startOfDay(for: Date()),
                              session: WorkoutPlanStore.session(on: Date()))
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
    /// Hide the system tab bar; the custom bar below the TabView replaces it.
    func tabContent() -> some View {
        self.toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
