//
//  WakeScheduleView.swift
//  Dialed
//
//  Your wake-up times: a usual time for each day of the week (or sleep
//  in), the next two weeks with any one-off changes, and your sleep goal.
//  Tap any upcoming day to change just that day. Bedtime, the wind-down
//  nudge and the day planner follow along.
//

import SwiftUI

struct WakeScheduleView: View {
    @State private var schedule = WakeSchedule.load()
    @State private var editingDay: Date?
    /// Calendar-based suggestions ("Dentist 8:15 → 7:15"), per day.
    @State private var suggestions: [WakeSuggestionEngine.Suggestion] = []
    private let calendar = Calendar.current

    /// Monday-first week.
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tomorrowCard
                section("Alarm") { WakeAlarmSettingsCard() }
                section("Usual wake-up") { weeklyCard }
                section("Next two weeks") { upcomingCard }
                calendarLink
                section("Sleep") { sleepCard }
                Text("Dialed also sends a wind-down note before bedtime and a good-morning note after you're up.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Wake-up times")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: schedule) { _, s in
            s.save()
            suggestions = WakeSuggestionStore.current()
        }
        .task {
            await CalendarService.shared.refresh()
            suggestions = WakeSuggestionStore.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarService.didRefresh)) { _ in
            suggestions = WakeSuggestionStore.current()
        }
        .sheet(item: Binding(get: { editingDay.map { DayTarget(date: $0) } }, set: { editingDay = $0?.date })) { target in
            WakeDaySheet(date: target.date, schedule: $schedule,
                         suggestion: suggestions.first { calendar.isDate($0.date, inSameDayAs: target.date) })
                .presentationDetents(suggestions.contains { calendar.isDate($0.date, inSameDayAs: target.date) }
                                     ? [.large] : [.medium, .large])
        }
    }

    private struct DayTarget: Identifiable {
        let date: Date
        var id: Date { date }
    }

    // MARK: - Tomorrow

    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date() }

    private var tomorrowCard: some View {
        Button { editingDay = tomorrow } label: {
            HStack(spacing: 14) {
                Image(systemName: schedule.wake(on: tomorrow) == nil ? "moon.zzz.fill" : "sun.horizon.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Neka.amber)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Neka.amberSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text("TOMORROW · \(tomorrow.formatted(.dateTime.weekday(.wide)).uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    if let m = schedule.minutes(on: tomorrow) {
                        Text("Up at \(WakeSchedule.clock(m))")
                            .font(Neka.display(22, weight: .bold))
                            .foregroundColor(Neka.ink)
                        if let bed = schedule.bedtime(before: tomorrow) {
                            Text("Bed by \(bed.formatted(date: .omitted, time: .shortened)) for \(WakeSchedule.duration(schedule.sleepGoalMinutes))")
                                .font(.system(size: 12))
                                .foregroundColor(Neka.inkSecondary)
                        }
                    } else {
                        Text("Sleep in")
                            .font(Neka.display(22, weight: .bold))
                            .foregroundColor(Neka.ink)
                    }
                }
                Spacer(minLength: 0)
                Text("Change")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Neka.track))
            }
            .padding(16)
            .nekaCard(wash: .mint)
        }
        .buttonStyle(.dialedScale)
    }

    // MARK: - Weekly

    private var weeklyCard: some View {
        VStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { wd in
                HStack(spacing: 10) {
                    Text(calendar.weekdaySymbols[wd - 1])
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Neka.ink)
                    Spacer()
                    if schedule.weekly[wd] != nil {
                        DatePicker("", selection: usualBinding(wd), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    } else {
                        Text("Sleep in")
                            .font(.system(size: 14))
                            .foregroundColor(Neka.inkTertiary)
                    }
                    Toggle("", isOn: Binding(
                        get: { schedule.weekly[wd] != nil },
                        set: { on in schedule.setUsual(on ? (schedule.weekly[2] ?? 390) : nil, weekday: wd) }
                    ))
                    .labelsHidden()
                    .tint(Neka.green)
                }
                .padding(.vertical, 8)
                if wd != weekdays.last { Divider().overlay(Neka.hairline) }
            }
            if let monday = schedule.weekly[2] {
                Button {
                    withAnimation { for wd in 3...6 { schedule.setUsual(monday, weekday: wd) } }
                } label: {
                    Label("Use Monday's time for all weekdays", systemImage: "arrow.down.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .nekaCard()
    }

    private func usualBinding(_ weekday: Int) -> Binding<Date> {
        Binding(
            get: { Self.date(minutes: schedule.weekly[weekday] ?? 390) },
            set: { schedule.setUsual(Self.minutes(of: $0), weekday: weekday) }
        )
    }

    // MARK: - Upcoming

    private var upcomingCard: some View {
        VStack(spacing: 0) {
            ForEach(0..<14, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
                Button { editingDay = day } label: {
                    HStack(spacing: 10) {
                        Text(offset == 0 ? "Today" : offset == 1 ? "Tomorrow" : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 14, weight: offset < 2 ? .semibold : .regular))
                            .foregroundColor(Neka.ink)
                        if let s = suggestions.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                            suggestionChip(s)
                        } else if schedule.isChanged(on: day) {
                            Text("CHANGED")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(Neka.orangeText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Neka.orangeSoft))
                        }
                        Spacer()
                        Text(schedule.minutes(on: day).map(WakeSchedule.clock) ?? "Sleep in")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(schedule.minutes(on: day) == nil ? Neka.inkTertiary : Neka.ink)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Neka.inkTertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if offset < 13 { Divider().overlay(Neka.hairline) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .nekaCard()
    }

    /// "Suggested 7:15" on an upcoming day; tapping the day shows why,
    /// with a one-tap Use.
    private func suggestionChip(_ s: WakeSuggestionEngine.Suggestion) -> some View {
        HStack(spacing: 3) {
            Image(systemName: s.kind == .earlier ? "sunrise.fill" : "bed.double.fill")
            Text("Suggested \(WakeSchedule.clock(s.suggested))")
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundColor(s.kind == .earlier ? Neka.orangeText : Neka.lavenderText)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .lineLimit(1)
        .fixedSize()
        .background(Capsule().fill(s.kind == .earlier ? Neka.orangeSoft : Neka.lavenderSoft))
        .accessibilityLabel("Suggested wake-up \(WakeSchedule.clock(s.suggested)). \(s.reason)")
    }

    private var calendarLink: some View {
        NavigationLink { CalendarSettingsView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Neka.track))
                VStack(alignment: .leading, spacing: 1) {
                    Text(CalendarService.shared.isConnected ? "Calendar-based suggestions" : "Connect your calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("Early plans move your wake-up earlier; days off let you sleep in. You accept each one.")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .nekaCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sleep

    private var sleepCard: some View {
        VStack(spacing: 12) {
            Stepper(value: $schedule.sleepGoalMinutes, in: 360...600, step: 15) {
                HStack {
                    Text("Sleep goal")
                    Spacer()
                    Text(WakeSchedule.duration(schedule.sleepGoalMinutes))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            Divider().overlay(Neka.hairline)
            Toggle("Wind-down reminder", isOn: $schedule.bedtimeReminder).tint(Neka.green)
            if schedule.bedtimeReminder {
                Picker("Remind me", selection: $schedule.windDownMinutes) {
                    Text("15 min before bed").tag(15)
                    Text("30 min before bed").tag(30)
                    Text("1 hour before bed").tag(60)
                }
            }
            Divider().overlay(Neka.hairline)
            Toggle("Good-morning note", isOn: $schedule.morningNote).tint(Neka.green)
        }
        .font(.system(size: 15))
        .foregroundColor(Neka.ink)
        .padding(16)
        .nekaCard()
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            content()
        }
    }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - One day

/// Change one date's wake-up: a time, sleep in, or back to usual.
struct WakeDaySheet: View {
    let date: Date
    @Binding var schedule: WakeSchedule
    /// A calendar-based suggestion for this day, if there is one.
    var suggestion: WakeSuggestionEngine.Suggestion? = nil
    /// Opened from somewhere else (the Sleep tab): link to the full schedule.
    var showsAllSettings = false
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var sleepIn = false

    private var usual: Int? { schedule.weekly[Calendar.current.component(.weekday, from: date)] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let suggestion { suggestionCard(suggestion) }
                    Toggle("Sleep in (no wake-up)", isOn: $sleepIn)
                        .tint(Neka.green)
                        .padding(16)
                        .nekaCard()
                        .animation(.easeOut(duration: 0.2), value: sleepIn)
                    if !sleepIn {
                        DatePicker("Wake up", selection: $time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipped()
                            .transition(.opacity)
                    }
                    Text(usual.map { "Usual \(date.formatted(.dateTime.weekday(.wide))): \(WakeSchedule.clock($0))" }
                         ?? "No usual wake-up on \(date.formatted(.dateTime.weekday(.wide)))s")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                    if schedule.isChanged(on: date) {
                        Button("Back to usual") {
                            schedule.resetDay(date)
                            dismiss()
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                    if showsAllSettings {
                        NavigationLink { WakeScheduleView() } label: {
                            Label("All wake-up times & alarm settings", systemImage: "alarm")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Neka.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Neka.track))
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .nekaPageBackground()
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        schedule.setDay(sleepIn ? nil : WakeScheduleView.minutes(of: time), on: date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let m = schedule.minutes(on: date)
                sleepIn = m == nil
                time = WakeScheduleView.date(minutes: m ?? usual ?? 390)
            }
        }
    }

    /// "SUGGESTED 5:10 AM", why, and a full-width Use button, so a long
    /// reason wraps instead of getting cut off.
    private func suggestionCard(_ s: WakeSuggestionEngine.Suggestion) -> some View {
        let earlier = s.kind == .earlier
        let tint = earlier ? Neka.orangeText : Neka.lavenderText
        let clock = WakeSchedule.clock(s.suggested)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: earlier ? "sunrise.fill" : "bed.double.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Neka.surface.opacity(0.75)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(earlier ? "SUGGESTED · EARLIER" : "SUGGESTED · SLEEP IN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(tint)
                    Text(clock)
                        .font(Neka.display(24, weight: .bold))
                        .foregroundColor(Neka.ink)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            Text(s.reason)
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                schedule.setDay(s.suggested, on: date)
                dismiss()
            } label: {
                Text("Use \(clock)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Neka.ink))
            }
            .buttonStyle(.dialedScale)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(earlier ? Neka.orangeSoft : Neka.lavenderSoft))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Home (evenings)

/// After 5 PM: "Up at 6:30 tomorrow · bed by 10:30" with a quick change.
struct HomeTomorrowWakeCard: View {
    @State private var schedule = WakeSchedule.load()
    @State private var editing = false

    static var isShowing: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 17 || h < 2
    }

    private var tomorrow: Date {
        let cal = Calendar.current
        let now = Date()
        // After midnight, "tomorrow" is still the morning ahead.
        let base = cal.component(.hour, from: now) < 2 ? now : cal.date(byAdding: .day, value: 1, to: now) ?? now
        return cal.startOfDay(for: base)
    }

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: schedule.wake(on: tomorrow) == nil ? "moon.zzz.fill" : "alarm.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Neka.lavenderText)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Neka.lavenderSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.minutes(on: tomorrow).map { "Up at \(WakeSchedule.clock($0)) tomorrow" } ?? "Sleeping in tomorrow")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                    if let alarm = alarmLine {
                        Text(alarm)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Neka.lavenderText)
                    }
                }
                Spacer(minLength: 0)
                Text("Change")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Neka.track))
            }
            .padding(14)
            .nekaCard()
        }
        .buttonStyle(.dialedScale)
        .sheet(isPresented: $editing) {
            WakeDaySheet(date: tomorrow, schedule: $schedule)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: schedule) { _, s in s.save() }
        .onReceive(NotificationCenter.default.publisher(for: .wakeScheduleDidChange)) { _ in
            let fresh = WakeSchedule.load()
            if fresh != schedule { schedule = fresh }
        }
    }

    /// "⏰ Alarm · Math mission"
    private var alarmLine: String? {
        let alarm = WakeAlarmSettings.load()
        guard alarm.enabled, schedule.wake(on: tomorrow) != nil else { return nil }
        return "⏰ Alarm · \(alarm.effectiveMission.title) mission"
    }

    private var subtitle: String {
        guard let bed = schedule.bedtime(before: tomorrow) else { return "No wake-up set. Enjoy it." }
        let left = bed.timeIntervalSince(Date())
        let bedText = bed.formatted(date: .omitted, time: .shortened)
        if left > 0 {
            let h = Int(left) / 3600, m = Int(left) % 3600 / 60
            return "Bed by \(bedText) for \(WakeSchedule.duration(schedule.sleepGoalMinutes)) · \(h > 0 ? "\(h) h " : "")\(m) m to go"
        }
        return "Past your \(bedText) bedtime. Lights out soon."
    }
}
