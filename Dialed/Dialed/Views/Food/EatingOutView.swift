//
//  EatingOutView.swift
//  Dialed
//
//  "Where are you eating?" Pick or type a restaurant and get up to three
//  orders that fit what's left of today — the best fit for your protein,
//  a lighter one and a more filling one — each with the macros, what
//  your day looks like after it, and how to order it. Popular chains use
//  Dialed's built-in menu guide; anywhere else, Apple Intelligence
//  suggests an order. One tap logs it.
//

import SwiftUI
import SwiftData

struct EatingOutView: View {
    var onLogged: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var restaurant: String?
    @State private var options: [OrderOption] = []
    @State private var loading = false
    @State private var lastMeal = false
    @State private var logged: Set<String> = []
    @State private var eaten = (calories: 0.0, protein: 0.0)
    @FocusState private var searching: Bool

    private var settings: UserSettings { UserSettings.load() }
    /// Calories exercise earned back today.
    @State private var earnedCalories: Double = 0

    /// Today's target plus what exercise earned back.
    private var calorieTarget: Double {
        CalorieTarget.current(settings: settings, weight: settings.currentWeight) + earnedCalories
    }
    private var proteinTarget: Double { settings.proteinTargetGrams }

    private var budget: MealPlanner.Budget {
        MealPlanner.Budget.forNow(caloriesLeft: calorieTarget - eaten.calories,
                                  proteinLeft: proteinTarget - eaten.protein,
                                  hour: Calendar.current.component(.hour, from: Date()),
                                  lastMeal: lastMeal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            budgetCard
            searchField
            if let restaurant {
                results(for: restaurant)
            } else {
                popular
            }
        }
        .onAppear(perform: loadToday)
        .task { earnedCalories = await EarnedCalories.day(context: modelContext).earned }
        .onChange(of: lastMeal) { _, _ in if let restaurant { Task { await plan(restaurant) } } }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🍽️")
                .font(.system(size: 34))
            Text("Eating out?")
                .font(Neka.display(28, weight: .bold))
                .foregroundColor(Neka.ink)
            Text("Tell me where — I'll pick what fits the rest of your day.")
                .font(.system(size: 14))
                .foregroundColor(Neka.inkSecondary)
        }
    }

    // MARK: - Budget

    private var budgetCard: some View {
        let b = budget
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                budgetRing(value: b.calories, unit: "calories", label: "to spend", tint: Neka.orange,
                           progress: calorieTarget > 0 ? eaten.calories / calorieTarget : 0)
                budgetRing(value: b.protein, unit: "g", label: "protein to get", tint: Neka.green,
                           progress: proteinTarget > 0 ? eaten.protein / proteinTarget : 0)
                Spacer(minLength: 0)
            }
            Picker("Plan for", selection: $lastMeal) {
                Text("This meal").tag(false)
                Text("Last meal today").tag(true)
            }
            .pickerStyle(.segmented)
            Text(lastMeal
                 ? "Using almost everything you have left today."
                 : "Saving room for later — \(Int(b.share * 100))% of what's left (\(Int(max(0, calorieTarget - eaten.calories))) calories).")
                .font(.system(size: 11.5))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Neka.amberSoft, Neka.orangeSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private func budgetRing(value: Double, unit: String, label: String, tint: Color, progress: Double) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Neka.surface.opacity(0.9), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(value))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Neka.ink)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Neka.inkTertiary)
            TextField("Chipotle, Chick-fil-A, the Thai place…", text: $query)
                .font(.system(size: 16, weight: .medium))
                .focused($searching)
                .submitLabel(.search)
                .onSubmit { choose(query) }
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                    withAnimation { restaurant = nil; options = [] }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Neka.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Neka.hairline, lineWidth: 1))
    }

    // MARK: - Popular

    private var filtered: [Restaurant] {
        let q = RestaurantMenus.normalize(query)
        guard !q.isEmpty else { return RestaurantMenus.all }
        return RestaurantMenus.all.filter { r in
            ([r.name] + r.aliases).map(RestaurantMenus.normalize).contains { $0.contains(q) }
        }
    }

    private var popular: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(query.isEmpty ? "Popular spots" : (filtered.isEmpty ? "Not in the guide — tap Search for an AI pick" : "Matches"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(filtered) { r in
                    Button { choose(r.name) } label: {
                        VStack(spacing: 6) {
                            Text(r.emoji).font(.system(size: 28))
                            Text(r.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Neka.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Neka.surface))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Neka.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.dialedScale)
                }
            }
            if !query.isEmpty && filtered.isEmpty {
                Button { choose(query) } label: {
                    Label("Find something at \(query)", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private func results(for name: String) -> some View {
        let guide = RestaurantMenus.find(name)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(guide?.emoji ?? "🍴")
                    .font(.system(size: 30))
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Neka.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text(guide?.name ?? name.capitalized)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Label(guide != nil ? "From Dialed's menu guide" : "Suggested by Apple Intelligence",
                          systemImage: guide != nil ? "book.closed.fill" : "sparkles")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer()
                Button("Change") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        restaurant = nil
                        options = []
                        query = ""
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.ink)
            }

            if loading {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                        .fill(Neka.surface)
                        .frame(height: 210)
                        .overlay(IntelligenceRim(cornerRadius: Neka.cardRadius, active: true))
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Reading the menu…")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Neka.inkSecondary)
                            }
                        )
                }
            } else if options.isEmpty {
                emptyState(guide: guide)
            } else {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    OrderCard(option: option, featured: index == 0,
                              eaten: eaten, calorieTarget: calorieTarget, proteinTarget: proteinTarget,
                              isLogged: logged.contains(option.id)) {
                        log(option, at: guide?.name ?? name.capitalized)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Text(guide != nil
                     ? "Nutrition is approximate, from each chain's published numbers — recipes and portions vary."
                     : "Estimates from Apple Intelligence — check the menu, and adjust after logging if you need to.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
    }

    private func emptyState(guide: Restaurant?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(guide == nil && !DialedAI.isAvailable ? "No menu for this one" : "Nothing fits neatly",
                  systemImage: "fork.knife.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            Text(guide == nil && !DialedAI.isAvailable
                 ? "Dialed's guide doesn't have this place, and suggestions need Apple Intelligence. The rule that works almost anywhere: a grilled protein, vegetables, sauce on the side, and skip the extras."
                 : "Try \"Last meal today\" for a bigger budget, or go with a grilled protein and vegetables.")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard()
    }

    // MARK: - Actions

    private func loadToday() {
        let foods = FoodLog.entries(on: Calendar.current.startOfDay(for: Date()), context: modelContext)
        eaten = (foods.reduce(0) { $0 + $1.calories }, foods.reduce(0) { $0 + $1.protein })
    }

    private func choose(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searching = false
        query = RestaurantMenus.find(trimmed)?.name ?? trimmed
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { restaurant = trimmed }
        Task { await plan(trimmed) }
    }

    private func plan(_ name: String) async {
        let b = budget
        if let guide = RestaurantMenus.find(name) {
            let picks = MealPlanner.picks(menu: guide.items, budget: b).map(OrderOption.init)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { options = picks }
            return
        }
        loading = true
        let ai = await DialedAI.restaurantPicks(name, calories: Int(b.calories), protein: Int(b.protein)) ?? []
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            options = ai.map(OrderOption.init)
            loading = false
        }
    }

    private func log(_ option: OrderOption, at place: String) {
        var d = FoodDraft()
        d.name = "\(place): \(option.items.joined(separator: " + "))"
        d.calories = option.calories.rounded()
        d.protein = option.protein.rounded()
        d.carbs = option.carbs.rounded()
        d.fat = option.fat.rounded()
        d.time = Date()
        FoodLog.add(d, context: modelContext)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { _ = logged.insert(option.id) }
        loadToday()
        onLogged(place)
    }
}

