//
//  HomeProteinPaceCard.swift
//  Dialed
//
//  "You're at 60 g by 3 PM — a protein shake now keeps you on track."
//  A pace bar (where you are vs where your usual day would be by now)
//  and, when you're behind, a one-tap log of a snack sized to the gap.
//

import SwiftUI
import SwiftData

struct HomeProteinPaceCard: View {
    /// Today's protein so far (Home's merged number) and the day's target.
    let protein: Double
    let target: Double

    @Environment(\.modelContext) private var context
    @State private var curve = ProteinPacing.defaultCurve
    @State private var lastMeal: Date?
    @State private var logged: String?

    private var status: ProteinPacing.Status {
        ProteinPacing.status(actual: protein, target: target, curve: curve, now: Date(), lastMealAt: lastMeal)
    }

    var body: some View {
        // The big day (a wedding): no protein pressure.
        if !EventModeStore.isEventDay() { card }
    }

    private var card: some View {
        let s = status
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PROTEIN PACE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.inkTertiary)
                Spacer()
                Text("\(Int(protein)) / \(Int(target)) g")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Neka.ink)
            }
            paceBar(s)
            Text(logged.map { "Logged \($0.lowercased()). Nice." } ?? s.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Neka.ink)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if logged == nil, s.gap >= 10, s.actual < s.target, let pick = s.suggestion {
                Button { log(pick) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Log \(pick.phrase) · +\(Int(pick.protein)) g")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
            }
        }
        .padding(16)
        .nekaCard()
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in reload() }
    }

    /// Fill = protein so far; the tick = where your usual day is by now.
    private func paceBar(_ s: ProteinPacing.Status) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let done = target > 0 ? min(1, s.actual / target) : 0
            let expected = target > 0 ? min(1, s.expected / target) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Neka.track)
                Capsule().fill(s.gap >= 20 ? Neka.orange : Neka.green)
                    .frame(width: max(8, w * done))
                RoundedRectangle(cornerRadius: 1)
                    .fill(Neka.ink)
                    .frame(width: 2, height: 14)
                    .offset(x: max(0, w * expected - 1))
            }
        }
        .frame(height: 10)
        .accessibilityLabel("\(Int(s.actual)) grams, pace says \(Int(s.expected)) by now")
    }

    private func reload() {
        curve = ProteinPacing.curve(context: context)
        lastMeal = ProteinPacing.lastMeal(context: context)
    }

    private func log(_ pick: ProteinPacing.Option) {
        var draft = FoodDraft()
        draft.name = pick.name
        draft.calories = pick.calories
        draft.protein = pick.protein
        draft.carbs = pick.carbs
        draft.fat = pick.fat
        draft.time = Date()
        FoodLog.add(draft, context: context)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.easeOut(duration: 0.25)) { logged = pick.name }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { logged = nil }
        }
    }
}
