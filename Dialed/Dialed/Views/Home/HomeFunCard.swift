//
//  HomeFunCard.swift
//  Dialed
//
//  "Suggested activity" on Home: the stretches your heart rate gave away
//  (tap a "?" to say what it was, with your usual picks first), the ones
//  you've named, and anything your watch recorded that isn't the gym —
//  laid out on a strip of your day, 6 AM to midnight, with the minutes
//  and calories they earned. Plus a quick way to add one by hand.
//

import SwiftUI
import SwiftData

struct HomeFunCard: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var day = FunActivityService.Day()
    @State private var lookedAt: Date?
    @State private var naming: NamingTarget?
    @State private var earned = EarnedCalories.Day()
    /// "+280 calories added to today" for a moment after you name one.
    @State private var celebrate: Double?
    @State private var pulse = false

    /// Shown in the header, Customize Home and the naming sheet.
    static let title = "Suggested activity"

    enum NamingTarget: Identifiable {
        case bout(ActiveBouts.Bout)
        case manual
        var id: String {
            switch self {
            case .bout(let b): return b.id
            case .manual:      return "manual"
            }
        }
    }

    /// One thing that happened today, whatever its source.
    private struct Moment: Identifiable {
        let id: String
        let kind: ActiveMomentsStrip.Kind
        let name: String
        let start: Date
        let end: Date
        let calories: Double?
        let detail: String?
        var bout: ActiveBouts.Bout?
        var event: ContextEvent?

        var minutes: Double { max(1, end.timeIntervalSince(start) / 60) }
    }

    private var moments: [Moment] {
        let unnamed = day.unnamed.map {
            Moment(id: $0.id, kind: .unnamed, name: "What was it?", start: $0.start, end: $0.end,
                   calories: $0.calories, detail: "avg \(Int($0.averageBPM)) bpm", bout: $0)
        }
        let named = day.logged.map { e in
            Moment(id: "fun-\(e.id)", kind: .named, name: e.text ?? "Activity", start: e.timestamp,
                   end: e.timestamp.addingTimeInterval((e.value ?? 0) * 60), calories: e.secondaryValue,
                   detail: nil, event: e)
        }
        let recorded = day.recorded.map {
            Moment(id: "watch-\($0.id)", kind: .recorded, name: $0.title, start: $0.start, end: $0.end,
                   calories: $0.calories.map(Double.init), detail: $0.source)
        }
        return (unnamed + named + recorded).sorted { $0.start < $1.start }
    }

    /// Calories from the moments you've named or your watch recorded.
    private var momentCalories: Double {
        moments.filter { $0.kind != .unnamed }.reduce(0) { $0 + ($1.calories ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ActiveMomentsStrip(items: moments.map { .init(id: $0.id, kind: $0.kind, start: $0.start, end: $0.end) },
                     pulse: pulse && !reduceMotion) { id in
                if let b = moments.first(where: { $0.id == id })?.bout { naming = .bout(b) }
            }
            if moments.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(moments) { m in
                        row(m)
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
        .overlay(alignment: .top) {
            if let celebrate {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                    Text("+\(Int(celebrate)) calories added to today")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(LinearGradient(colors: [Neka.amber, Neka.orange],
                                                          startPoint: .leading, endPoint: .trailing)))
                .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Neka.orange.opacity(0.35), radius: 12, y: 5)
                .offset(y: -16)
                .transition(reduceMotion ? .opacity
                            : .move(edge: .top).combined(with: .scale(scale: 0.8)).combined(with: .opacity))
            }
        }
        .task { await refresh() }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
            if Date().timeIntervalSince(lookedAt ?? .distantPast) > 60 { Task { await refresh() } }
        }
        .sheet(item: $naming) { target in
            FunActivitySheet(target: target) { Task { await refresh() } }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "figure.mixed.cardio")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(LinearGradient(colors: [Neka.amber, Neka.rose],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(moments.isEmpty ? "Nothing yet today" : "\(Int(day.minutes.rounded())) active min")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .contentTransition(.numericText(value: day.minutes))
                    if momentCalories > 0 {
                        Label("+\(Int(momentCalories)) cal", systemImage: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Neka.orangeText)
                            .labelStyle(.titleAndIcon)
                            .contentTransition(.numericText(value: momentCalories))
                    }
                }
            }
            Spacer(minLength: 8)
            Button { naming = .manual } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Neka.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Neka.track))
            }
            .buttonStyle(.dialedScale)
            .accessibilityLabel("Add an activity")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ m: Moment) -> some View {
        if m.kind == .unnamed {
            Button { if let b = m.bout { naming = .bout(b) } } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Neka.roseSoft)
                        Circle().stroke(Neka.rose.opacity(0.5), lineWidth: 2)
                            .scaleEffect(pulse && !reduceMotion ? 1.2 : 1)
                            .opacity(pulse && !reduceMotion ? 0 : 1)
                        Text("?")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(Neka.rose)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You were moving \(Self.timeRange(m.start, m.end))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .lineLimit(1)
                        Text("\(Int(m.minutes.rounded())) min · \(m.detail ?? "") · earns ~\(Int(m.calories ?? 0))")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text("Name it")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Neka.ink))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.roseSoft.opacity(0.45)))
            }
            .buttonStyle(.dialedScale)
            .accessibilityLabel("Unnamed active stretch, \(Self.timeRange(m.start, m.end)). Name it.")
        } else {
            HStack(spacing: 12) {
                Image(systemName: ActiveBouts.symbol(for: m.name))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(m.kind == .named ? Neka.orangeText : Neka.greenText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(m.kind == .named ? Neka.orangeSoft : Neka.greenSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text([Self.timeRange(m.start, m.end), "\(Int(m.minutes.rounded())) min", m.detail]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let cal = m.calories, cal > 0 {
                    Text("+\(Int(cal))")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Neka.ink)
                    + Text(" cal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                if let e = m.event {
                    Button(role: .destructive) { FunActivityService.delete(e, context: context) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.amber)
            Text("Nothing yet — a game, a hike or a long walk will show up here.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.track))
    }

    static func timeRange(_ a: Date, _ b: Date) -> String {
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(a.formatted(f))–\(b.formatted(f))"
    }

    private func refresh() async {
        let firstLook = lookedAt == nil
        lookedAt = Date()
        let found = await FunActivityService.day(Date(), context: context)
        let nowEarned = await EarnedCalories.day(context: context)
        let gained = nowEarned.earned - earned.earned
        withAnimation(.easeOut(duration: 0.25)) {
            day = found
            earned = nowEarned
        }
        guard !firstLook, gained > 0 else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.7)) {
            celebrate = gained
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        try? await Task.sleep(for: .seconds(2.6))
        withAnimation(.easeIn(duration: 0.3)) { celebrate = nil }
    }
}

// MARK: - Day strip

/// 6 AM → midnight with a capsule per moment: a rose "?" for unnamed
/// stretches (tap to name), orange for named, green for watch-recorded.
struct ActiveMomentsStrip: View {
    enum Kind { case unnamed, named, recorded }

    struct Item: Identifiable {
        let id: String
        let kind: Kind
        let start: Date
        let end: Date
    }

    let items: [Item]
    let pulse: Bool
    var onTap: (String) -> Void

    private let span: TimeInterval = 18 * 3600
    private var dayStart: Date {
        Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func x(_ date: Date, width: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1, date.timeIntervalSince(dayStart) / span))) * width
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track).frame(height: 10)
                    // How much of the day has gone by.
                    Capsule().fill(Neka.inkTertiary.opacity(0.16))
                        .frame(width: x(Date(), width: w), height: 10)
                    ForEach(items) { item in
                        let start = x(item.start, width: w)
                        let width = max(item.kind == .unnamed ? 22 : 10, x(item.end, width: w) - start)
                        capsule(item)
                            .frame(width: width, height: item.kind == .unnamed ? 22 : 14)
                            .offset(x: min(start, max(0, w - width)))
                            .onTapGesture { if item.kind == .unnamed { onTap(item.id) } }
                    }
                }
                .frame(height: 24)
            }
            .frame(height: 24)
            HStack {
                Text("6 AM")
                Spacer()
                Text("Noon")
                Spacer()
                Text("6 PM")
                Spacer()
                Text("Midnight")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Neka.inkTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.isEmpty ? "No suggested activity yet today" : "\(items.count) suggested activities today")
    }

    @ViewBuilder
    private func capsule(_ item: Item) -> some View {
        switch item.kind {
        case .unnamed:
            ZStack {
                Capsule().fill(Neka.rose)
                Text("?")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            .shadow(color: Neka.rose.opacity(pulse ? 0.55 : 0.15), radius: pulse ? 6 : 2)
            .scaleEffect(pulse ? 1.06 : 1)
        case .named:
            Capsule().fill(LinearGradient(colors: [Neka.amber, Neka.orange], startPoint: .leading, endPoint: .trailing))
        case .recorded:
            Capsule().fill(Neka.green)
        }
    }
}

