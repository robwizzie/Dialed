//
//  HomeMealPlanCard.swift
//  Dialed
//
//  Home: the next meal on this week's plan, with a one-tap Log.
//

import SwiftUI
import SwiftData

struct HomeMealPlanCard: View {
    /// Opens the full meal plan.
    var onOpen: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var next: (date: Date, meal: WeekMealPlanner.Meal)?
    @State private var logged = false

    var body: some View {
        Group {
            if let next {
                content(next.date, next.meal)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: MealPlanStore.didChange)) { _ in refresh() }
    }

    private func content(_ date: Date, _ meal: WeekMealPlanner.Meal) -> some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Text(meal.emoji)
                        .font(.system(size: 24))
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Neka.track))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Calendar.current.isDateInToday(date)
                             ? "NEXT UP · \(meal.slot.title.uppercased())"
                             : "TOMORROW · \(meal.slot.title.uppercased())")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(Neka.inkTertiary)
                        Text(meal.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .lineLimit(1)
                        Text("\(Int(meal.calories)) cal · \(Int(meal.protein)) g protein")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button {
                MealPlanStore.log(meal, on: date, context: context)
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { logged = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    logged = false
                    refresh()
                }
            } label: {
                Label(logged ? "Logged" : "Log", systemImage: logged ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(logged ? Neka.greenText : Neka.onInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(logged ? Neka.greenSoft : Neka.ink))
            }
            .buttonStyle(.dialedScale)
            .disabled(logged)
        }
        .padding(14)
        .nekaCard()
    }

    /// The next planned meal not yet logged.
    private func refresh() {
        let plan = MealPlanStore.current(context: context)
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        guard let today = plan.days.firstIndex(where: { calendar.isDateInToday($0.date) }) else { next = nil; return }
        for d in today..<min(today + 2, plan.days.count) {
            let day = plan.days[d]
            let meals = day.meals.sorted { $0.slot.hour < $1.slot.hour }
            if let m = meals.first(where: { !MealPlanStore.isLogged($0, on: day.date) && (d > today || $0.slot.hour + 2 > hour) }) {
                next = (day.date, m)
                return
            }
        }
        next = nil
    }
}
