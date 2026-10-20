//
//  PulseCheckView.swift
//  Dialed
//
//  Pulse Check: pick what you're about to do (a scary movie, the big
//  game, a boss fight…), start it, tap when something gets you, end it.
//  Then a recap of your heart rate with the moments that spiked it, and a
//  leaderboard per kind ("your scariest movies").
//

import SwiftUI
import SwiftData

struct PulseCheckView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var store = PulseSessionStore.shared
    @State private var starting: PulseTemplate?
    @State private var showingLive = false
    @State private var recap: PulseSession?
    @State private var board: PulseTemplate = .scaryMovie

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let s = store.active {
                    PulseLiveBanner(session: s) { showingLive = true }
                }
                templatesGrid
                leaderboard
                history
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Pulse Check")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refreshPending(context: context) }
        .refreshable { await store.refreshPending(context: context) }
        .sheet(item: $starting) { template in
            PulseStartSheet(template: template) { showingLive = true }
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showingLive) {
            if let s = store.active {
                PulseLiveView(sessionID: s.id) { ended in
                    showingLive = false
                    recap = ended
                }
            }
        }
        .sheet(item: $recap) { s in
            NavigationStack { PulseRecapView(sessionID: s.id) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's your heart doing?")
                .font(Neka.display(26, weight: .bold))
                .foregroundColor(Neka.ink)
            Text("Start a session, tap when something gets you, end it when it's over. Your watch fills in the heart rate.")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var templatesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(PulseTemplate.allCases) { t in
                Button { starting = t } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.emoji).font(.system(size: 26))
                        Text(t.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(t.pitch)
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(t == .scaryMovie ? Neka.lavenderSoft : Neka.surface))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Neka.hairline))
                }
                .buttonStyle(.dialedScale)
            }
        }
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        let kinds = PulseTemplate.allCases.filter { !store.leaderboard($0).isEmpty }
        return Group {
            if !kinds.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Leaderboard")
                            .font(Neka.title)
                            .foregroundColor(Neka.ink)
                        Spacer()
                        Menu {
                            ForEach(kinds) { k in Button("\(k.emoji) \(k.title)") { board = k } }
                        } label: {
                            Label(board.title, systemImage: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Neka.ink)
                        }
                    }
                    let rows = store.leaderboard(kinds.contains(board) ? board : kinds[0])
                    VStack(spacing: 0) {
                        ForEach(Array(rows.prefix(10).enumerated()), id: \.element.id) { i, s in
                            Button { recap = s } label: { PulseRow(session: s, place: i + 1) }
                                .buttonStyle(.plain)
                            if i < min(rows.count, 10) - 1 { Divider().overlay(Neka.hairline) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .nekaCard()
                }
                .onAppear { if !kinds.contains(board) { board = kinds[0] } }
            }
        }
    }

    // MARK: - History

    private var history: some View {
        let past = store.sessions.filter { !$0.isLive }
        return Group {
            if !past.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("All sessions")
                        .font(Neka.title)
                        .foregroundColor(Neka.ink)
                    VStack(spacing: 0) {
                        ForEach(past) { s in
                            Button { recap = s } label: { PulseRow(session: s, place: nil) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { store.delete(s.id) } label: { Label("Delete", systemImage: "trash") }
                                }
                            if s.id != past.last?.id { Divider().overlay(Neka.hairline) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .nekaCard()
                }
            }
        }
    }
}

// MARK: - Rows & banner

struct PulseRow: View {
    let session: PulseSession
    let place: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let place {
                Text(place <= 3 ? ["🥇", "🥈", "🥉"][place - 1] : "\(place)")
                    .font(.system(size: place <= 3 ? 20 : 14, weight: .bold))
                    .frame(width: 26)
            }
            PulsePoster(url: session.posterURL, template: session.template)
                .frame(width: 38, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if session.hasHeartRate {
                VStack(spacing: 0) {
                    Text("\(session.score)")
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Neka.ink)
                    Text(session.template.scoreName.components(separatedBy: " ").first ?? "")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
            } else if session.awaitingSync {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts = [session.start.formatted(.dateTime.month(.abbreviated).day())]
        if let r = session.result, r.hasData {
            parts.append("peak \(Int(r.peak)) bpm")
            parts.append("\(r.moments.count) \(session.template.momentName.lowercased())\(r.moments.count == 1 ? "" : "s")")
        } else if session.awaitingSync {
            parts.append("waiting for your watch")
        }
        return parts.joined(separator: " · ")
    }
}

/// A movie poster, or the template's emoji on a tinted tile.
struct PulsePoster: View {
    let url: URL?
    let template: PulseTemplate

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Neka.lavenderSoft)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(template.emoji)
                }
            } else {
                Text(template.emoji).font(.system(size: 20))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PulseLiveBanner: View {
    let session: PulseSession
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Circle().fill(Neka.rose).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.template.emoji) \(session.title)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(1)
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("Live · \(PulseAnalyzer.clock(ctx.date.timeIntervalSince(session.start)))")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
                Spacer()
                Text("Open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.onInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Neka.ink))
            }
            .padding(14)
            .nekaCard()
        }
        .buttonStyle(.dialedScale)
    }
}

