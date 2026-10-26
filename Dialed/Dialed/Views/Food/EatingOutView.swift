//
//  EatingOutView.swift
//  Dialed
//
//  "Where are you eating?" Find it from where you are (Apple Maps' places
//  nearby), or pick or type a restaurant or bar, and get up to three
//  orders that fit what's left of today — the best fit for your protein,
//  a lighter one and a more filling one — each with the macros, what
//  your day looks like after it, and how to order it. Popular chains use
//  Dialed's built-in menu guide; anywhere else, Apple Intelligence
//  suggests an order (bars fall back to a built-in bar guide). At a bar,
//  a drinks card shows what each drink costs and how many still fit.
//  One tap logs it.
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
    @StateObject private var nearby = NearbyPlaces()
    /// The place picked from nearby, when it came from there.
    @State private var place: NearbyPlaces.Place?
    /// The menu guide the picks came from (nil = Apple Intelligence).
    @State private var guide: Restaurant?
    @State private var menuTab: MenuTab = .fits

    enum MenuTab: Hashable { case fits, full }

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
            if restaurant == nil { nearbySection }
            searchField
            if let restaurant {
                results(for: restaurant)
            } else {
                popular
            }
        }
        .onAppear(perform: loadToday)
        .task {
            // Already allowed? Look around right away.
            if nearby.canLookQuietly && nearby.status == .idle { await nearby.find() }
        }
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
            Text("Tell me where, or let me look around. I'll pick what fits the rest of your day.")
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

    // MARK: - Nearby

    @ViewBuilder
    private var nearbySection: some View {
        switch nearby.status {
        case .idle:
            Button { Task { await nearby.find() } } label: {
                HStack(spacing: 12) {
                    NekaIconBadge(systemName: "location.fill", tint: Neka.sky, fill: Neka.skySoft, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find where I am")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("Looks up restaurants and bars around you, once")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
                .padding(14)
                .nekaCard()
            }
            .buttonStyle(.dialedScale)
        case .locating:
            VStack(alignment: .leading, spacing: 12) {
                NekaSkeleton(width: 90, height: 10)
                HStack(spacing: 12) {
                    Circle().fill(Neka.skeleton).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        NekaSkeleton(width: 160, height: 14)
                        NekaSkeleton(width: 100, height: 10)
                    }
                }
                Label("Looking around…", systemImage: "location.magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nekaShimmer()
            .nekaCard()
            .transition(.opacity)
        case .ready:
            if let here = nearby.places.first {
                nearbyCard(here)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        case .denied, .none, .failed:
            HStack(spacing: 10) {
                Image(systemName: nearby.status == .denied ? "location.slash" : "mappin.slash")
                    .foregroundColor(Neka.inkTertiary)
                Text(nearby.status == .denied
                     ? "Location is off for Dialed. Turn it on in Settings to find where you are, or type the name below."
                     : nearby.status == .none
                        ? "Nothing to eat or drink close by. Type the name below."
                        : "Couldn't get your location just now.")
                    .font(.system(size: 12.5))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if nearby.status == .denied {
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                } else {
                    Button("Retry") { Task { await nearby.find() } }
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(14)
            .nekaCard()
        }
    }

    /// "Are you at Joe's Tavern?" with one tap to plan, and the other
    /// places around as chips.
    private func nearbyCard(_ here: NearbyPlaces.Place) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ARE YOU AT")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(Neka.inkTertiary)
            HStack(spacing: 12) {
                Text(here.emoji)
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Neka.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text(here.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(2)
                    Text("\(here.kindText) · \(here.distanceText) away")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            Button { choose(here.name, at: here) } label: {
                Label("Yes, plan my order", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.nekaPrimary)
            if nearby.places.count > 1 {
                Text("Somewhere else nearby")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(nearby.places.dropFirst()) { p in
                            Button { choose(p.name, at: p) } label: {
                                HStack(spacing: 6) {
                                    Text(p.emoji)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(p.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Neka.ink)
                                            .lineLimit(1)
                                        Text(p.distanceText)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundColor(Neka.inkTertiary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Neka.surface))
                                .overlay(Capsule().stroke(Neka.hairline, lineWidth: 0.5))
                            }
                            .buttonStyle(.dialedScale)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Neka.skySoft, Neka.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
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
        let guides = RestaurantMenus.all + [RestaurantMenus.bar]
        guard !q.isEmpty else { return guides }
        return guides.filter { r in
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(guide?.emoji ?? place?.emoji ?? "🍴")
                    .font(.system(size: 30))
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Neka.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place?.name ?? guide?.name ?? name.capitalized)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(2)
                    Label((place.map { "\($0.distanceText) away · " } ?? "") + sourceText,
                          systemImage: guide != nil ? "book.closed.fill" : "sparkles")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Change") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        restaurant = nil
                        options = []
                        query = ""
                        place = nil
                        guide = nil
                        menuTab = .fits
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.ink)
            }

            Picker("Show", selection: $menuTab) {
                Text("Fits today").tag(MenuTab.fits)
                Text("Full menu").tag(MenuTab.full)
            }
            .pickerStyle(.segmented)

            if menuTab == .full {
                FullMenuView(restaurant: guide?.name ?? name, guide: guide,
                             caloriesLeft: budget.calories, proteinLeft: budget.protein) { items in
                    logMenuItems(items, at: place?.name ?? guide?.name ?? name.capitalized)
                }
            } else if loading {
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
                        log(option, at: place?.name ?? guide?.name ?? name.capitalized)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let drinks = drinkMenu { drinksCard(drinks, after: options.first) }
                Text(guide == RestaurantMenus.bar
                     ? "Typical bar portions and pours — real ones vary a lot, so round up."
                     : guide != nil
                     ? "Nutrition is approximate, from each chain's published numbers — recipes and portions vary."
                     : "Estimates from Apple Intelligence — check the menu, and adjust after logging if you need to.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
    }

    // MARK: - Drinks

    /// At a bar: its drinks with calories, lightest first.
    private var drinkMenu: [MenuItem]? {
        guard place?.kind == .bar || guide == RestaurantMenus.bar else { return nil }
        let menu = guide?.items ?? RestaurantMenus.bar.items
        let drinks = menu.filter { $0.role == .drink && $0.calories > 10 }.sorted { $0.calories < $1.calories }
        return drinks.isEmpty ? nil : drinks
    }

    /// What each drink costs, and how many fit in what's left after the
    /// top pick.
    private func drinksCard(_ drinks: [MenuItem], after pick: OrderOption?) -> some View {
        let left = calorieTarget - eaten.calories - (pick?.calories ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Drinks", systemImage: "wineglass.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Text(left > 0 ? "\(Int(left)) cal left\(pick == nil ? "" : " after the top pick")" : "No room after the top pick")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(left > 0 ? Neka.inkSecondary : Neka.rose)
            }
            ForEach(drinks, id: \.name) { drink in
                let fits = left > 0 ? Int(left / drink.calories) : 0
                HStack(spacing: 10) {
                    Text(drink.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Neka.ink)
                    Spacer(minLength: 6)
                    Text("\(Int(drink.calories)) cal")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                        .monospacedDigit()
                    Text(fits == 0 ? "over" : fits >= 5 ? "5+ fit" : "\(fits) fit")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(fits >= 2 ? Neka.greenText : fits == 1 ? Neka.orangeText : Neka.rose)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(fits >= 2 ? Neka.greenSoft : fits == 1 ? Neka.orangeSoft : Neka.roseSoft))
                        .frame(width: 58, alignment: .trailing)
                }
            }
            Text("Spirits with soda water or diet mixers are the lightest. Tonic, juice and regular soda add 100–150 calories a drink.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .nekaCard()
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

    /// `at`: the nearby place it came from, if any (its kind steers the picks).
    private func choose(_ name: String, at nearbyPlace: NearbyPlaces.Place? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searching = false
        place = nearbyPlace
        query = RestaurantMenus.guide(for: trimmed)?.name ?? trimmed
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { restaurant = trimmed }
        Task { await plan(trimmed) }
    }

    private func plan(_ name: String) async {
        let b = budget
        let isBar = place?.kind == .bar
        // A chain we know, or the bar guide (picked by name, or a bar nearby
        // when Apple Intelligence isn't there to read its menu).
        if let known = RestaurantMenus.guide(for: name) ?? (isBar && !DialedAI.isAvailable ? RestaurantMenus.bar : nil) {
            let picks = MealPlanner.picks(menu: known.items, budget: b).map(OrderOption.init)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                guide = known
                options = picks
            }
            return
        }
        guide = nil
        loading = true
        let kind: String? = switch place?.kind {
        case .bar?:  "bar"
        case .cafe?: "café"
        default:     nil
        }
        let ai = await DialedAI.restaurantPicks(name, calories: Int(b.calories), protein: Int(b.protein), kind: kind) ?? []
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            if ai.isEmpty && isBar {
                guide = RestaurantMenus.bar
                options = MealPlanner.picks(menu: RestaurantMenus.bar.items, budget: b).map(OrderOption.init)
            } else {
                options = ai.map(OrderOption.init)
            }
            loading = false
        }
    }

    private var sourceText: String {
        guard let guide else { return "Suggested by Apple Intelligence" }
        return guide == RestaurantMenus.bar && place != nil ? "Typical bar menu" : "From Dialed's menu guide"
    }

    private func log(_ option: OrderOption, at place: String) {
        var d = FoodDraft()
        d.name = "\(place): \(option.items.joined(separator: " + "))"
        d.calories = option.calories.rounded()
        d.protein = option.protein.rounded()
        d.carbs = option.carbs.rounded()
        d.fat = option.fat.rounded()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { _ = logged.insert(option.id) }
        logDraft(d, at: place)
    }

    /// An order built from the full menu, logged as one meal.
    private func logMenuItems(_ items: [(item: FoodCloud.MenuItem, count: Int)], at place: String) {
        guard !items.isEmpty else { return }
        var d = FoodDraft()
        d.name = "\(place): " + items.map { $0.count > 1 ? "\($0.count)× \($0.item.name)" : $0.item.name }.joined(separator: " + ")
        d.calories = items.reduce(0) { $0 + $1.item.calories * Double($1.count) }.rounded()
        d.protein = items.reduce(0) { $0 + $1.item.protein * Double($1.count) }.rounded()
        d.carbs = items.reduce(0) { $0 + $1.item.carbs * Double($1.count) }.rounded()
        d.fat = items.reduce(0) { $0 + $1.item.fat * Double($1.count) }.rounded()
        logDraft(d, at: place)
    }

    private func logDraft(_ draft: FoodDraft, at place: String) {
        var d = draft
        d.time = Date()
        FoodLog.add(d, context: modelContext)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        loadToday()
        onLogged(place)
    }
}

// MARK: - Full menu

/// Every item a restaurant serves — from your Dialed server (Claude, cached
/// a month per chain) plus Dialed's own guide — searchable, grouped by
/// section, each tagged by whether it fits this meal. Tap + to build an
/// order and log it as one meal.
private struct FullMenuView: View {
    let restaurant: String
    let guide: Restaurant?
    /// What this meal has to work with.
    let caloriesLeft: Double
    let proteinLeft: Double
    var onLog: ([(item: FoodCloud.MenuItem, count: Int)]) -> Void

    @State private var items: [FoodCloud.MenuItem] = []
    @State private var known = true
    @State private var fetching = false
    @State private var error: String?
    @State private var search = ""
    @State private var category: String?
    @State private var order: [FoodCloud.MenuItem: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !order.isEmpty { orderCard }
            if !items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Neka.inkSecondary)
                    TextField("Search the menu", text: $search)
                        .font(.system(size: 15))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Capsule().fill(Neka.surface))
                categoryChips
            }
            if fetching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(items.isEmpty
                         ? "Getting the full menu… the first time for a restaurant can take up to a minute."
                         : "Getting the rest of the menu…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nekaCard()
            }
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkSecondary)
                    if FoodCloud.isConfigured {
                        Button("Try again") { Task { await load() } }
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nekaCard()
            }
            if !shown.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Neka.hairline).padding(.leading, 14) }
                        row(item)
                    }
                }
                .nekaCard()
            } else if !items.isEmpty {
                Text("Nothing on the menu matches “\(search)”.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }
            if !items.isEmpty {
                Text(known
                     ? "Nutrition from the chain's published numbers — recipes and portions vary."
                     : "No published nutrition for this place — a typical menu, estimated.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .task(id: restaurant) { await load() }
    }

    // MARK: Pieces

    private var categories: [String] {
        var seen = Set<String>()
        return items.map(\.category).filter { seen.insert($0).inserted }
    }

    private var shown: [FoodCloud.MenuItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            (category == nil || item.category == category)
                && (q.isEmpty || item.name.lowercased().contains(q))
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip("All", selected: category == nil) { category = nil }
                ForEach(categories, id: \.self) { c in
                    chip(c, selected: category == c) { category = c }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? Neka.onInk : Neka.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? Neka.ink : Neka.surface))
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: FoodCloud.MenuItem) -> some View {
        let count = order[item] ?? 0
        let tag = fit(item)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tag.text)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tag.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tag.fill))
                if let tip = item.tip, !tip.isEmpty {
                    Text(tip)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Neka.skyText)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(item.calories))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text("\(Int(item.protein)) g P")
                    .font(.system(size: 11.5))
                    .foregroundColor(Neka.inkSecondary)
            }
            if count > 0 {
                HStack(spacing: 6) {
                    stepButton("minus") { order[item] = count > 1 ? count - 1 : nil }
                    Text("\(count)")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: 14)
                    stepButton("plus") { order[item] = count + 1 }
                }
            } else {
                stepButton("plus") { order[item] = 1 }
                    .accessibilityLabel("Add \(item.name)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Neka.greenText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Neka.greenSoft))
        }
        .buttonStyle(.plain)
    }

    private var orderLines: [(item: FoodCloud.MenuItem, count: Int)] {
        items.compactMap { item in order[item].map { (item: item, count: $0) } }
    }

    private var orderCalories: Double { orderLines.reduce(0) { $0 + $1.item.calories * Double($1.count) } }
    private var orderProtein: Double { orderLines.reduce(0) { $0 + $1.item.protein * Double($1.count) } }

    private var orderCard: some View {
        let left = caloriesLeft - orderCalories
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your order")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Text("\(Int(orderCalories)) cal · \(Int(orderProtein)) g protein")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
            Text(left >= 0 ? "\(Int(left)) calories to spare for this meal" : "\(Int(-left)) over what this meal has")
                .font(.system(size: 12))
                .foregroundColor(left >= 0 ? Neka.greenText : Neka.roseText)
            Button {
                onLog(orderLines)
                withAnimation { order = [:] }
            } label: {
                Text("Log order").frame(maxWidth: .infinity)
            }
            .buttonStyle(.nekaPrimary)
        }
        .padding(16)
        .nekaCard(wash: .amber)
    }

    /// Fits / tight / over against what's left after the order so far.
    private func fit(_ item: FoodCloud.MenuItem) -> (text: String, ink: Color, fill: Color) {
        let after = caloriesLeft - orderCalories - item.calories
        if after >= 100 {
            let proteinRich = item.protein >= 25 && item.protein * 4 >= item.calories * 0.3
            return (proteinRich ? "Fits · high protein" : "Fits", Neka.greenText, Neka.greenSoft)
        }
        if after >= -100 { return ("Tight", Neka.orangeText, Neka.amberSoft) }
        return ("Over by \(Int(-after))", Neka.roseText, Neka.roseSoft)
    }

    // MARK: Load

    private func load() async {
        // Dialed's own guide shows right away; the full menu fills in after.
        let curated = (guide?.items ?? []).map { m in
            FoodCloud.MenuItem(name: m.name, category: Self.section(m.role), calories: m.calories,
                               protein: m.protein, carbs: m.carbs, fat: m.fat, tip: m.tip)
        }
        items = curated
        error = nil
        guard FoodCloud.isConfigured else {
            if curated.isEmpty {
                error = "Full menus need your Dialed server — add it in Challenge → Live sync."
            }
            return
        }
        fetching = true
        defer { fetching = false }
        do {
            let menu = try await FoodCloud.menu(for: restaurant)
            let names = Set(menu.items.map { $0.name.lowercased() })
            withAnimation(.easeOut(duration: 0.25)) {
                known = menu.known
                items = menu.items + curated.filter { !names.contains($0.name.lowercased()) }
            }
        } catch {
            self.error = curated.isEmpty
                ? "Couldn't get the menu: \(error.localizedDescription)"
                : "Showing Dialed's picks — couldn't get the full menu (\(error.localizedDescription))."
        }
    }

    private static func section(_ role: MenuItem.Role) -> String {
        switch role {
        case .main:  return "Entrées"
        case .side:  return "Sides"
        case .drink: return "Drinks"
        }
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
