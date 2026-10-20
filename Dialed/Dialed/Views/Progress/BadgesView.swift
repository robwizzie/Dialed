//
//  BadgesView.swift
//  Dialed
//
//  The trophy wall: unlocked badges in their tier colors with the day you
//  earned them, locked ones greyed out with a progress ring ("10 of 14
//  days"). Tap one for the story and a share card.
//

import SwiftUI
import SwiftData

struct BadgesView: View {
    /// Inside TrophyRoomView (which owns the navigation bar).
    var embedded = false

    @Environment(\.modelContext) private var context
    @State private var statuses: [BadgeEngine.Status] = []
    @State private var selected: BadgeEngine.Status?
    @State private var loaded = false

    private var unlocked: [BadgeEngine.Status] { statuses.filter(\.unlocked) }
    private var locked: [BadgeEngine.Status] {
        statuses.filter { !$0.unlocked }.sorted { $0.progress > $1.progress }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loaded {
                    summary
                    if !unlocked.isEmpty { section("Earned", unlocked) }
                    if !locked.isEmpty { section("Up next", locked) }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle(embedded ? "" : "Badges")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let s = await GameService.badges(context: context)
            withAnimation(.easeOut(duration: 0.25)) {
                statuses = s
                loaded = true
            }
        }
        .sheet(item: $selected) { status in
            BadgeDetailSheet(status: status, unlockedOn: GameService.unlockDate(status.badge.id))
                .presentationDetents([.medium, .large])
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            Image(systemName: "medal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Neka.amber)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Neka.amberSoft))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(unlocked.count) of \(statuses.count) badges")
                    .font(Neka.display(22, weight: .bold))
                    .foregroundColor(Neka.ink)
                if let next = locked.first {
                    Text("Closest: \(next.badge.title) · \(next.progressText)")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .nekaCard(wash: .mint)
    }

    private func section(_ title: String, _ items: [BadgeEngine.Status]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(items) { s in
                    Button { selected = s } label: { BadgeTile(status: s) }
                        .buttonStyle(.dialedScale)
                }
            }
        }
    }
}

// MARK: - Tile

struct BadgeTile: View {
    let status: BadgeEngine.Status
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 8) {
            BadgeMedal(badge: status.badge, unlocked: status.unlocked, progress: status.progress, size: size)
            Text(status.badge.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(status.unlocked ? Neka.ink : Neka.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !status.unlocked {
                Text(status.progressText)
                    .font(.system(size: 10))
                    .foregroundColor(Neka.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Neka.hairline))
    }
}

/// The round medal: tier gradient when earned, grey with a progress ring when not.
struct BadgeMedal: View {
    let badge: BadgeEngine.Badge
    var unlocked: Bool
    var progress: Double = 1
    var size: CGFloat = 64

    static func colors(_ tier: BadgeEngine.Tier) -> [Color] {
        switch tier {
        case .bronze: return [Color(red: 0.86, green: 0.58, blue: 0.36), Color(red: 0.66, green: 0.40, blue: 0.22)]
        case .silver: return [Color(red: 0.82, green: 0.85, blue: 0.90), Color(red: 0.56, green: 0.60, blue: 0.67)]
        case .gold:   return [Color(red: 1.0, green: 0.84, blue: 0.36), Color(red: 0.90, green: 0.62, blue: 0.10)]
        }
    }

    var body: some View {
        ZStack {
            if unlocked {
                Circle()
                    .fill(LinearGradient(colors: Self.colors(badge.tier), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Self.colors(badge.tier)[1].opacity(0.35), radius: 6, y: 3)
                Circle().stroke(.white.opacity(0.5), lineWidth: 2).padding(4)
            } else {
                Circle().fill(Neka.track)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Neka.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            }
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(unlocked ? .white : Neka.inkTertiary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Detail & share

struct BadgeDetailSheet: View {
    let status: BadgeEngine.Status
    let unlockedOn: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                BadgeMedal(badge: status.badge, unlocked: status.unlocked, progress: status.progress, size: 110)
                    .padding(.top, 12)
                VStack(spacing: 6) {
                    Text(status.badge.title)
                        .font(Neka.display(26, weight: .bold))
                        .foregroundColor(Neka.ink)
                    Text(status.badge.detail)
                        .font(.system(size: 14))
                        .foregroundColor(Neka.inkSecondary)
                        .multilineTextAlignment(.center)
                    Text(status.unlocked
                         ? (unlockedOn.map { "Earned \($0.formatted(.dateTime.month(.abbreviated).day().year()))" } ?? "Earned")
                         : status.progressText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(status.unlocked ? Neka.greenText : Neka.inkTertiary)
                }
                if status.unlocked, let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview(status.badge.title, image: shareImage)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.onInk)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Neka.ink))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .nekaPageBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { render() }
        }
    }

    @MainActor
    private func render() {
        guard status.unlocked else { return }
        let renderer = ImageRenderer(content: BadgeShareCard(badge: status.badge, date: unlockedOn ?? Date()))
        renderer.scale = 3
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

/// The image you share: medal, title, what it took, date, Dialed mark.
struct BadgeShareCard: View {
    let badge: BadgeEngine.Badge
    let date: Date

    var body: some View {
        VStack(spacing: 14) {
            BadgeMedal(badge: badge, unlocked: true, size: 120)
            Text("BADGE UNLOCKED")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundColor(.white.opacity(0.7))
            Text(badge.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(badge.detail)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Text(date.formatted(.dateTime.month(.wide).day().year()))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            Text("DIALED")
                .font(.system(size: 13, weight: .black))
                .tracking(3)
                .foregroundColor(.white.opacity(0.85))
                .padding(.top, 6)
        }
        .padding(32)
        .frame(width: 360)
        .background(LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.12), Color(red: 0.10, green: 0.22, blue: 0.18)],
                                   startPoint: .top, endPoint: .bottom))
    }
}
