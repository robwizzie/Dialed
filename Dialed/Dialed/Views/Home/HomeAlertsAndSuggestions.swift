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

/// Reads as a health warning, not a nudge: a dark card edged in warning
/// amber (watch) or red (alert), a pulsing vitals icon, how many vitals
/// are off, and each one against your normal.
struct HomeIllnessBanner: View {
    let check: HealthInsights.IllnessCheck
    var onOpen: () -> Void = {}

    @AppStorage("illness.bannerDismissedDay") private var dismissedDay = ""
    @State private var expanded = false
    @State private var pulsing = false
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
    /// Only the short-night signals moved: still a warning, but the copy
    /// names sleep as the likely cause.
    private var shortNight: Bool { check.likelyShortSleep }

    private var tone: IllnessTone { isAlert ? .alert : .watch }

    var body: some View {
        if Self.shows(check, dismissedDay: dismissedDay) {
            VStack(alignment: .leading, spacing: 14) {
                statusBar
                header
                causeLine

                VStack(spacing: 8) {
                    ForEach(flagged) { IllnessSignalRow(signal: $0, tone: tone) }
                    if expanded {
                        ForEach(normal) { IllnessSignalRow(signal: $0, tone: tone) }
                    }
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHAT TO DO TODAY")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundColor(Neka.inkSecondary)
                        ForEach(Array(advice.enumerated()), id: \.offset) { i, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(tone.accentText)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(tone.accent.opacity(0.16)))
                                Text(line)
                                    .font(.system(size: 13))
                                    .foregroundColor(Neka.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .transition(.opacity)
                }

                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                actions
            }
            .padding(16)
            .padding(.leading, 4)
            .background(cardBackground)
            .shadow(color: tone.accent.opacity(0.18), radius: 16, y: 6)
            .accessibilityElement(children: .contain)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear { pulsing = !reduceMotion }
        }
    }

    // MARK: Pieces

    /// "⚠ HEALTH WARNING" on the left, how many vitals are off on the right.
    private var statusBar: some View {
        HStack(spacing: 8) {
            Label(isAlert ? "ILLNESS ALERT" : "HEALTH WARNING", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(tone.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(tone.accent))
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Text("\(flagged.count) of \(check.signals.count) vitals off")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tone.accentText)
                HStack(spacing: 2) {
                    ForEach(0..<check.signals.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(i < flagged.count ? tone.accent : Neka.muted)
                            .frame(width: 5, height: 12)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(tone.accent.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulsing ? 1.35 : 1)
                    .opacity(pulsing ? 0 : 0.8)
                    .animation(pulsing ? .easeOut(duration: 1.6).repeatForever(autoreverses: false) : nil, value: pulsing)
                Circle().fill(tone.accent.opacity(0.16))
                Image(systemName: isAlert ? "cross.case.fill" : "waveform.path.ecg")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(tone.accentText)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(why)
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Likely cause after a short night; otherwise the symptoms to watch for.
    @ViewBuilder
    private var causeLine: some View {
        if let hours = check.sleepHours, hours < 6 {
            infoStrip(icon: "moon.zzz.fill",
                      label: "Likely cause",
                      text: String(format: "Only %.1f h of sleep last night", hours))
        } else if !isAlert {
            infoStrip(icon: "thermometer.medium", label: "Watch for", text: "Sore throat, chills, aches or unusual fatigue")
        }
    }

    private func infoStrip(icon: String, label: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tone.accentText)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundColor(tone.accentText)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tone.accent.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(tone.accent.opacity(0.25), lineWidth: 0.5))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                Text("Body details")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tone.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(tone.accent))
            }
            .buttonStyle(.dialedScale)
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                Label(expanded ? "Less" : "What to do", systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().stroke(Neka.hairline, lineWidth: 1))
            }
            .buttonStyle(.dialedScale)
            Spacer()
            Button("Dismiss") {
                withAnimation { dismissedDay = Self.dayKey() }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Neka.inkTertiary)
            .accessibilityLabel("Dismiss for today")
        }
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
        return shape
            .fill(tone.card)
            .overlay(
                // Warning glow from the top-left corner.
                shape.fill(RadialGradient(colors: [tone.accent.opacity(0.22), .clear],
                                          center: .topLeading, startRadius: 0, endRadius: 260))
            )
            .overlay(alignment: .leading) {
                // The warning edge.
                Rectangle()
                    .fill(tone.accent)
                    .frame(width: 4)
            }
            .clipShape(shape)
            .overlay(shape.stroke(tone.accent.opacity(0.45), lineWidth: 1))
    }

    // MARK: Copy

    private var title: String {
        if isAlert { return "Possible illness detected" }
        return shortNight ? "Your body is under strain" : "Early warning: vitals off baseline"
    }

    private var why: String {
        func listed(_ signals: [HealthInsights.IllnessCheck.Signal]) -> String {
            let names = signals.map { $0.name == "HRV" ? "HRV" : $0.name.lowercased() }
            return names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.first ?? "your vitals"
        }
        let list = listed(flagged)
        if isAlert {
            return "Your \(list) all moved off your normal overnight. That's the pattern wearables see a day or two before a cold or flu shows up."
        }
        if shortNight {
            let rest = normal.isEmpty ? "" : " Your \(listed(normal)) \(normal.count == 1 ? "is" : "are") still normal."
            return "Your \(list) shifted the way they do before you get sick. A short night causes the same shift, so that's the likelier reason.\(rest)"
        }
        return "Your \(list) moved off your normal together. This pattern often shows up a day or two before you feel sick."
    }

    private var footnote: String {
        let nights = check.baselineNights
        let base = nights > 0 ? "Compared with your last \(nights) nights; shaded band = your normal range. " : ""
        return base + "Not a diagnosis. If you feel unwell, rest and talk to a doctor."
    }

    private var advice: [String] {
        if isAlert {
            return ["Skip hard training; a walk is plenty", "Aim for an extra hour of sleep tonight",
                    "Fluids and electrolytes, no alcohol", "Feverish or achy? Rest and check in with a doctor"]
        }
        if shortNight {
            return ["Train light today, no hard efforts", "Be in bed 60 minutes earlier tonight",
                    "Hydrate and skip alcohol", "Sore throat, chills or aches? Treat it as a cold starting"]
        }
        return ["Keep today's workout light", "Get to bed early tonight",
                "Drink more water than usual", "Watch for sore throat, chills or fatigue"]
    }
}

