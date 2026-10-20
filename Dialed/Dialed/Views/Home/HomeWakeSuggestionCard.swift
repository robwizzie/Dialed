//
//  HomeWakeSuggestionCard.swift
//  Dialed
//
//  "Tomorrow: Dentist at 8:15 — wake 7:15 instead of 8:30?" The next
//  calendar-based wake-up suggestion with Accept / Ignore, and a count of
//  any others coming up. Takes no space when there's nothing to suggest
//  (or no calendar connected).
//

import SwiftUI

struct HomeWakeSuggestionCard: View {
    @ObservedObject private var service = CalendarService.shared
    @State private var suggestions: [WakeSuggestionEngine.Suggestion] = []

    var body: some View {
        Group {
            if let s = suggestions.first {
                card(s)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .task {
            await service.refresh()
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: CalendarService.didRefresh)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .wakeScheduleDidChange)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: CalendarPrefs.didChange)) { _ in reload() }
    }

    private func card(_ s: WakeSuggestionEngine.Suggestion) -> some View {
        let earlier = s.kind == .earlier
        let tint = earlier ? Neka.orangeText : Neka.lavenderText
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: earlier ? "sunrise.fill" : "bed.double.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(earlier ? Neka.orangeSoft : Neka.lavenderSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Self.dayName(s.date).uppercased()) · FROM YOUR CALENDAR")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text(headline(s))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                timePill(s.current.map(WakeSchedule.clock) ?? "No alarm", struck: true)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
                timePill(WakeSchedule.clock(s.suggested), struck: false)
                Spacer(minLength: 0)
            }

            Text(s.reason)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        WakeSuggestionStore.accept(s)
                    }
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                } label: {
                    Text("Wake at \(WakeSchedule.clock(s.suggested))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { WakeSuggestionStore.ignore(s) }
                } label: {
                    Text("Ignore")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
            }

            if suggestions.count > 1 {
                NavigationLink {
                    WakeScheduleView()
                } label: {
                    Text("\(suggestions.count - 1) more suggestion\(suggestions.count == 2 ? "" : "s") in the next two weeks")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func headline(_ s: WakeSuggestionEngine.Suggestion) -> String {
        if s.kind == .earlier, let title = s.eventTitle, let start = s.eventStart {
            return "\(title) at \(start.formatted(date: .omitted, time: .shortened)), wake at \(WakeSchedule.clock(s.suggested))?"
        }
        return "Day off: sleep in until \(WakeSchedule.clock(s.suggested))?"
    }

    private func timePill(_ text: String, struck: Bool) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .strikethrough(struck, color: Neka.inkTertiary)
            .foregroundColor(struck ? Neka.inkTertiary : Neka.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(struck ? Neka.track : Neka.greenSoft))
    }

    private func reload() {
        let fresh = WakeSuggestionStore.current()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { suggestions = fresh }
    }

    static func dayName(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}
