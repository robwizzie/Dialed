//
//  SettingsView.swift
//  Dialed
//
//  Settings in the Neka style: a profile card on top, then grouped cards
//  for your plan, connections, the challenge and the app. Detail screens
//  use Neka tokens too, so they follow the system appearance.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var photos = ProfilePhotoStore.shared
    @ObservedObject private var google = GoogleHealthAuth.shared

    @State private var settings = UserSettings.load()
    @State private var challenge = WeightChallenge.load()
    @State private var healthKitConnected = false
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case profile, challenge, whatsNew
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(Neka.display(34, weight: .bold))
                        .tracking(-0.8)
                        .foregroundColor(Neka.ink)
                        .padding(.top, 8)

                    profileCard

                    group("Your plan") {
                        row("target", "Daily targets",
                            "\(Int(settings.proteinTargetGrams)) g protein · \(Int(settings.waterTargetOz)) oz water",
                            tint: Neka.green, fill: Neka.greenSoft) { TargetsSettingsView() }
                        divider
                        row("checklist", "Daily routine", "Your recurring tasks and times",
                            tint: Neka.orange, fill: Neka.orangeSoft) { ManageDailyRoutineView() }
                        divider
                        row("alarm", "Wake-up times", wakeSummary,
                            tint: Neka.amber, fill: Neka.amberSoft) { WakeScheduleView() }
                        divider
                        row("slider.horizontal.3", "Home screen", "Reorder or hide Home's cards",
                            tint: Neka.sky, fill: Neka.skySoft) { HomeLayoutEditor(inSheet: false) }
                        divider
                        row("figure.walk", "Mile a day", "\(MileADay.format(MileSettings.load().goalMiles)) goal · recalibrate steps per mile",
                            tint: Neka.lavender, fill: Neka.lavenderSoft) { MileSettingsView() }
                        divider
                        row("chart.bar.fill", "What to track", TrackingPreferences.load().trackingSummary,
                            tint: Neka.sky, fill: Neka.skySoft) { TrackingSettingsView() }
                        divider
                        row("figure.strengthtraining.traditional", "Workout types", "Categories for logged workouts",
                            tint: Neka.rose, fill: Neka.roseSoft) { WorkoutTypeSettingsView() }
                    }

                    group("Connections") {
                        row("dot.radiowaves.left.and.right", "Devices & data check",
                            google.isConnected ? "Pixel Watch connected" : "Pixel Watch, WaterH, scale",
                            tint: Neka.green, fill: Neka.greenSoft) { DevicesView() }
                        divider
                        row("heart.text.square.fill", "Apple Health",
                            healthKitConnected ? "Connected" : "Not connected",
                            tint: Neka.rose, fill: Neka.roseSoft) { HealthKitSettingsView() }
                        divider
                        row("bell.fill", "Notifications",
                            settings.notificationsEnabled ? "On" : "Off",
                            tint: Neka.lavender, fill: Neka.lavenderSoft) { NotificationsSettingsView() }
                        divider
                        row("alarm.fill", "Smart reminders", "Nudges only when you're behind pace",
                            tint: Neka.orange, fill: Neka.orangeSoft) { RemindersSettingsView() }
                    }

                    group("Challenge") {
                        actionRow("flag.2.crossed.fill",
                                  challenge == nil ? "Start a challenge" : "Edit challenge",
                                  challenge.map { "vs. \($0.friendDisplayName) · ends \($0.endDate.formatted(.dateTime.month(.abbreviated).day()))" }
                                    ?? "Go head-to-head with a friend",
                                  tint: Neka.orange, fill: Neka.orangeSoft) { sheet = .challenge }
                        divider
                        actionRow("chart.line.downtrend.xyaxis", "Open scoreboard", "Pace, projection and weigh-ins",
                                  tint: Neka.green, fill: Neka.greenSoft) { router.select(.challenge) }
                    }

                    group("About") {
                        actionRow("sparkles", "What's new", "Dialed 3.0",
                                  tint: Neka.lavender, fill: Neka.lavenderSoft) { sheet = .whatsNew }
                        divider
                        HStack {
                            Text("Version")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Neka.ink)
                            Spacer()
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                                .font(.system(size: 14))
                                .foregroundColor(Neka.inkSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }

                    DialedLockup(markSize: 28, textSize: 20)
                        .opacity(0.9)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .nekaPageBackground()
            .nekaStatusBarScrim()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: reload)
            .sheet(item: $sheet, onDismiss: reload) { sheet in
                switch sheet {
                case .profile:
                    ProfileSheet()
                case .challenge:
                    ChallengeSetupSheet(existing: challenge, suggestedStartWeight: settings.currentWeight)
                case .whatsNew:
                    WhatsNewSheet()
                        .environmentObject(appState)
                        .presentationBackground(.regularMaterial)
                }
            }
        }
    }

    private func reload() {
        settings = UserSettings.load()
        challenge = WeightChallenge.load()
        healthKitConnected = HealthKitManager.shared.checkAuthorizationStatus()
    }

    // MARK: - Profile

    private var profileCard: some View {
        VStack(spacing: 0) {
            Button { sheet = .profile } label: {
                HStack(spacing: 14) {
                    Group {
                        if let image = photos.thumbnail {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundColor(Neka.inkTertiary)
                        }
                    }
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Neka.surface, lineWidth: 2))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(firstName.ifEmpty("Add your name"))
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("Photo, name and hero framing")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            divider

            NavigationLink { ProfileSettingsView() } label: {
                HStack(spacing: 0) {
                    stat("Current", "\(Int(settings.currentWeight)) lb")
                    stat("Goal", "\(Int(settings.goalWeight)) lb")
                    stat("To go", "\(max(0, Int(settings.currentWeight - settings.goalWeight))) lb")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                        .padding(.trailing, 16)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .nekaCard(wash: .mint)
    }

    private var firstName: String {
        UserDefaults.standard.string(forKey: "user.firstName") ?? ""
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Building blocks

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Neka.inkTertiary)
                .padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .nekaCard()
        }
    }

    /// "Tomorrow 6:30 AM · 8 h sleep goal"
    private var wakeSummary: String {
        let s = WakeSchedule.load()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return "Tomorrow \(s.minutes(on: tomorrow).map(WakeSchedule.clock) ?? "sleep in") · \(WakeSchedule.duration(s.sleepGoalMinutes)) sleep goal"
    }

    private var divider: some View {
        Divider().overlay(Neka.hairline).padding(.leading, 64)
    }

    private func label(_ icon: String, _ title: String, _ subtitle: String, tint: Color, fill: Color) -> some View {
        HStack(spacing: 14) {
            NekaIconBadge(systemName: icon, tint: tint, fill: fill)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func row<Destination: View>(
        _ icon: String, _ title: String, _ subtitle: String,
        tint: Color, fill: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            LazyDestination(build: destination)
        } label: {
            label(icon, title, subtitle, tint: tint, fill: fill)
        }
        .buttonStyle(.plain)
    }

    private func actionRow(
        _ icon: String, _ title: String, _ subtitle: String,
        tint: Color, fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label(icon, title, subtitle, tint: tint, fill: fill)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(AppRouter())
}