// MARK: - Option

/// One suggested order, from the menu guide or Apple Intelligence.
struct OrderOption: Identifiable, Equatable {
    let title: String
    let icon: String
    let tint: Color
    let items: [String]
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let tips: [String]
    let isAI: Bool

    var id: String { title + items.joined() }

    init(_ pick: MealPlanner.Pick) {
        title = pick.title
        switch pick.kind {
        case .protein: icon = "target"; tint = Neka.green
        case .light:   icon = "leaf.fill"; tint = Neka.sky
        case .filling: icon = "fork.knife"; tint = Neka.orange
        }
        items = pick.items.filter { $0.role != .drink || $0.calories > 0 }.map(\.name)
            + pick.items.filter { $0.role == .drink && $0.calories == 0 }.map(\.name)
        calories = pick.calories
        protein = pick.protein
        carbs = pick.carbs
        fat = pick.fat
        tips = pick.tips
        isAI = false
    }

    init(_ ai: AIRestaurantPick) {
        title = ai.title
        icon = "sparkles"
        tint = Neka.lavender
        items = ai.items
        calories = Double(ai.calories)
        protein = Double(ai.proteinGrams)
        carbs = Double(ai.carbsGrams)
        fat = Double(ai.fatGrams)
        tips = ai.tips
        isAI = true
    }
}