/// Warning colors: amber for a watch, red for an alert. The card stays
/// dark-tinted so it reads as an alert in both appearances.
private enum IllnessTone {
    case watch, alert

    var accent: Color { self == .alert ? Color(hex: "FF5A5F") : Color(hex: "FFA62B") }
    var accentText: Color {
        self == .alert ? Color(light: Color(hex: "C62828"), dark: Color(hex: "FF8A8D"))
                       : Color(light: Color(hex: "A85A00"), dark: Color(hex: "FFBE5C"))
    }
    /// Text on a solid accent fill.
    var onAccent: Color { Color(hex: "1A0E05") }
    var card: Color {
        self == .alert ? Color(light: Color(hex: "FFF5F5"), dark: Color(hex: "1F1315"))
                       : Color(light: Color(hex: "FFF8EE"), dark: Color(hex: "1E1810"))
    }
}

/// One vital: name, how far it moved and your usual; a two-week trend with
/// your normal band shaded; last night's value in the warning color when off.
private struct IllnessSignalRow: View {
    let signal: HealthInsights.IllnessCheck.Signal
    let tone: IllnessTone

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: signal.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(signal.flagged ? tone.accentText : Neka.inkSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(signal.flagged ? tone.accent.opacity(0.16) : Neka.track))
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    if !signal.change.isEmpty {
                        Text(signal.change)
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(signal.flagged ? tone.accentText : Neka.inkSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(signal.flagged ? tone.accent.opacity(0.16) : Neka.track))
                    }
                    Text(signal.usual)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            if signal.history.count >= 2 {
                IllnessTrend(signal: signal, tone: tone)
                    .frame(width: 56, height: 28)
                    .accessibilityHidden(true)
            }
            Text(signal.value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundColor(signal.flagged ? tone.accentText : Neka.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.surface.opacity(0.7)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(signal.flagged ? tone.accent.opacity(0.35) : Neka.hairline, lineWidth: signal.flagged ? 1 : 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.name): \(signal.value), \(signal.usual), \(signal.change)\(signal.flagged ? ", off your normal" : "")")
    }
}

/// History as a thin line, the normal band behind it, last night as a dot.
private struct IllnessTrend: View {
    let signal: HealthInsights.IllnessCheck.Signal
    let tone: IllnessTone

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
                             with: .color(Neka.track))
            }
            var line = Path()
            for (i, v) in values.enumerated() {
                if i == 0 { line.move(to: point(i, v)) } else { line.addLine(to: point(i, v)) }
            }
            context.stroke(line, with: .color(Neka.inkTertiary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            let last = point(values.count - 1, signal.current)
            let r: CGFloat = signal.flagged ? 3.5 : 2.5
            context.fill(Path(ellipseIn: CGRect(x: last.x - r, y: last.y - r, width: r * 2, height: r * 2)),
                         with: .color(signal.flagged ? tone.accent : Neka.ink))
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
