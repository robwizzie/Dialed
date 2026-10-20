//
//  HomeBadgesStrip.swift
//  Dialed
//
//  A slim row on Home: your latest medals, how many you've earned, and the
//  one you're closest to. Tap for the trophy wall.
//

import SwiftUI
import SwiftData

struct HomeBadgesStrip: View {
    @Environment(\.modelContext) private var context
    @State private var statuses: [BadgeEngine.Status] = []
    @State private var showing = false

    private var earned: [BadgeEngine.Status] {
        let store = GameStore.load()
        return statuses.filter(\.unlocked)
            .sorted { (store.badges[$0.badge.id] ?? .distantPast) > (store.badges[$1.badge.id] ?? .distantPast) }
    }

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(earned.prefix(4)) { s in
                        BadgeMedal(badge: s.badge, unlocked: true, size: 34)
                            .overlay(Circle().stroke(Neka.surface, lineWidth: 2))
                    }
                    if earned.isEmpty {
                        Image(systemName: "medal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Neka.inkTertiary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Neka.track))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(earned.count) of \(statuses.count) badges")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    if let next = statuses.filter({ !$0.unlocked }).max(by: { $0.progress < $1.progress }) {
                        Text("Next: \(next.badge.title) · \(next.progressText)")
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .nekaCard()
        }
        .buttonStyle(.dialedScale)
        .task { statuses = await GameService.badges(context: context) }
        .onReceive(NotificationCenter.default.publisher(for: .badgesUnlocked)) { _ in
            Task { statuses = await GameService.badges(context: context) }
        }
        .sheet(isPresented: $showing) {
            NavigationStack { TrophyRoomView() }
        }
    }
}