// MARK: - Card

private struct OrderCard: View {
    let option: OrderOption
    let featured: Bool
    let eaten: (calories: Double, protein: Double)
    let calorieTarget: Double
    let proteinTarget: Double
    let isLogged: Bool
    var onLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(option.title, systemImage: option.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(featured ? .white : option.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(featured ? option.tint : option.tint.opacity(0.15)))
                Spacer()
                if option.isAI {
                    Image(systemName: "sparkles")
                        .foregroundStyle(LinearGradient(colors: Neka.intelligence, startPoint: .leading, endPoint: .trailing))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(option.items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(option.tint).frame(width: 6, height: 6).padding(.top, 6)
                        Text(item)
                            .font(.system(size: featured ? 16 : 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                numberStat(option.calories, "calories")
                numberStat(option.protein, "g protein")
                Spacer(minLength: 0)
            }
            macroBar

            afterThis

            if !option.tips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(option.tips, id: \.self) { tip in
                        Label(tip, systemImage: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.amberSoft.opacity(0.7)))
            }

            Button(action: onLog) {
                HStack(spacing: 8) {
                    Image(systemName: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                    Text(isLogged ? "Logged — enjoy it" : "Log this meal")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isLogged ? Neka.greenText : Neka.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(isLogged ? Neka.greenSoft : Neka.ink))
            }
            .buttonStyle(.dialedScale)
            .disabled(isLogged)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous).fill(Neka.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .stroke(featured ? option.tint.opacity(0.6) : Neka.hairline, lineWidth: featured ? 1.5 : 0.5)
        )
        .shadow(color: featured ? option.tint.opacity(0.18) : .clear, radius: 14, y: 6)
    }

    private func numberStat(_ value: Double, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(Int(value))")
                .font(.system(size: featured ? 30 : 24, weight: .bold, design: .rounded))
                .foregroundColor(Neka.ink)
            Text(unit)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
    }

    /// Protein / carbs / fat by calories, as one bar.
    private var macroBar: some View {
        let p = option.protein * 4, c = option.carbs * 4, f = option.fat * 9
        let total = max(1, p + c + f)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(Neka.green).frame(width: max(3, (geo.size.width - 4) * p / total))
                    Capsule().fill(Neka.sky).frame(width: max(3, (geo.size.width - 4) * c / total))
                    Capsule().fill(Neka.lavender).frame(width: max(3, (geo.size.width - 4) * f / total))
                }
            }
            .frame(height: 8)
            HStack(spacing: 12) {
                legend(Neka.green, "\(Int(option.protein)) g protein")
                legend(Neka.sky, "\(Int(option.carbs)) g carbs")
                legend(Neka.lavender, "\(Int(option.fat)) g fat")
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Neka.inkSecondary)
        }
    }

    /// Where today lands if you eat this.
    private var afterThis: some View {
        let calAfter = eaten.calories + option.calories
        let proAfter = eaten.protein + option.protein
        return VStack(alignment: .leading, spacing: 6) {
            Text("After this")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.inkTertiary)
            dayBar(done: eaten.calories, adds: option.calories, target: calorieTarget, tint: Neka.orange,
                   text: calAfter <= calorieTarget ? "\(Int(calorieTarget - calAfter)) calories left today" : "\(Int(calAfter - calorieTarget)) calories over today")
            dayBar(done: eaten.protein, adds: option.protein, target: proteinTarget, tint: Neka.green,
                   text: proAfter >= proteinTarget ? "Protein goal hit 🎉" : "\(Int(proteinTarget - proAfter)) g protein to go")
        }
    }

    private func dayBar(done: Double, adds: Double, target: Double, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let t = max(target, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Neka.track)
                    Capsule().fill(tint.opacity(0.35)).frame(width: w * min(1, (done + adds) / t))
                    Capsule().fill(tint).frame(width: w * min(1, done / t))
                }
            }
            .frame(height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.ink)
                .frame(width: 136, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Eating out as its own sheet (the + menu and Home).
struct EatingOutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                EatingOutView()
                    .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .nekaPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
