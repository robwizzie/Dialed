//
//  HomeSideBetCard.swift
//  Dialed
//
//  This week's side bet at a glance on Home: you vs your friend, the
//  stake and days left; or a bet waiting for your answer; or what's still
//  owed. Takes no space without a challenge. Tap to open the Challenge tab.
//

import SwiftUI
import SwiftData

struct HomeSideBetCard: View {
    var onOpen: () -> Void = {}

    @Environment(\.modelContext) private var context
    @ObservedObject private var store = SideBetsStore.shared

    var body: some View {
        if WeightChallenge.load() != nil {
            Button(action: onOpen) { content }
                .buttonStyle(.dialedScale)
                .task { await store.refresh(context: context) }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SIDE BET")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.inkTertiary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
            }
            if let bet = store.current {
                SideBetHeader(bet: bet)
                if bet.status == .proposed {
                    Text(bet.proposer == .friend
                         ? "\(store.friendName) wants this bet. Tap to answer."
                         : "Waiting for \(store.friendName) to accept.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(bet.proposer == .friend ? Neka.orangeText : Neka.inkSecondary)
                } else {
                    SideBetBars(bet: bet, friendName: store.friendName)
                }
            } else if let owed = store.ledger.unpaid.first, let w = SideBets.winner(owed, now: Date()),
                      let line = SideBets.owes(owed, winner: w, friendName: store.friendName) {
                HStack(spacing: 10) {
                    Text(w == .you ? "🏆" : "😬").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("Last week's \(owed.metric.title.lowercased()) · not paid yet")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Text("🎲").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No side bet this week")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("Most steps, loser buys wings?")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
            }
        }
        .padding(14)
        .nekaCard()
    }
}