// MARK: - Name it / add it

struct FunActivitySheet: View {
    let target: HomeFunCard.NamingTarget
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var suggestions: [String] = []
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var minutes: Double = 60

    private var bout: ActiveBouts.Bout? {
        if case .bout(let b) = target { return b }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let b = bout {
                        summary(b)
                    } else {
                        manualFields
                    }

                    if !suggestions.isEmpty {
                        section("Your usual") { chips(suggestions) }
                    }
                    section("Pick one") {
                        chips(ActiveBouts.activities.map(\.name).filter { !suggestions.contains($0) })
                    }
                    section("Something else") {
                        HStack(spacing: 8) {
                            TextField("Laser tag, moving furniture…", text: $custom)
                                .submitLabel(.done)
                                .onSubmit { submitCustom() }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
                            Button("Save") { submitCustom() }
                                .font(.system(size: 14, weight: .semibold))
                                .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    if let b = bout {
                        Button {
                            FunActivityService.dismiss(b)
                            onDone()
                            dismiss()
                        } label: {
                            Text("That wasn't anything")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Neka.inkTertiary)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle(bout == nil ? "Add an activity" : "What was it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                let history = FunActivityService.history(context: context)
                let probe = bout ?? ActiveBouts.Bout(start: start, end: start, averageBPM: 0, peakBPM: 0, effort: 0, calories: 0)
                suggestions = Array(ActiveBouts.suggestions(for: probe, history: history).prefix(4))
            }
        }
    }

    private func summary(_ b: ActiveBouts.Bout) -> some View {
        HStack(spacing: 0) {
            stat("\(Int(b.minutes.rounded()))", "min")
            stat("\(Int(b.averageBPM))", "avg bpm")
            stat("\(Int(b.peakBPM))", "peak")
            stat("~\(Int(b.calories))", "cal")
        }
        .padding(.vertical, 14)
        .nekaCard()
        .overlay(alignment: .topLeading) {
            Text("\(HomeFunCard.timeRange(b.start, b.end)) · \(b.intensity)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Neka.inkTertiary)
                .padding(.horizontal, 6)
                .background(Capsule().fill(Neka.paper))
                .offset(x: 12, y: -7)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Neka.display(22, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Neka.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Neka.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var manualFields: some View {
        VStack(spacing: 12) {
            DatePicker("Started", selection: $start, in: ...Date())
            HStack {
                Text("How long")
                Spacer()
                Stepper("\(Int(minutes)) min", value: $minutes, in: 5...600, step: 5)
                    .fixedSize()
            }
        }
        .font(.system(size: 15))
        .padding(16)
        .nekaCard()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            content()
        }
    }

    private func chips(_ names: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
            ForEach(names, id: \.self) { name in
                Button { save(name) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: ActiveBouts.symbol(for: name))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Neka.orangeText)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Neka.orangeSoft))
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Neka.hairline))
                }
                .buttonStyle(.dialedScale)
            }
        }
    }

    /// "sex", "hooked up"… → Intimacy (and its Health entry).
    private func submitCustom() {
        let words = ["sex", "intimacy", "intimate", "sexual activity", "hooked up", "hookup", "made love"]
        if words.contains(custom.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            save(ActiveBouts.intimacy)
        } else {
            save(custom)
        }
    }

    private func save(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let b = bout {
            FunActivityService.name(b, as: trimmed, context: context)
        } else {
            // A rough burn for hand-entered ones: ~6 calories a minute (about 4 for intimacy).
            let perMinute = trimmed == ActiveBouts.intimacy ? 4.0 : 6.0
            FunActivityService.add(name: trimmed, start: start, minutes: minutes, calories: (minutes * perMinute).rounded(),
                                   context: context)
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        onDone()
        dismiss()
    }
}

