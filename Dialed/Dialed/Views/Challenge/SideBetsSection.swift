//
//  SideBetsSection.swift
//  Dialed
//
//  The Challenge tab's side bets: this week's battle (you vs your friend,
//  live bars, days left, the stake), answering or proposing a bet, typing
//  in your friend's number when their side can't post it, and the ledger
//  of who owes what with "mark paid".
//

import SwiftUI
import SwiftData

struct SideBetsSection: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var store = SideBetsStore.shared
    @State private var proposing = false
    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Side bets")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                let l = store.ledger
                if l.wins + l.losses + l.ties > 0 {
                    NekaPill(text: "You \(l.wins)–\(l.losses)\(l.ties > 0 ? "–\(l.ties)" : "")", tint: Neka.lavenderText, fill: Neka.lavenderSoft)
                }
            }

            if let bet = store.current {
                currentCard(bet)
            } else {
                startCard
            }

            ForEach(store.awaitingScores) { bet in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(bet.metric.title) · week of \(Self.weekLabel(bet.week))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    FriendScoreField(bet: bet, friendName: store.friendName)
                }
                .padding(14)
                .nekaCard()
            }

            if !store.ledger.unpaid.isEmpty { ledgerCard }
            if !store.history.isEmpty { historyCard }

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.rose)
            }
        }
        .task { await store.refresh(context: context) }
        .sheet(isPresented: $proposing) {
            ProposeBetSheet(friendName: store.friendName)
                .presentationDetents([.large])
        }
    }

    // MARK: - This week

    @ViewBuilder
    private func currentCard(_ bet: SideBets.Bet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SideBetHeader(bet: bet)
            switch bet.status {
            case .proposed where bet.proposer == .friend:
                Text("\(store.friendName) wants this bet for the week. You in?")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                HStack(spacing: 10) {
                    Button { Task { await store.respond(bet, accept: true, context: context) } } label: {
                        Text("Accept 🤝")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.onInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Neka.ink))
                    }
                    Button { Task { await store.respond(bet, accept: false, context: context) } } label: {
                        Text("Pass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Neka.track))
                    }
                }
                .buttonStyle(.dialedScale)
                .disabled(store.isWorking)
            case .proposed:
                HStack {
                    Label("Waiting for \(store.friendName) to accept", systemImage: "hourglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                    Spacer()
                    Button("Cancel") { Task { await store.cancel(bet) } }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.rose)
                }
            default:
                SideBetBars(bet: bet, friendName: store.friendName)
                if bet.friendScore == nil || !store.usesServer {
                    FriendScoreField(bet: bet, friendName: store.friendName)
                }
            }
        }
        .padding(16)
        .nekaCard(wash: .mint)
    }

    private var startCard: some View {
        Button { proposing = true } label: {
            HStack(spacing: 12) {
                Text("🎲")
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Neka.lavenderSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a side bet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("One stat, this week, something on the line. Loser buys wings?")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .nekaCard()
        }
        .buttonStyle(.dialedScale)
    }

    // MARK: - Ledger

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHO OWES WHAT")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(Neka.inkTertiary)
                .padding(.bottom, 6)
            ForEach(store.ledger.unpaid) { bet in
                if let w = SideBets.winner(bet, now: Date()), let line = SideBets.owes(bet, winner: w, friendName: store.friendName) {
                    HStack(spacing: 10) {
                        Text(w == .you ? "🏆" : "😬")
                            .font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Neka.ink)
                            Text("\(bet.metric.title) · week of \(Self.weekLabel(bet.week))")
                                .font(.system(size: 11))
                                .foregroundColor(Neka.inkSecondary)
                        }
                        Spacer()
                        Button("Mark paid") { Task { await store.setPaid(bet, true) } }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Neka.track))
                            .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(14)
        .nekaCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation { showHistory.toggle() } } label: {
                HStack {
                    Text("Past bets (\(store.history.count))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Spacer()
                    Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            .buttonStyle(.plain)
            if showHistory {
                ForEach(store.history) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.bet.metric.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.inkSecondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.winner == .you ? "Won" : item.winner == .friend ? "Lost" : "Tied")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(item.winner == .you ? Neka.greenText : item.winner == .friend ? Neka.rose : Neka.inkSecondary)
                            Text("\(item.bet.metric.title) · \(item.bet.metric.number(item.bet.youScore ?? 0)) vs \(item.bet.metric.number(item.bet.friendScore ?? 0))")
                                .font(.system(size: 11))
                                .foregroundColor(Neka.inkSecondary)
                        }
                        Spacer()
                        if item.winner != .tie {
                            Button(item.bet.paid ? "Paid ✓" : "Unpaid") { Task { await store.setPaid(item.bet, !item.bet.paid) } }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(item.bet.paid ? Neka.greenText : Neka.inkSecondary)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 7)
                }
            }
        }
        .padding(14)
        .nekaCard()
    }

    static func weekLabel(_ key: String) -> String {
        ChallengeWire.date(fromKey: key).map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? key
    }
}

