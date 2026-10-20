//
//  HomeFunCard.swift
//  Dialed
//
//  "Fun stuff" on Home: the active stretches your heart rate gave away
//  (tap to say what it was, with your usual picks first), the ones you've
//  named, and anything your watch recorded that isn't the gym. Plus a
//  quick way to add one by hand.
//

import SwiftUI
import SwiftData

struct HomeFunCard: View {
    @Environment(\.modelContext) private var context
    @State private var day = FunActivityService.Day()
    @State private var lookedAt: Date?
    @State private var naming: NamingTarget?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FUN STUFF")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text(day.isEmpty ? "Played something today?" : "\(Int(day.minutes.rounded())) active min")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                }
                Spacer()
                Button { naming = .manual } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
                .accessibilityLabel("Add a fun activity")
            }

            ForEach(day.unnamed) { bout in
                Button { naming = .bout(bout) } label: { boutRow(bout) }
                    .buttonStyle(.dialedScale)
            }
            ForEach(day.logged, id: \.id) { e in
                loggedRow(name: e.text ?? "Activity", start: e.timestamp, minutes: e.value ?? 0,
                          calories: e.secondaryValue, detail: nil)
                    .contextMenu {
                        Button(role: .destructive) { FunActivityService.delete(e, context: context) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            ForEach(day.recorded) { w in
                loggedRow(name: w.title, start: w.start, minutes: w.minutes,
                          calories: w.calories.map(Double.init), detail: w.source)
            }
        }
        .padding(14)
        .nekaCard()
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
            if Date().timeIntervalSince(lookedAt ?? .distantPast) > 60 { Task { await refresh() } }
        }
        .sheet(item: $naming) { target in
            FunActivitySheet(target: target) { Task { await refresh() } }
                .presentationDetents([.medium, .large])
        }
    }

    private func boutRow(_ b: ActiveBouts.Bout) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Neka.rose)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Neka.roseSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text("You were moving \(Self.timeRange(b.start, b.end))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                Text("\(Int(b.minutes.rounded())) min · avg \(Int(b.averageBPM)) bpm · ~\(Int(b.calories)) cal")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("What was it?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.onInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Neka.ink))
        }
    }

    private func loggedRow(name: String, start: Date, minutes: Double, calories: Double?, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ActiveBouts.symbol(for: name))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Neka.orangeText)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Neka.orangeSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text([start.formatted(.dateTime.hour().minute()), "\(Int(minutes.rounded())) min",
                      calories.map { "~\(Int($0)) cal" }, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    static func timeRange(_ a: Date, _ b: Date) -> String {
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(a.formatted(f))–\(b.formatted(f))"
    }

    private func refresh() async {
        lookedAt = Date()
        let found = await FunActivityService.day(Date(), context: context)
        withAnimation(.easeOut(duration: 0.25)) { day = found }
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
    @State private var askProtection = false

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
            .navigationTitle(bout == nil ? "Add fun activity" : "What was it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Protection used?", isPresented: $askProtection, titleVisibility: .visible) {
                Button("Yes") { save(ActiveBouts.intimacy, protection: true) }
                Button("No") { save(ActiveBouts.intimacy, protection: false) }
                Button("Skip") { save(ActiveBouts.intimacy, protection: nil) }
            } message: {
                Text("Saved to Apple Health's Sexual Activity, which only you can see.")
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
                Button {
                    if name == ActiveBouts.intimacy { askProtection = true } else { save(name) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: ActiveBouts.symbol(for: name))
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 20)
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Neka.hairline))
                }
                .buttonStyle(.dialedScale)
            }
        }
    }

    /// "sex", "hooked up"… → Intimacy (and its Health entry).
    private func submitCustom() {
        let words = ["sex", "intimacy", "intimate", "sexual activity", "hooked up", "hookup", "made love"]
        if words.contains(custom.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            askProtection = true
        } else {
            save(custom)
        }
    }

    private func save(_ name: String, protection: Bool? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let b = bout {
            FunActivityService.name(b, as: trimmed, protectionUsed: protection, context: context)
        } else {
            // A rough burn for hand-entered ones: ~6 calories a minute (about 4 for intimacy).
            let perMinute = trimmed == ActiveBouts.intimacy ? 4.0 : 6.0
            FunActivityService.add(name: trimmed, start: start, minutes: minutes, calories: (minutes * perMinute).rounded(),
                                   protectionUsed: protection, context: context)
        }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        onDone()
        dismiss()
    }
}
