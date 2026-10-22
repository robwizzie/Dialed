//
//  ScheduleView.swift
//  Dialed
//
//  Your days at a glance: a week strip on top, then one agenda per day —
//  wake-up (and alarm mission) first, calendar events as blocks in their
//  calendar's color, the planned workout, the meal plan, and bedtime last.
//  Calendar-based wake-up suggestions sit right on the day they're for.
//

import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var service = CalendarService.shared
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var schedule = WakeSchedule.load()
    @State private var suggestions: [WakeSuggestionEngine.Suggestion] = []
    @State private var mealPlan: WeekMealPlanner.WeekPlan?
    @State private var detail: PlannedEvent?

    private let calendar = Calendar.current
    private var days: [Date] {
        (0..<8).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: Date())) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    weekStrip(proxy)
                    if !service.isConnected { connectCard }
                    ForEach(days, id: \.self) { day in
                        dayAgenda(day)
                            .id(day)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .bottom) {
            // First calendar fetch: a floating pill, so events landing don't shove the agenda around.
            if service.isConnected && service.loadedAt == nil {
                NekaUpdatingPill(text: "Loading calendar")
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeOut(duration: 0.3), value: service.loadedAt == nil)
        .nekaPageBackground()
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { CalendarSettingsView() } label: { Image(systemName: "gearshape") }
            }
        }
        .task {
            mealPlan = MealPlanStore.current(context: context)
            await service.refresh()
            reload()
        }
        .refreshable {
            await service.refresh(force: true)
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarService.didRefresh)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .wakeScheduleDidChange)) { _ in reload() }
        .sheet(item: $detail) { event in
            EventDetailSheet(event: event)
                .presentationDetents([.medium])
        }
    }

    private func reload() {
        schedule = WakeSchedule.load()
        withAnimation(.easeOut(duration: 0.2)) { suggestions = WakeSuggestionStore.current() }
    }

    // MARK: - Week strip

    private func weekStrip(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            ForEach(days.prefix(7), id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let busy = service.events(on: day).filter { !$0.isAllDay }.count
                Button {
                    selected = day
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(day, anchor: .top) }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isSelected ? Neka.onInk.opacity(0.8) : Neka.inkTertiary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(isSelected ? Neka.onInk : Neka.ink)
                        HStack(spacing: 2) {
                            ForEach(0..<min(busy, 3), id: \.self) { _ in
                                Circle().fill(isSelected ? Neka.onInk : Neka.orange).frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? Neka.ink : Neka.surface))
                }
                .buttonStyle(.dialedScale)
            }
        }
    }

    private var connectCard: some View {
        NavigationLink { CalendarSettingsView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Neka.track))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("Apple or Google: your events show here and tune your wake-ups.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .nekaCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - A day

    private struct Item: Identifiable {
        enum Kind { case wake, event, workout, meal, bed }
        let id: String
        let time: Date?
        let kind: Kind
        let title: String
        let subtitle: String?
        let symbol: String
        let color: Color
        var event: PlannedEvent?
    }

    private func items(for day: Date) -> (allDay: [PlannedEvent], timed: [Item]) {
        var out: [Item] = []
        let events = service.events(on: day)
        if let wake = schedule.wake(on: day) {
            let alarm = WakeAlarmSettings.load()
            out.append(Item(id: "wake", time: wake, kind: .wake, title: "Wake up",
                            subtitle: alarm.enabled ? "Alarm · \(alarm.effectiveMission.title) mission" : (schedule.isChanged(on: day) ? "Changed for this day" : nil),
                            symbol: "sun.horizon.fill", color: Neka.amber))
        }
        for e in events where !e.isAllDay {
            let range = "\(e.start.formatted(date: .omitted, time: .shortened))–\(e.end.formatted(date: .omitted, time: .shortened))"
            out.append(Item(id: e.id, time: e.start, kind: .event, title: e.title,
                            subtitle: [range, e.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                            symbol: "calendar", color: Color(hex: e.colorHex ?? "#5B8DEF"), event: e))
        }
        let session = WorkoutPlanStore.session(on: day)
        if session.kind != .rest {
            out.append(Item(id: "workout", time: nil, kind: .workout, title: session.title,
                            subtitle: [session.minutes > 0 ? "\(session.minutes) min" : nil, session.walk].compactMap { $0 }.joined(separator: " · "),
                            symbol: session.symbol, color: Neka.green))
        }
        if let plan = mealPlan?.days.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            for meal in plan.meals {
                out.append(Item(id: "meal-\(meal.slot.rawValue)", time: nil, kind: .meal, title: "\(meal.emoji) \(meal.name)",
                                subtitle: "\(meal.slot.title) · \(Int(meal.calories)) calories · \(Int(meal.protein)) g protein",
                                symbol: "fork.knife", color: Neka.orange))
            }
        }
        if let next = calendar.date(byAdding: .day, value: 1, to: day), let bed = schedule.bedtime(before: next) {
            out.append(Item(id: "bed", time: bed, kind: .bed, title: "Lights out",
                            subtitle: "\(WakeSchedule.duration(schedule.sleepGoalMinutes)) before \(schedule.minutes(on: next).map(WakeSchedule.clock) ?? "tomorrow")",
                            symbol: "moon.stars.fill", color: Neka.lavender))
        }
        // Timed items in order; untimed (workout, meals) after the morning.
        let timed = out.filter { $0.time != nil }.sorted { $0.time! < $1.time! }
        let untimed = out.filter { $0.time == nil }
        var merged = timed.filter { $0.kind != .bed }
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let insertAt = merged.firstIndex { ($0.time ?? noon) >= noon } ?? merged.count
        merged.insert(contentsOf: untimed, at: insertAt)
        merged += timed.filter { $0.kind == .bed }
        return (events.filter(\.isAllDay), merged)
    }

    private func dayAgenda(_ day: Date) -> some View {
        let (allDay, list) = items(for: day)
        let suggestion = suggestions.first { calendar.isDate($0.date, inSameDayAs: day) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(HomeWakeSuggestionCard.dayName(day))
                    .font(Neka.display(22, weight: .bold))
                    .foregroundColor(Neka.ink)
                Text(day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
                Spacer()
            }
            ForEach(allDay) { e in
                Button { detail = e } label: {
                    HStack(spacing: 8) {
                        Capsule().fill(Color(hex: e.colorHex ?? "#5B8DEF")).frame(width: 4, height: 16)
                        Text(e.title).font(.system(size: 13, weight: .semibold)).foregroundColor(Neka.ink)
                        Spacer()
                        Text("All day").font(.system(size: 11)).foregroundColor(Neka.inkTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: e.colorHex ?? "#5B8DEF").opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            if let suggestion { suggestionRow(suggestion) }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                    row(item, last: index == list.count - 1)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .nekaCard()
        }
    }

    private func row(_ item: Item, last: Bool) -> some View {
        Button {
            if let e = item.event { detail = e }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(item.time?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Neka.inkTertiary)
                    .frame(width: 58, alignment: .trailing)
                    .padding(.top, 3)
                VStack(spacing: 0) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(item.color))
                    if !last {
                        Rectangle().fill(Neka.hairline).frame(width: 2).frame(maxHeight: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let sub = item.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 3)
                .padding(.bottom, last ? 0 : 10)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.event == nil)
    }

    private func suggestionRow(_ s: WakeSuggestionEngine.Suggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.kind == .earlier ? "sunrise.fill" : "bed.double.fill")
                .foregroundColor(s.kind == .earlier ? Neka.orangeText : Neka.lavenderText)
            VStack(alignment: .leading, spacing: 1) {
                Text("Suggested wake-up \(WakeSchedule.clock(s.suggested))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(s.reason)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("Use") { WakeSuggestionStore.accept(s) }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(Neka.ink)
                .controlSize(.small)
            Button { WakeSuggestionStore.ignore(s) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(s.kind == .earlier ? Neka.orangeSoft : Neka.lavenderSoft))
    }
}

/// One event's details.
struct EventDetailSheet: View {
    let event: PlannedEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: event.colorHex ?? "#5B8DEF")).frame(width: 12, height: 12)
                        Text(event.title).font(.headline)
                    }
                    if event.isAllDay {
                        Label("All day · \(event.start.formatted(.dateTime.weekday(.wide).month().day()))", systemImage: "calendar")
                    } else {
                        Label("\(event.start.formatted(.dateTime.weekday(.wide).month().day().hour().minute())) – \(event.end.formatted(date: .omitted, time: .shortened))",
                              systemImage: "clock")
                    }
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    Label("\(event.calendarTitle) · \(event.source == .google ? "Google Calendar" : "Apple Calendar")", systemImage: "tray.full")
                }
                if let notes = event.notes, !notes.isEmpty {
                    Section("Notes") { Text(notes).font(.callout) }
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
