//
//  PulseRecapView.swift
//  Dialed
//
//  The recap: your heart rate across the whole session with the moments
//  that spiked it pinned on the line, the score, your own ratings, where
//  it lands on your leaderboard, and a share card.
//

import SwiftUI
import SwiftData
import Charts

struct PulseRecapView: View {
    let sessionID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PulseSessionStore.shared
    @State private var selected: PulseAnalyzer.Moment?
    @State private var fetching = false
    @State private var poster: UIImage?
    @State private var shareImage: Image?
    @State private var notes = ""

    private var session: PulseSession? { store.session(sessionID) }

    var body: some View {
        ScrollView {
            if let s = session {
                VStack(alignment: .leading, spacing: 16) {
                    hero(s)
                    if let r = s.result, r.hasData {
                        chartCard(s, r)
                        stats(s, r)
                        momentsList(s, r)
                    } else {
                        waiting(s)
                    }
                    ratings(s)
                    board(s)
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview("\(s.title) — Pulse Check", image: shareImage)) {
                            Label("Share recap", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Neka.onInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Capsule().fill(Neka.ink))
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .nekaPageBackground()
        .navigationTitle("Recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            notes = session?.notes ?? ""
            await loadPoster()
            await fetchIfNeeded()
            renderShare()
        }
        .task(id: session?.hasHeartRate) {
            // Watch hasn't synced yet: look again every two minutes while open.
            guard let s = session, s.awaitingSync else { return }
            while !Task.isCancelled, session?.awaitingSync == true {
                try? await Task.sleep(for: .seconds(120))
                await fetch()
            }
        }
        .onChange(of: session?.result) { _, _ in renderShare() }
        .onChange(of: session?.felt) { _, _ in renderShare() }
        .onChange(of: session?.rating) { _, _ in renderShare() }
    }

    // MARK: - Hero

    private func hero(_ s: PulseSession) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PulsePoster(url: s.posterURL, template: s.template)
                .frame(width: 84, height: 122)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(s.title)
                    .font(Neka.display(22, weight: .bold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(3)
                Text([s.subtitle, s.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                      PulseAnalyzer.clock(s.duration)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                if let r = s.result, r.hasData {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(r.score)")
                            .font(Neka.display(40, weight: .bold))
                            .foregroundColor(Self.tint(r.score))
                        Text(s.template.scoreName.lowercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Text(s.template.verdict(r.score))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Neka.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let place = store.place(of: s) {
                        Text(place == 1 ? "🏆 #1 on your \(s.template.title.lowercased()) board" : "#\(place) on your \(s.template.title.lowercased()) board")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Neka.lavenderText)
                    }
                }
            }
        }
    }

    static func tint(_ score: Int) -> Color {
        score >= 70 ? Neka.rose : score >= 40 ? Neka.orange : Neka.green
    }

    // MARK: - Chart

    private func chartCard(_ s: PulseSession, _ r: PulseAnalyzer.Result) -> some View {
        let samples = s.samples.filter { $0.t >= 0 && $0.t <= r.duration }
        let lo = max(40, (samples.map(\.bpm).min() ?? r.baseline) - 8)
        let hi = (samples.map(\.bpm).max() ?? r.peak) + 10
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Heart rate")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                Text("baseline \(Int(r.baseline)) bpm")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            Chart {
                RectangleMark(xStart: .value("Start", 0.0), xEnd: .value("End", r.duration / 60),
                              yStart: .value("Low", r.baseline - 4), yEnd: .value("High", r.baseline + 4))
                    .foregroundStyle(Neka.green.opacity(0.12))
                ForEach(Array(samples.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Minute", p.t / 60), y: .value("bpm", p.bpm))
                        .foregroundStyle(LinearGradient(colors: [Neka.lavender, Neka.rose], startPoint: .bottom, endPoint: .top))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                ForEach(r.moments) { m in
                    PointMark(x: .value("Minute", m.t / 60), y: .value("bpm", m.peak))
                        .symbolSize(selected?.id == m.id ? 160 : 70)
                        .foregroundStyle(m.marked ? Neka.rose : Neka.orange)
                        .annotation(position: .top, spacing: 2) {
                            Text("+\(Int(m.delta))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(m.marked ? Neka.roseText : Neka.orangeText)
                        }
                }
                ForEach(Array(r.unmatchedMarks.enumerated()), id: \.offset) { _, t in
                    RuleMark(x: .value("Mark", t / 60))
                        .foregroundStyle(Neka.rose.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxisLabel("minutes", alignment: .trailing)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geo[plot].origin.x
                            guard let minute: Double = proxy.value(atX: x) else { return }
                            selected = r.moments.min { abs($0.t / 60 - minute) < abs($1.t / 60 - minute) }
                        }
                }
            }
            .frame(height: 220)
            if let m = selected {
                Text("\(PulseAnalyzer.clock(m.t)) · +\(Int(m.delta)) bpm (\(Int(m.peak)) peak)\(m.marked ? " · marked by you" : "")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Neka.track))
            } else {
                Text("Tap a dot to see the moment. Red dots are ones you marked.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func stats(_ s: PulseSession, _ r: PulseAnalyzer.Result) -> some View {
        HStack(spacing: 8) {
            stat("\(Int(r.peak))", "peak bpm")
            stat("\(Int(r.average))", "average")
            stat("\(r.moments.count)", s.template.momentName.lowercased() + (r.moments.count == 1 ? "" : "s"))
            stat("\(Int(r.minutesElevated))", s.template.direction == .dip ? "min calm" : "min elevated")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundColor(Neka.ink)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))
    }

    private func momentsList(_ s: PulseSession, _ r: PulseAnalyzer.Result) -> some View {
        let top = r.moments.sorted { $0.delta > $1.delta }.prefix(5)
        return Group {
            if !top.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.template == .scaryMovie ? "Scariest moments" : "Biggest moments")
                        .font(Neka.title)
                        .foregroundColor(Neka.ink)
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, m in
                        Button { selected = m } label: {
                            HStack(spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Neka.onInk)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Self.tint(Int(m.delta * 2.5))))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(PulseAnalyzer.clock(m.t)) · +\(Int(m.delta)) bpm")
                                        .font(.system(size: 14, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundColor(Neka.ink)
                                    Text("\(Int(m.baseline)) → \(Int(m.peak)) bpm\(m.marked ? " · you marked it" : "")")
                                        .font(.system(size: 11))
                                        .foregroundColor(Neka.inkSecondary)
                                }
                                Spacer()
                                if m.marked { Text("😱") }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected?.id == m.id ? Neka.roseSoft : Neka.surface))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Waiting

    private func waiting(_ s: PulseSession) -> some View {
        VStack(spacing: 10) {
            if fetching {
                ProgressView()
            } else {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 30))
                    .foregroundColor(Neka.inkTertiary)
            }
            Text(s.awaitingSync ? "Waiting for your watch to sync…" : "No heart rate for this window")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text(s.awaitingSync
                 ? "Pixel Watch and Apple Health can take a few minutes to send heart rate. Dialed checks again every couple of minutes."
                 : "Your watch didn't record heart rate during this session.")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
            Button { Task { await fetch() } } label: {
                Label("Check now", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Neka.track))
            }
            .disabled(fetching)
            if !s.marks.isEmpty {
                Text("\(s.marks.count) moment\(s.marks.count == 1 ? "" : "s") marked: " + s.marks.map(PulseAnalyzer.clock).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .nekaCard()
    }

    // MARK: - Ratings

    private func ratings(_ s: PulseSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your take")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            ratingRow(s.template == .scaryMovie ? "Movie rating" : "Rating", value: s.rating, emoji: "⭐️") {
                store.setRating(s.id, rating: $0)
            }
            ratingRow(s.template.feltLabel, value: s.felt, emoji: s.template == .scaryMovie ? "😱" : "💓") {
                store.setFelt(s.id, felt: $0)
            }
            TextField("Notes (the scene that got you…)", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 14))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
                .onChange(of: notes) { _, v in store.setNotes(s.id, notes: v) }
        }
        .padding(16)
        .nekaCard()
    }

    private func ratingRow(_ title: String, value: Double?, emoji: String, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                Text(value.map { "\(emoji) \(Int($0))/10" } ?? "Tap to rate")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(value == nil ? Neka.inkTertiary : Neka.ink)
            }
            Slider(value: Binding(get: { value ?? 5 }, set: { set($0.rounded()) }), in: 0...10, step: 1)
                .tint(Neka.rose)
        }
    }

    // MARK: - Leaderboard

    private func board(_ s: PulseSession) -> some View {
        let rows = store.leaderboard(s.template)
        return Group {
            if rows.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.template == .scaryMovie ? "Your scariest movies" : "Your \(s.template.title.lowercased()) board")
                        .font(Neka.title)
                        .foregroundColor(Neka.ink)
                    VStack(spacing: 0) {
                        ForEach(Array(rows.prefix(8).enumerated()), id: \.element.id) { i, row in
                            PulseRow(session: row, place: i + 1)
                                .padding(.horizontal, 8)
                                .background(row.id == s.id ? Neka.lavenderSoft : .clear)
                        }
                    }
                    .padding(.horizontal, 8)
                    .nekaCard()
                }
            }
        }
    }

    // MARK: - Loading

    private func fetchIfNeeded() async {
        guard let s = session, !s.isLive else { return }
        if !s.hasHeartRate || s.result == nil { await fetch() }
    }

    private func fetch() async {
        fetching = true
        await store.fetchHeartRate(sessionID, context: context)
        fetching = false
    }

    private func loadPoster() async {
        guard let url = session?.posterURL, poster == nil,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        poster = UIImage(data: data)
        renderShare()
    }

    @MainActor
    private func renderShare() {
        guard let s = session else { return }
        let renderer = ImageRenderer(content: PulseShareCard(session: s, poster: poster).frame(width: 360))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

// MARK: - Share card

struct PulseShareCard: View {
    let session: PulseSession
    let poster: UIImage?

    var body: some View {
        let r = session.result
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let poster {
                        Image(uiImage: poster).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(0.08)
                            Text(session.template.emoji).font(.system(size: 40))
                        }
                    }
                }
                .frame(width: 96, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("PULSE CHECK · \(session.template.title.uppercased())")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.6))
                    Text(session.title)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(3)
                    if let r, r.hasData {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(r.score)")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("/100 \(session.template.scoreName.lowercased())")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            if let r, r.hasData {
                NekaSparkline(values: session.samples.filter { $0.t >= 0 && $0.t <= r.duration }.map(\.bpm),
                              color: .white, lineWidth: 2, fill: true)
                    .frame(height: 60)
                if let b = r.biggest {
                    Text("My heart hit \(Int(b.peak)) bpm at \(PulseAnalyzer.clock(b.t)) (+\(Int(b.delta)))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                HStack(spacing: 16) {
                    shareStat("\(r.moments.count)", session.template.momentName.lowercased() + (r.moments.count == 1 ? "" : "s"))
                    shareStat("\(Int(r.peak))", "peak bpm")
                    if let felt = session.felt { shareStat("\(Int(felt))/10", "felt") }
                    if let rating = session.rating { shareStat("\(Int(rating))/10", "rating") }
                }
            }
            Text("Tracked with Dialed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.12, green: 0.05, blue: 0.18), Color(red: 0.45, green: 0.08, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func shareStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}
