//
//  HomeQuestsCard.swift
//  Dialed
//
//  Today's three quests, your level and XP bar. Quests check themselves off
//  as your data comes in ("+20 XP" pops when one lands); the few Dialed
//  can't see have a Claim button. Tap the level for badges and habits.
//  Also checks badges now and then so unlocks show up without opening the
//  trophy wall.
//

import SwiftUI
import SwiftData

struct HomeQuestsCard: View {
    @Environment(\.modelContext) private var context
    @State private var today = GameService.Today()
    @State private var lookedAt: Date?
    @State private var badgesCheckedAt: Date?
    @State private var pop: Int?
    @State private var showingTrophies = false
    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { showingTrophies = true } label: { levelHeader }
                .buttonStyle(.dialedScale)

            VStack(spacing: 10) {
                ForEach(today.quests) { row in
                    questRow(row)
                }
            }
            if today.quests.count == 3 {
                let done = today.quests.filter { $0.status == .done }.count
                Text(done == 3 ? "Clean sweep: +\(QuestEngine.sweepBonus) bonus XP 🔥"
                               : "Finish all three for +\(QuestEngine.sweepBonus) bonus XP")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(done == 3 ? Neka.orangeText : Neka.inkTertiary)
            }
        }
        .padding(16)
        .nekaCard()
        .overlay(alignment: .topTrailing) {
            if let pop {
                Text("+\(pop) XP")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LinearGradient(colors: [Neka.green, Neka.sky],
                                                              startPoint: .leading, endPoint: .trailing)))
                    .shadow(color: Neka.green.opacity(0.35), radius: 8, y: 3)
                    .offset(x: -12, y: -14)
                    .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.6)).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                BadgeToast(text: toast)
                    .offset(y: 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in
            if Date().timeIntervalSince(lookedAt ?? .distantPast) > 30 { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .badgesUnlocked)) { note in
            let ids = note.userInfo?["ids"] as? [String] ?? []
            Task { await showToast(for: ids) }
        }
        .sheet(isPresented: $showingTrophies) {
            NavigationStack { TrophyRoomView() }
        }
    }

    // MARK: - Level

    private var levelHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Neka.track, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: today.level.progress)
                    .stroke(LinearGradient(colors: [Neka.green, Neka.sky], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(today.level.number)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText(value: Double(today.level.number)))
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY'S QUESTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.inkTertiary)
                Text("Level \(today.level.number) · \(today.level.title)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text("\(today.level.into) / \(today.level.size) XP to level \(today.level.number + 1)")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(today.xpToday)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(today.xpToday > 0 ? Neka.greenText : Neka.inkTertiary)
                    .contentTransition(.numericText(value: Double(today.xpToday)))
                Text("today")
                    .font(.system(size: 10))
                    .foregroundColor(Neka.inkTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Neka.inkTertiary)
        }
    }

    // MARK: - Quests

    private func questRow(_ row: GameService.QuestRow) -> some View {
        let q = row.quest
        let done = row.status == .done
        let missed = row.status == .missed
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Neka.green : (missed ? Neka.track : Neka.greenSoft))
                Image(systemName: done ? "checkmark" : q.symbol)
                    .font(.system(size: done ? 14 : 13, weight: .bold))
                    .foregroundColor(done ? Neka.onInk : (missed ? Neka.inkTertiary : Neka.greenText))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 36, height: 36)
            .scaleEffect(done ? 1 : 0.94)
            .animation(.spring(response: 0.35, dampingFraction: 0.55), value: done)
            VStack(alignment: .leading, spacing: 1) {
                Text(q.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(missed ? Neka.inkTertiary : Neka.ink)
                    .strikethrough(missed, color: Neka.inkTertiary)
                Text(missed ? "Missed today. Tomorrow's a new set." : q.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if row.status == .claimable {
                Button {
                    GameService.claim(q)
                    Task { await refresh() }
                } label: {
                    Text("Claim")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Neka.onInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
            } else {
                Text("\(q.points) XP")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(done ? Neka.greenText : Neka.inkTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(done ? Neka.greenSoft : Neka.track))
            }
        }
    }

    // MARK: - Data

    private func refresh() async {
        lookedAt = Date()
        let before = today.xpToday
        let firstLoad = today.quests.isEmpty
        let fresh = await GameService.today(context: context)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { today = fresh }
        let gained = fresh.xpToday - before
        if !firstLoad, gained > 0 {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { pop = gained }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeIn(duration: 0.25)) { pop = nil }
        }
        // Badges: at most every 15 minutes from Home.
        if Date().timeIntervalSince(badgesCheckedAt ?? .distantPast) > 15 * 60 {
            badgesCheckedAt = Date()
            _ = await GameService.badges(context: context)
        }
    }

    private func showToast(for ids: [String]) async {
        guard let first = ids.first,
              let badge = BadgeEngine.catalog.first(where: { $0.id == first })
        else { return }
        let text = ids.count == 1 ? "Badge unlocked: \(badge.title)" : "\(ids.count) badges unlocked"
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { toast = text }
        try? await Task.sleep(for: .seconds(3))
        withAnimation(.easeIn(duration: 0.3)) { toast = nil }
    }
}

/// "🏅 Badge unlocked: First 5"
struct BadgeToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "medal.fill")
            Text(text)
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(LinearGradient(colors: [Neka.amber, Neka.orange],
                                                  startPoint: .leading, endPoint: .trailing)))
        .shadow(color: Neka.orange.opacity(0.35), radius: 10, y: 4)
    }
}

/// Badges and habits in one place (from the quests card).
struct TrophyRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Badges").tag(0)
                Text("Habits").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if tab == 0 { BadgesView(embedded: true) } else { HabitHeatmapView(embedded: true) }
        }
        .nekaPageBackground()
        .navigationTitle(tab == 0 ? "Badges" : "Habits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}
