//
//  HomePulseCard.swift
//  Dialed
//
//  Pulse Check on Home: a live session in progress (timer, "That got
//  me!" and End), a "your recap is ready" nudge after one, or quick
//  starts for a scary movie or the game.
//

import SwiftUI
import SwiftData

struct HomePulseCard: View {
    /// Opens the full Pulse Check screen.
    var onOpen: () -> Void = {}

    @Environment(\.modelContext) private var context
    @ObservedObject private var store = PulseSessionStore.shared
    @State private var starting: PulseTemplate?
    @State private var showingLive = false
    @State private var recap: PulseSession?

    var body: some View {
        Group {
            if let s = store.active {
                live(s)
            } else if let last = recentRecap {
                ready(last)
            } else {
                quickStart
            }
        }
        .task { await store.refreshPending(context: context) }
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

    /// A session that ended in the last 12 hours.
    private var recentRecap: PulseSession? {
        store.sessions.first { s in
            guard let end = s.end else { return false }
            return Date().timeIntervalSince(end) < 12 * 3600
        }
    }

    // MARK: - Live

    private func live(_ s: PulseSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Neka.rose).frame(width: 9, height: 9)
                Text("PULSE CHECK · LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.roseText)
                Spacer()
                SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(PulseAnalyzer.clock(ctx.date.timeIntervalSince(s.start)))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Neka.ink)
                }
            }
            Text("\(s.template.emoji) \(s.title)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Neka.ink)
                .lineLimit(1)
            HStack(spacing: 10) {
                Button {
                    store.mark(s.id)
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    #endif
                } label: {
                    Text(s.template.markButton)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(LinearGradient(colors: [Neka.rose, Neka.orange],
                                                                  startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(.dialedScale)
                Button { showingLive = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
                .accessibilityLabel("Open live session")
            }
            if !s.marks.isEmpty {
                Text("\(s.marks.count) marked so far")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous).fill(Neka.roseSoft))
    }

    // MARK: - Recap ready

    private func ready(_ s: PulseSession) -> some View {
        Button { recap = s } label: {
            HStack(spacing: 12) {
                PulsePoster(url: s.posterURL, template: s.template)
                    .frame(width: 42, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PULSE CHECK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text(s.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(1)
                    Text(readyLine(s))
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if s.hasHeartRate {
                    Text("\(s.score)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(PulseRecapView.tint(s.score))
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .padding(14)
            .nekaCard()
        }
        .buttonStyle(.dialedScale)
        .contextMenu {
            Button { onOpen() } label: { Label("All Pulse Check sessions", systemImage: "waveform.path.ecg") }
        }
    }

    private func readyLine(_ s: PulseSession) -> String {
        if let r = s.result, r.hasData, let b = r.biggest {
            return "Peak \(Int(r.peak)) bpm · biggest +\(Int(b.delta)) at \(PulseAnalyzer.clock(b.t))"
        }
        return s.awaitingSync ? "Recap fills in when your watch syncs" : "See your recap"
    }

    // MARK: - Quick start

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PULSE CHECK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text("Track your heart through a movie or the game")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                }
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Neka.inkTertiary)
                }
                .accessibilityLabel("All Pulse Check sessions")
            }
            HStack(spacing: 8) {
                quick(.scaryMovie, "Scary movie")
                quick(.sportsGame, "The game")
                Button(action: onOpen) {
                    Text("More")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func quick(_ t: PulseTemplate, _ label: String) -> some View {
        Button { starting = t } label: {
            Text("\(t.emoji) \(label)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(Neka.ink))
        }
        .buttonStyle(.dialedScale)
    }
}
