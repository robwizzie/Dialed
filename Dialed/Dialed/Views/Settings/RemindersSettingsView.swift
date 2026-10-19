//
//  RemindersSettingsView.swift
//  Dialed
//
//  Smart reminders, Neka style: one master switch (turning it on is when
//  we ask for notification permission), a toggle per kind, quiet hours and
//  a daily cap — plus a peek at what's scheduled right now.
//

import SwiftUI
import SwiftData

struct RemindersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings = ReminderSettings.load()
    @State private var permissionDenied = false
    @State private var upcoming: [(date: Date, title: String)] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                masterCard
                if permissionDenied { deniedCard }
                group("Nudges") {
                    ForEach(Array(ReminderKind.allCases.enumerated()), id: \.element) { index, kind in
                        if index > 0 { divider }
                        kindRow(kind)
                    }
                }
                .opacity(settings.enabled ? 1 : 0.5)
                .disabled(!settings.enabled)

                group("Quiet hours & limit") {
                    timeRow("Quiet from", minutes: $settings.quietStart)
                    divider
                    timeRow("Until", minutes: $settings.quietEnd)
                    divider
                    Stepper(value: $settings.maxPerDay, in: 1...6) {
                        rowText("Up to \(settings.maxPerDay) a day", "The Sunday review doesn't count")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .opacity(settings.enabled ? 1 : 0.5)
                .disabled(!settings.enabled)

                if settings.enabled { upcomingCard }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .nekaPageBackground()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Neka.green)
        .task { await loadUpcoming() }
        .onChange(of: settings) { _, newValue in
            newValue.save()
            Task {
                await SmartReminders.refresh(context: modelContext)
                await loadUpcoming()
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        Text("Dialed only nudges you when you're behind pace — log it (or let the WaterH bottle sync) and the reminder quietly cancels itself.")
            .font(.system(size: 13))
            .foregroundColor(Neka.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var masterCard: some View {
        Toggle(isOn: Binding(get: { settings.enabled }, set: setEnabled)) {
            HStack(spacing: 14) {
                NekaIconBadge(systemName: "bell.badge.fill", tint: Neka.green, fill: Neka.surface.opacity(0.85))
                rowText("Smart reminders", settings.enabled ? "On — only when you're behind" : "Off")
            }
        }
        .padding(14)
        .nekaCard(wash: .mint)
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notifications are off for Dialed. Turn them on in Settings to get reminders.")
                .font(.system(size: 13))
                .foregroundColor(Neka.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.nekaPrimary)
        }
        .padding(16)
        .nekaCard(wash: .rose)
    }

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCHEDULED RIGHT NOW")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Neka.inkTertiary)
            if upcoming.isEmpty {
                Text("Nothing — you're on track (or it's quiet hours). 🎉")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }
            ForEach(Array(upcoming.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Neka.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(timeLabel(item.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard()
    }

    private func kindRow(_ kind: ReminderKind) -> some View {
        Toggle(isOn: Binding(
            get: { !settings.disabledKinds.contains(kind) },
            set: { on in
                if on { settings.disabledKinds.remove(kind) } else { settings.disabledKinds.insert(kind) }
            }
        )) {
            HStack(spacing: 14) {
                NekaIconBadge(systemName: kind.icon, tint: tint(kind), fill: fill(kind))
                rowText(kind.title, kind.detail)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func timeRow(_ title: String, minutes: Binding<Int>) -> some View {
        let date = Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
        return DatePicker(selection: date, displayedComponents: .hourAndMinute) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func setEnabled(_ on: Bool) {
        guard on else {
            settings.enabled = false
            return
        }
        Task {
            if await SmartReminders.requestPermission() {
                permissionDenied = false
                settings.enabled = true
            } else {
                permissionDenied = true
                settings.enabled = false
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let style: Date.FormatStyle = Calendar.current.isDateInToday(date)
            ? Date.FormatStyle().hour().minute()
            : Date.FormatStyle().weekday(.abbreviated).hour().minute()
        return date.formatted(style)
    }

    private func loadUpcoming() async {
        upcoming = settings.enabled ? await SmartReminders.pending() : []
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

    private var divider: some View {
        Divider().overlay(Neka.hairline).padding(.leading, 64)
    }

    private func rowText(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tint(_ kind: ReminderKind) -> Color {
        switch kind {
        case .water:        return Neka.sky
        case .protein:      return Neka.orange
        case .weighIn:      return Neka.green
        case .steps:        return Neka.lavender
        case .weeklyReview: return Neka.rose
        }
    }

    private func fill(_ kind: ReminderKind) -> Color {
        switch kind {
        case .water:        return Neka.skySoft
        case .protein:      return Neka.orangeSoft
        case .weighIn:      return Neka.greenSoft
        case .steps:        return Neka.lavenderSoft
        case .weeklyReview: return Neka.roseSoft
        }
    }
}

#Preview {
    NavigationStack { RemindersSettingsView() }
        .modelContainer(for: DialedSchema.allModels, inMemory: true)
}
