//
//  LogHubSheet.swift
//  Dialed
//
//  The bottom bar's "+": one place to log anything. Your recent and
//  favorite foods sit on top for a one-tap re-log, then four big tiles
//  (Food, Workout, Water, Weigh-in) with Food's ways in right under it
//  (snap, scan, describe, eating out), then the rest (activity, voice,
//  progress photo).
//

import SwiftUI
import SwiftData

struct LogHubSheet: View {
    /// Open another quick-log sheet in this one's place.
    var onPick: (QuickLog) -> Void
    /// Progress photos live on Home; the caller routes there.
    var onPhoto: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var recents: [FoodDraft] = []
    @State private var favorites: [SavedMeal] = []
    @State private var justLogged: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !favorites.isEmpty || !recents.isEmpty {
                        againStrip
                    }
                    primaryTiles
                    foodWays
                    secondaryRow
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .nekaPageBackground()
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .overlay(alignment: .bottom) {
                if let justLogged {
                    Label("Logged \(justLogged)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Neka.ink))
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            recents = FoodLog.recents(context: context, limit: 8)
            favorites = SavedMealsManager.load()
        }
    }

    // MARK: - Eat it again

    private var againStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eat it again")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(favorites) { meal in
                        againChip(name: meal.name, calories: meal.calories, favorite: true) {
                            relog(FoodDraft(meal))
                        }
                    }
                    ForEach(Array(recents.enumerated()), id: \.offset) { _, draft in
                        againChip(name: draft.name, calories: draft.calories, favorite: false) {
                            relog(draft)
                        }
                    }
                }
            }
        }
    }

    private func againChip(name: String, calories: Double, favorite: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: favorite ? "star.fill" : "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(favorite ? Neka.amber : Neka.inkTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(1)
                    Text("\(Int(calories)) calories")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                }
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Neka.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Neka.hairline))
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Log \(name) again, \(Int(calories)) calories")
    }

    private func relog(_ draft: FoodDraft) {
        var d = draft
        d.time = Date()
        FoodLog.add(d, context: context)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { justLogged = d.name.isEmpty ? "meal" : d.name }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { justLogged = nil }
        }
    }

    // MARK: - Tiles

    private var primaryTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            bigTile(.meal, title: "Food", subtitle: "Snap, scan or describe", tint: Neka.orange, fill: Neka.orangeSoft)
            bigTile(.workout, title: "Workout", subtitle: "Sets, cardio, times", tint: Neka.green, fill: Neka.greenSoft)
            bigTile(.water, title: "Water", subtitle: "A glass or a bottle", tint: Neka.sky, fill: Neka.skySoft)
            bigTile(.weighIn, title: "Weigh-in", subtitle: "Today's weight", tint: Neka.lavender, fill: Neka.lavenderSoft)
        }
    }

    private func bigTile(_ item: QuickLog, title: String, subtitle: String, tint: Color, fill: Color) -> some View {
        Button { pick(item) } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(fill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Neka.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .nekaCard()
        }
        .buttonStyle(.dialedScale)
    }

    /// Food's ways in, one tap each.
    private var foodWays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other ways to log food")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            HStack(spacing: 8) {
                smallTile(.snapMeal, title: "Snap")
                smallTile(.scanFood, title: "Scan")
                smallTile(.describeFood, title: "Describe")
                smallTile(.eatingOut, title: "Eating out")
            }
        }
    }

    private var secondaryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            HStack(spacing: 8) {
                smallTile(.activity, title: "Activity")
                smallTile(.voice, title: "Voice")
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onPhoto()
                } label: {
                    smallLabel(icon: "camera.aperture", title: "Photo")
                }
                .buttonStyle(.dialedScale)
                .accessibilityLabel("Progress photo")
            }
        }
    }

    private func smallTile(_ item: QuickLog, title: String) -> some View {
        Button { pick(item) } label: { smallLabel(icon: item.icon, title: title) }
            .buttonStyle(.dialedScale)
            .accessibilityLabel(item.title)
    }

    private func smallLabel(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Neka.hairline))
    }

    private func pick(_ item: QuickLog) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        onPick(item)
    }
}
