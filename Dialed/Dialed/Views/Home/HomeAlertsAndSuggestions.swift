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
    /// Only the short-night signals moved: calmer colors, sleep-first copy.
    private var shortNight: Bool { check.likelyShortSleep }

    private var gradient: [Color] {
        if isAlert { return [Neka.rose, Color(hex: "E86F8A")] }
        if shortNight { return [Color(hex: "7B6BD6"), Color(hex: "5A72D8")] }
        return [Neka.amber, Neka.orange]
    }
    private var accentText: Color { isAlert ? Neka.rose : (shortNight ? Color(hex: "5A5FC8") : Neka.orangeText) }

    var body: some View {
        if Self.shows(check, dismissedDay: dismissedDay) {
            VStack(alignment: .leading, spacing: 14) {
                header

                // The signals that tripped it, always visible.
                VStack(spacing: 8) {
                    ForEach(flagged) { IllnessSignalRow(signal: $0) }
                    if expanded {
                        ForEach(normal) { IllnessSignalRow(signal: $0) }
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

                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() }
                    } label: {
                        Label(expanded ? "Less" : "All vitals & tips", systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(accentText)
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
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: gradient[0].opacity(0.25), radius: 14, y: 6)
            .accessibilityElement(children: .contain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isAlert ? "cross.case.fill" : (shortNight ? "moon.zzz.fill" : "waveform.path.ecg.rectangle.fill"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isAlert ? "ILLNESS WATCH · ALERT" : "ILLNESS WATCH")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.white.opacity(0.8))
                    if let hours = check.sleepHours {
                        Text(String(format: "%.1f h sleep", hours))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(hours < 6 ? 0.28 : 0.16)))
                    }
                }
                Text(title)
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
    }

    private var title: String {
        if isAlert { return "Your body might be fighting something" }
        return shortNight ? "A short night is showing in your vitals" : "A few vitals are off your normal"
    }

    private var why: String {
        func listed(_ signals: [HealthInsights.IllnessCheck.Signal]) -> String {
            let names = signals.map { $0.name == "HRV" ? "HRV" : $0.name.lowercased() }
            return names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.first ?? "your vitals"
        }
        let list = listed(flagged)
        if shortNight {
            let rest = normal.isEmpty ? "" : " Your \(listed(normal)) \(normal.count == 1 ? "looks" : "look") normal."
            return "Your \(list) moved together, which one short night does on its own.\(rest) If you feel fine, sleep is the likely reason, not a cold."
        }
        return "Overnight, your \(list) moved away from your normal together. That pattern often shows up a day or two before you feel a cold, or after a hard day, alcohol or short sleep."
    }

    private var footnote: String {
        let nights = check.baselineNights
        let base = nights > 0 ? "Compared with your last \(nights) nights. " : ""
        return base + "Shaded band = your normal range. Not a diagnosis."
    }

    private var advice: [String] {
        if isAlert {
            return ["Skip hard training today; a walk is plenty", "Aim for an extra hour of sleep tonight",
                    "Fluids and electrolytes, easy on alcohol", "If you feel feverish or achy, rest and check in with a doctor"]
        }
        if shortNight {
            return ["Moderate training is fine; save PRs for a rested day", "Get to bed 30–60 min earlier tonight",
                    "Keep caffeine before early afternoon", "Expect HRV to bounce back after a full night"]
        }
        return ["Keep today's workout light", "Get to bed a little earlier", "Drink more water than usual"]
    }
}

/// One vital: name and how far it moved, then a two-week trend with your
/// normal band shaded and last night as the dot.
private struct IllnessSignalRow: View {
    let signal: HealthInsights.IllnessCheck.Signal

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: signal.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(signal.flagged ? 0.28 : 0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.name)
                    .font(.system(size: 13, weight: signal.flagged ? .semibold : .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    if !signal.change.isEmpty {
                        Text(signal.change)
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(signal.flagged ? 0.3 : 0.14)))
                    }
                    Text(signal.usual)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            if signal.history.count >= 2 {
                IllnessTrend(signal: signal)
                    .frame(width: 56, height: 28)
                    .accessibilityHidden(true)
            }
            Text(signal.value)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 52, alignment: .trailing)
            Image(systemName: signal.flagged ? "exclamationmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(signal.flagged ? 1 : 0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(signal.flagged ? 0.16 : 0.08)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.name): \(signal.value), \(signal.usual), \(signal.change)\(signal.flagged ? ", off your normal" : "")")
    }
}

/// History as a thin line, the normal band behind it, last night as a dot.
private struct IllnessTrend: View {
    let signal: HealthInsights.IllnessCheck.Signal

    var body: some View {
        Canvas { context, size in
            let values = signal.history + [signal.current]
            var lo = values.min() ?? 0, hi = values.max() ?? 1
            if let band = signal.normal {
                lo = min(lo, band.lowerBound)
                hi = max(hi, band.upperBound)
            }
            let span = max(hi - lo, 0.0001)
            let inset: CGFloat = 4
            func point(_ i: Int, _ v: Double) -> CGPoint {
                let x = values.count > 1 ? CGFloat(i) / CGFloat(values.count - 1) * (size.width - inset * 2) + inset : size.width / 2
                let y = inset + (1 - CGFloat((v - lo) / span)) * (size.height - inset * 2)
                return CGPoint(x: x, y: y)
            }
            if let band = signal.normal {
                let top = point(0, band.upperBound).y, bottom = point(0, band.lowerBound).y
                context.fill(Path(roundedRect: CGRect(x: 0, y: top, width: size.width, height: max(2, bottom - top)), cornerRadius: 3),
                             with: .color(.white.opacity(0.16)))
            }
            var line = Path()
            for (i, v) in values.enumerated() {
                if i == 0 { line.move(to: point(i, v)) } else { line.addLine(to: point(i, v)) }
            }
            context.stroke(line, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            let last = point(values.count - 1, signal.current)
            let r: CGFloat = signal.flagged ? 3.5 : 2.5
            context.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)), with: .color(.white))
        }
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
    @State private var reviewing: ActiveBouts.Bout?
    var onOpenDay: (Date) -> Void = { _ in }

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WAITING FOR YOU")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(Neka.inkTertiary)
                            Text(items.count == 1 ? "1 activity to add or dismiss" : "\(items.count) activities to add or dismiss")
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
                        SuggestionRow(item: item, onOpen: item.bout.map { b -> () -> Void in { reviewing = b } },
                                      onAdd: { add(item) }, onDismiss: {
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
        .sheet(item: $reviewing) { bout in
            ActivityReviewSheet(bout: bout) { Task { await refresh(force: true) } }
                .presentationDetents([.large])
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