// MARK: - Start

struct PulseStartSheet: View {
    let template: PulseTemplate
    var onStarted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MovieSearch.Movie] = []
    @State private var searching = false
    @State private var picked: MovieSearch.Movie?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text(template.emoji).font(.system(size: 40))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(Neka.display(22, weight: .bold))
                                .foregroundColor(Neka.ink)
                            Text(template.pitch)
                                .font(.system(size: 13))
                                .foregroundColor(Neka.inkSecondary)
                        }
                    }
                    TextField(template.titlePrompt, text: $query)
                        .font(.system(size: 17))
                        .submitLabel(.search)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.track))
                        .onChange(of: query) { _, _ in picked = nil }

                    if template.searchesMovies { movieResults }

                    Text("Wear your watch. Heart rate comes in from Apple Health or your Pixel Watch, sometimes a few minutes behind; the recap fills in once it syncs.")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Text(startLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Neka.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle("Start")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                guard template.searchesMovies, picked == nil else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                searching = true
                results = await MovieSearch.search(query)
                searching = false
            }
        }
    }

    private var startLabel: String {
        if let picked { return "Start \(picked.title)" }
        let t = query.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Start \(template.title.lowercased())" : "Start \(t)"
    }

    @ViewBuilder
    private var movieResults: some View {
        if searching && results.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        }
        VStack(spacing: 8) {
            ForEach(results) { m in
                Button {
                    picked = m
                    #if os(iOS)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                } label: {
                    HStack(spacing: 12) {
                        PulsePoster(url: m.poster, template: template)
                            .frame(width: 44, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Neka.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text([m.year, m.genre].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12))
                                .foregroundColor(Neka.inkSecondary)
                        }
                        Spacer()
                        if picked == m {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(Neka.green)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(picked == m ? Neka.greenSoft : Neka.surface))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func start() {
        let title = picked?.title ?? query
        let subtitle = picked.flatMap { m in [m.year, m.genre].compactMap { $0 }.joined(separator: " · ") }
        PulseSessionStore.shared.start(template, title: title, subtitle: subtitle, posterURL: picked?.poster)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onStarted() }
    }
}

// MARK: - Live

struct PulseLiveView: View {
    let sessionID: UUID
    /// Called with the session when it ends (to show its recap), or nil when just closed.
    var onClose: (PulseSession?) -> Void

    @Environment(\.modelContext) private var context
    @ObservedObject private var store = PulseSessionStore.shared
    @State private var confirmEnd = false
    @State private var bump = false

    private var session: PulseSession? { store.session(sessionID) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.05, blue: 0.12), Color(red: 0.2, green: 0.05, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if let s = session {
                VStack(spacing: 22) {
                    HStack {
                        Button { onClose(nil) } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(.white.opacity(0.12)))
                        }
                        Spacer()
                        Text("● LIVE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Neka.rose)
                    }
                    VStack(spacing: 6) {
                        Text("\(s.template.emoji) \(s.title)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(PulseAnalyzer.clock(ctx.date.timeIntervalSince(s.start)))
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                    }
                    heartRate
                    Spacer(minLength: 0)
                    Button {
                        store.mark(s.id)
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { bump.toggle() }
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        #endif
                    } label: {
                        VStack(spacing: 6) {
                            Text(s.template.markButton)
                                .font(.system(size: 22, weight: .heavy))
                            Text(s.marks.isEmpty ? "Tap whenever it gets you" : "\(s.marks.count) marked")
                                .font(.system(size: 13, weight: .medium))
                                .opacity(0.8)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                        .background(RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(LinearGradient(colors: [Neka.rose, Neka.orange], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .scaleEffect(bump ? 1.03 : 1)
                    }
                    .buttonStyle(.plain)
                    Button { confirmEnd = true } label: {
                        Text("End \(s.template == .scaryMovie ? "movie" : "session")")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().stroke(.white.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
                    Button("End and see recap") {
                        store.end(s.id)
                        onClose(store.session(s.id))
                    }
                }
            }
        }
        .task {
            // Watches sync on their own clock; check once a minute.
            while !Task.isCancelled {
                await store.pollLive(context: context)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    @ViewBuilder
    private var heartRate: some View {
        VStack(spacing: 8) {
            if let live = store.live {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "heart.fill").foregroundColor(Neka.rose)
                    Text("\(Int(live.bpm))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("bpm")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    let ago = Int(ctx.date.timeIntervalSince(live.at) / 60)
                    Text(ago < 1 ? "just now" : "\(ago) min ago · your watch syncs every few minutes")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                if store.liveSamples.count >= 3 {
                    NekaSparkline(values: store.liveSamples.suffix(40).map(\.bpm), color: Neka.rose)
                        .frame(height: 44)
                        .padding(.horizontal, 30)
                }
            } else {
                Text("Heart rate shows up as your watch syncs. Keep it on.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
