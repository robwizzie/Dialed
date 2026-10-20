//
//  HomeAlertsAndSuggestions.swift
//  Dialed
//
//  Two Home pieces that only appear when there's something to say:
//  the illness-watch banner at the top (which signals moved and why it
//  matters), and "From recent days" (stretches to name and watch
//  sessions to log from the past week).
//

import SwiftUI
import SwiftData

// MARK: - Illness watch banner

struct HomeIllnessBanner: View {
    let check: HealthInsights.IllnessCheck
    var onOpen: () -> Void = {}

    @AppStorage("illness.bannerDismissedDay") private var dismissedDay = ""
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func dayKey(_ date: Date = Date()) -> String { WeeklyReview.dayKey(date) }

    /// Shown for watch / alert, unless dismissed today.
    static func shows(_ check: HealthInsights.IllnessCheck?, dismissedDay: String) -> Bool {
        guard let check, check.level >= .watch else { return false }
        return dismissedDay != dayKey()
    }

    private var flagged: [HealthInsights.IllnessCheck.Signal] { check.signals.filter(\.flagged) }
    private var normal: [HealthInsights.IllnessCheck.Signal] { check.signals.filter { !$0.flagged } }
    private var isAlert: Bool { check.level == .alert }

    var body: some View {
        if Self.shows(check, dismissedDay: dismissedDay) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isAlert ? "cross.case.fill" : "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isAlert ? "ILLNESS WATCH · ALERT" : "ILLNESS WATCH")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white.opacity(0.8))
                        Text(isAlert ? "Your body might be fighting something" : "A few vitals are off your normal")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(why)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                // The signals that tripped it, always visible.
                VStack(spacing: 6) {
                    ForEach(flagged) { signalRow($0, flagged: true) }
                    if expanded {
                        ForEach(normal) { signalRow($0, flagged: false) }
                    }
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What helps")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        ForEach(advice, id: \.self) { line in
                            Label(line, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                    .transition(.opacity)
                }

                HStack(spacing: 10) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() }
                    } label: {
                        Label(expanded ? "Less" : "Why & what to do", systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isAlert ? Neka.rose : Neka.orangeText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.dialedScale)
                    Button(action: onOpen) {
                        Text("Body details")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().stroke(.white.opacity(0.6)))
                    }
                    .buttonStyle(.dialedScale)
                    Spacer()
                    Button("Dismiss today") {
                        withAnimation { dismissedDay = Self.dayKey() }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                    .fill(LinearGradient(colors: isAlert ? [Neka.rose, Color(hex: "E86F8A")] : [Neka.amber, Neka.orange],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: (isAlert ? Neka.rose : Neka.orange).opacity(0.25), radius: 14, y: 6)
            .accessibilityElement(children: .contain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var why: String {
        let names = flagged.map { $0.name.lowercased() }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.first ?? "your vitals"
        return "Overnight, your \(list) moved away from your normal together. That pattern often shows up a day or two before you feel a cold, or after a hard day, alcohol or short sleep."
    }

    private var advice: [String] {
        isAlert
            ? ["Skip hard training today; a walk is plenty", "Aim for an extra hour of sleep tonight",
               "Fluids and electrolytes, easy on alcohol", "If you feel feverish or achy, rest and check in with a doctor"]
            : ["Keep today's workout light", "Get to bed a little earlier", "Drink more water than usual"]
    }

    private func signalRow(_ s: HealthInsights.IllnessCheck.Signal, flagged: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(flagged ? 0.28 : 0.14)))
            Text(s.name)
                .font(.system(size: 13, weight: flagged ? .semibold : .regular))
                .foregroundColor(.white)
            Spacer()
            Text(s.value)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
            Text(s.usual)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
            Image(systemName: flagged ? "exclamationmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(flagged ? 1 : 0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(flagged ? 0.16 : 0.08)))
    }
}

// MARK: - From recent days

/// Stretches to name and watch sessions to log from the last six days.
/// Takes no space when nothing's waiting.
struct HomeRecentSuggestionsCard: View {
    @Environment(\.modelContext) private var context
    @State private var items: [DaySuggestions.Item] = []
    @State private var naming: HomeFunCard.NamingTarget?
    @State private var logging: DaySuggestions.Item?
    var onOpenDay: (Date) -> Void = { _ in }

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FROM RECENT DAYS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(Neka.inkTertiary)
                            Text(items.count == 1 ? "1 thing to add" : "\(items.count) things to add")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Neka.ink)
                        }
                        Spacer()
                        if let first = items.first {
                            Button { onOpenDay(first.day) } label: {
                                Label("Open day", systemImage: "calendar")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Neka.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Neka.track))
                            }
                            .buttonStyle(.dialedScale)
                        }
                    }
                    ForEach(items.prefix(4)) { item in
                        SuggestionRow(item: item, onAdd: { add(item) }, onDismiss: {
                            RecentSuggestions.dismiss(item)
                            withAnimation { items.removeAll { $0.id == item.id } }
                        })
                    }
                    if items.count > 4 {
                        Text("+\(items.count - 4) more. Open a day to see them all.")
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkTertiary)
                    }
                }
                .padding(14)
                .nekaCard()
                .transition(.opacity)
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
            Task { await refresh() }
        }
        .sheet(item: $naming) { target in
            FunActivitySheet(target: target) {
                RecentSuggestions.invalidate()
                Task { await refresh(force: true) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $logging, onDismiss: {
            RecentSuggestions.invalidate()
            Task { await refresh(force: true) }
        }) { item in
            WorkoutLoggerView(day: item.day, session: WorkoutPlanStore.session(on: item.day),
                              detected: item.workout.map { [$0] } ?? [])
                .presentationDetents([.large])
        }
    }

    private func add(_ item: DaySuggestions.Item) {
        switch item.kind {
        case .activity: if let b = item.bout { naming = .bout(b) }
        case .workout:  logging = item
        }
    }

    private func refresh(force: Bool = false) async {
        let found = await RecentSuggestions.recent(context: context, force: force)
        withAnimation(.easeOut(duration: 0.25)) { items = found }
    }
}