// MARK: - Pieces

/// Metric, stake, days left.
struct SideBetHeader: View {
    let bet: SideBets.Bet

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: bet.metric.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Neka.lavenderText)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Neka.lavenderSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(bet.metric.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(bet.stake)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.orangeText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            let left = SideBets.daysLeft(bet, now: Date())
            Text(left == 0 ? "Final" : "\(left) day\(left == 1 ? "" : "s") left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
        }
    }
}

/// You vs your friend, live.
struct SideBetBars: View {
    let bet: SideBets.Bet
    let friendName: String

    var body: some View {
        let you = bet.youScore ?? 0, them = bet.friendScore ?? 0
        let top = max(1, you, them)
        let leader = SideBets.leader(bet.metric, you: bet.youScore, friend: bet.friendScore)
        VStack(alignment: .leading, spacing: 8) {
            bar("You", value: bet.youScore, fraction: you / top, tint: Neka.orange, leading: leader == .you)
            bar(friendName, value: bet.friendScore, fraction: them / top, tint: Neka.lavender, leading: leader == .friend)
            Text(caption(leader))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
    }

    private func bar(_ name: String, value: Double?, fraction: Double, tint: Color, leading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name + (leading ? " 👑" : ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Text(value.map { bet.metric.number($0) } ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(Neka.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track)
                    Capsule().fill(tint).frame(width: max(6, geo.size.width * min(1, fraction)))
                }
            }
            .frame(height: 8)
        }
    }

    private func caption(_ leader: SideBets.Side?) -> String {
        guard let leader else { return "Waiting on \(friendName)'s number." }
        let gap = abs((bet.youScore ?? 0) - (bet.friendScore ?? 0))
        switch leader {
        case .tie:    return "Dead even. Somebody blink."
        case .you:    return "You're up by \(bet.metric.format(gap)). Keep it."
        case .friend: return "\(friendName) is up by \(bet.metric.format(gap)). Time to answer."
        }
    }
}

/// Type your friend's number when their side can't post it.
struct FriendScoreField: View {
    let bet: SideBets.Bet
    let friendName: String
    @ObservedObject private var store = SideBetsStore.shared
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("\(friendName)'s total", text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: 15))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
            Button("Save") {
                store.setFriendScore(bet, Double(text.replacingOccurrences(of: ",", with: "")))
            }
            .font(.system(size: 14, weight: .semibold))
            .disabled(Double(text.replacingOccurrences(of: ",", with: "")) == nil)
        }
        .onAppear { text = bet.friendScore.map { bet.metric.number($0).replacingOccurrences(of: ",", with: "") } ?? "" }
    }
}

// MARK: - Propose

struct ProposeBetSheet: View {
    let friendName: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SideBetsStore.shared
    @State private var metric: SideBets.Metric = .steps
    @State private var stake = SideBets.presets[0]
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("The battle") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(SideBets.Metric.allCases) { m in
                                Button { metric = m } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: m.symbol)
                                            .font(.system(size: 14, weight: .semibold))
                                            .frame(width: 20)
                                        Text(m.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundColor(metric == m ? Neka.onInk : Neka.ink)
                                    .padding(12)
                                    .frame(minHeight: 54)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(metric == m ? Neka.ink : Neka.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Neka.hairline))
                                }
                                .buttonStyle(.dialedScale)
                            }
                        }
                    }
                    section("The stakes") {
                        VStack(spacing: 8) {
                            ForEach(SideBets.presets, id: \.self) { p in
                                Button { stake = p; custom = "" } label: {
                                    HStack {
                                        Text(p)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Neka.ink)
                                        Spacer()
                                        if stake == p && custom.isEmpty {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(Neka.green)
                                        }
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.surface))
                                }
                                .buttonStyle(.plain)
                            }
                            TextField("Or your own: Loser mows the lawn", text: $custom)
                                .font(.system(size: 14))
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
                        }
                    }
                    Text(store.usesServer
                         ? "\(friendName) gets it on their challenge page to accept. Your number updates on its own; they post theirs."
                         : "Not synced with \(friendName)'s page, so it starts now. Your number updates on its own; type theirs in as the week goes.")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                    Button {
                        Task {
                            await store.propose(metric: metric, stake: custom.isEmpty ? stake : custom, context: context)
                            if store.lastError == nil { dismiss() }
                        }
                    } label: {
                        Text(store.usesServer ? "Send bet to \(friendName) 🎲" : "Start bet 🎲")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.onInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Neka.ink))
                    }
                    .buttonStyle(.dialedScale)
                    .disabled(store.isWorking)
                    if let error = store.lastError {
                        Text(error).font(.system(size: 12)).foregroundColor(Neka.rose)
                    }
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle("Side bet this week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            content()
        }
    }
}
