//
//  MealPlanView.swift
//  Dialed
//
//  This week's go-to meals: a week strip, the day's breakfast, lunch,
//  dinner and snack with their ingredients and macros, one tap to log
//  one, a swap for anything you don't feel like, and the grocery list for
//  the whole week (check things off, or share it).
//

import SwiftUI
import SwiftData

struct MealPlanView: View {
    @Environment(\.modelContext) private var context
    @State private var plan: WeekMealPlanner.WeekPlan?
    @State private var selectedDay = 0
    @State private var tab = Tab.plan
    @State private var checked = MealPlanStore.checked
    @State private var justLogged: String?
    @State private var confirmRegenerate = false
    /// Bumped after logging so the cards re-read what's been logged.
    @State private var loggedTick = 0

    enum Tab: String, CaseIterable { case plan = "Plan", groceries = "Groceries" }

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let plan {
                    switch tab {
                    case .plan:      planContent(plan)
                    case .groceries: groceryContent(plan)
                    }
                } else {
                    NekaLoadingPage(cards: [70, 140, 140, 140])
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Meal plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { confirmRegenerate = true } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Regenerate week")
            }
        }
        .confirmationDialog("Make a new plan for the week?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Regenerate week") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    plan = MealPlanStore.regenerate(context: context)
                    checked = []
                }
            }
        } message: {
            Text("Rotates in different go-to meals and clears the grocery check marks.")
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
        .onAppear {
            let current = MealPlanStore.current(context: context)
            plan = current
            selectedDay = current.days.firstIndex { calendar.isDateInToday($0.date) } ?? 0
        }
    }

    // MARK: - Plan

    @ViewBuilder
    private func planContent(_ plan: WeekMealPlanner.WeekPlan) -> some View {
        weekStrip(plan)
        if plan.days.indices.contains(selectedDay) {
            let day = plan.days[selectedDay]
            dayHeader(day, plan: plan)
            ForEach(day.meals) { meal in
                mealCard(meal, day: day)
            }
        }
        Text("Portions are sized to your \(Int(plan.calories).formatted())-calorie, \(Int(plan.protein)) g protein target. Calories you earn exercising are on top.")
            .font(.system(size: 11))
            .foregroundColor(Neka.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func weekStrip(_ plan: WeekMealPlanner.WeekPlan) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(plan.days.enumerated()), id: \.offset) { i, day in
                let selected = i == selectedDay
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selectedDay = i }
                } label: {
                    VStack(spacing: 3) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 11, weight: .semibold))
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundColor(selected ? Neka.onInk : Neka.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? Neka.ink : (calendar.isDateInToday(day.date) ? Neka.greenSoft : Neka.surface)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayHeader(_ day: WeekMealPlanner.DayPlan, plan: WeekMealPlanner.WeekPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.wide)))
                    .font(Neka.display(24, weight: .bold))
                    .foregroundColor(Neka.ink)
                Text("\(Int(day.calories).formatted()) calories · \(Int(day.protein)) g protein")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }
            Spacer()
            if day.protein >= plan.protein {
                NekaPill(text: "Protein ✓", tint: Neka.greenText, fill: Neka.greenSoft)
            }
        }
    }

    private func mealCard(_ meal: WeekMealPlanner.Meal, day: WeekMealPlanner.DayPlan) -> some View {
        let logged = loggedTick >= 0 && MealPlanStore.isLogged(meal, on: day.date)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(meal.emoji)
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Neka.track))
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.slot.title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                    Text(meal.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(meal.ingredientLine)
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text("\(Int(meal.calories)) cal · \(Int(meal.protein))p · \(Int(meal.carbs))c · \(Int(meal.fat))f")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
                Button { swap(meal) } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Neka.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
                .accessibilityLabel("Swap \(meal.name)")
                .disabled(logged)
                Button { log(meal, day: day) } label: {
                    Label(logged ? "Logged" : "Log it", systemImage: logged ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(logged ? Neka.greenText : Neka.onInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(logged ? Neka.greenSoft : Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .disabled(logged)
            }
        }
        .padding(14)
        .nekaCard()
    }

    private func swap(_ meal: WeekMealPlanner.Meal) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            plan = MealPlanStore.swap(day: selectedDay, slot: meal.slot, context: context)
        }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    private func log(_ meal: WeekMealPlanner.Meal, day: WeekMealPlanner.DayPlan) {
        MealPlanStore.log(meal, on: day.date, context: context)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        loggedTick += 1
        withAnimation { justLogged = meal.name }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { justLogged = nil } }
    }

    // MARK: - Groceries

    @ViewBuilder
    private func groceryContent(_ plan: WeekMealPlanner.WeekPlan) -> some View {
        let items = WeekMealPlanner.groceries(plan)
        HStack {
            Text("\(items.count - items.filter { checked.contains($0.food) }.count) to get")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            Spacer()
            ShareLink(item: shareText(items)) {
                Label("Share list", systemImage: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        ForEach(WeekMealPlanner.aisles, id: \.self) { aisle in
            let inAisle = items.filter { $0.aisle == aisle }
            if !inAisle.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(aisle)
                        .font(Neka.title)
                        .foregroundColor(Neka.ink)
                        .padding(.bottom, 6)
                    ForEach(inAisle) { item in
                        groceryRow(item)
                        if item.id != inAisle.last?.id { Divider().overlay(Neka.hairline) }
                    }
                }
                .padding(14)
                .nekaCard()
            }
        }
    }

    private func groceryRow(_ item: WeekMealPlanner.GroceryItem) -> some View {
        let done = checked.contains(item.food)
        return Button {
            MealPlanStore.toggle(item.food)
            withAnimation(.easeOut(duration: 0.15)) { checked = MealPlanStore.checked }
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(done ? Neka.green : Neka.inkTertiary)
                Text(item.food)
                    .font(.system(size: 15))
                    .foregroundColor(done ? Neka.inkTertiary : Neka.ink)
                    .strikethrough(done)
                Spacer()
                Text(item.amount)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shareText(_ items: [WeekMealPlanner.GroceryItem]) -> String {
        var lines = ["Groceries for the week"]
        for aisle in WeekMealPlanner.aisles {
            let inAisle = items.filter { $0.aisle == aisle && !checked.contains($0.food) }
            guard !inAisle.isEmpty else { continue }
            lines.append("")
            lines.append(aisle.uppercased())
            lines += inAisle.map { "• \($0.food): \($0.amount)" }
        }
        return lines.joined(separator: "\n")
    }
}