// MARK: - Earned calories

/// "🔥 +455 calories earned · Strength, Pickleball  ›" — on the Fuel card
/// and Food log. Tap for what earned them.
struct EarnedCaloriesPill: View {
    let earned: EarnedCalories.Day
    @State private var showing = false
    @State private var glow = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(LinearGradient(colors: [Neka.amber, Neka.orange],
                                                             startPoint: .top, endPoint: .bottom)))
                    .scaleEffect(glow ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("+\(Int(earned.earned)) calories earned")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Neka.orangeText)
                        .contentTransition(.numericText(value: earned.earned))
                    Text(earned.sources)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Neka.amberSoft, Neka.orangeSoft], startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.dialedScale)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatCount(3, autoreverses: true)) { glow = true }
        }
        .sheet(isPresented: $showing) {
            EarnedCaloriesSheet(earned: earned)
                .presentationDetents([.medium])
        }
    }
}

/// What earned today's calories, one row per session.
struct EarnedCaloriesSheet: View {
    let earned: EarnedCalories.Day
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("+\(Int(earned.earned))")
                            .font(Neka.display(40, weight: .bold))
                            .foregroundColor(Neka.orangeText)
                        Text("calories added to today's budget")
                            .font(.system(size: 13))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(earned.entries) { e in
                            HStack(spacing: 12) {
                                Image(systemName: e.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Neka.orangeText)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Neka.orangeSoft))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Neka.ink)
                                    Text("\(HomeFunCard.timeRange(e.start, e.end)) · \(Self.sourceText(e.source))")
                                        .font(.system(size: 11))
                                        .foregroundColor(Neka.inkSecondary)
                                }
                                Spacer()
                                Text("+\(Int(e.calories))")
                                    .font(.system(size: 15, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundColor(Neka.ink)
                            }
                            .padding(.vertical, 10)
                            if e.id != earned.entries.last?.id { Divider().overlay(Neka.hairline) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .nekaCard()
                    Text("Watch-recorded workouts use your watch's number. Sessions you logged are estimated from time, distance and your weight. Anything recorded twice counts once.")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle("Earned today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    static func sourceText(_ s: EarnedCalories.Entry.Source) -> String {
        switch s {
        case .watch:  return "measured by your watch"
        case .fun:    return "from heart rate"
        case .logged: return "estimated from your log"
        }
    }
}
