//
//  FoodLogView.swift
//  Dialed
//
//  Your food for the day at a glance: totals against your targets, Add
//  food (the same sheet as everywhere else — snap, scan, describe or type
//  it) with one-tap shortcuts, favorites and recents, and the list of
//  everything logged. Tap an item to edit it, swipe to delete.
//

import SwiftUI
import SwiftData

struct FoodLogView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var day: Date
    @State private var foods: [LoggedFood] = []
    @State private var recents: [FoodDraft] = []
    @State private var favorites: [SavedMeal] = SavedMealsManager.load()
    @State private var editing: EditTarget?
    /// Add food, optionally jumping straight into a method.
    @State private var adding: AddRequest?
    @State private var justLogged: String?
    /// What exercise earned back on this day.
    @State private var earned = EarnedCalories.Day()
    @AppStorage(HealthWriteBack.defaultsKey) private var writeBack = true

    private let calendar = Calendar.current
    private var settings: UserSettings { UserSettings.load() }

    /// Opens on `day` (today by default), e.g. from a past day's recap.
    init(day: Date = Date()) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    struct AddRequest: Identifiable {
        let method: AddFoodSheet.Method?
        var id: String { method?.rawValue ?? "pick" }
    }

    /// What the edit sheet is open for.
    enum EditTarget: Identifiable {
        case new(FoodDraft)
        case existing(LoggedFood)
        var id: String {
            switch self {
            case .new(let d):      return "new-\(d.name)-\(d.time.timeIntervalSince1970)"
            case .existing(let f): return f.id
            }
        }
    }

    var body: some View {
        List {
            Section { summary }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)

            Section { quickAdd }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)

            Section {
                if foods.isEmpty {
                    Text(calendar.isDateInToday(day) ? "Nothing logged yet today." : "Nothing logged this day.")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkSecondary)
                        .listRowBackground(Neka.surface)
                }
                ForEach(foods) { food in
                    Button { editing = .existing(food) } label: { row(food) }
                        .listRowBackground(Neka.surface)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(food) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button { relog(FoodDraft(food)) } label: { Label("Log again", systemImage: "arrow.counterclockwise") }
                                .tint(Neka.green)
                        }
                }
            } header: {
                Text("Logged")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            } footer: {
                if !foods.isEmpty {
                    Text("Tap to edit · swipe left to delete, right to log again. Food from other apps in Apple Health is edited in that app.")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                }
            }

            Section {
                Toggle(isOn: $writeBack) {
                    Label("Save to Apple Health", systemImage: "heart.text.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                }
                .tint(Neka.green)
                .listRowBackground(Neka.surface)
                .onChange(of: writeBack) { _, on in
                    if on { Task { await HealthWriteBack.requestAccessIfNeeded() } }
                }
            } footer: {
                Text("Meals and water you log here are copied to Apple Health (calories, protein, carbs, fat, water). Edits and deletes stay in sync. Dialed never counts its own copies twice.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .nekaPageBackground()
        .navigationTitle("Food log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { dayStepper }
        }
        .onAppear(perform: reload)
        .onChange(of: day) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .dialedDataDidChange)) { _ in reload() }
        .sheet(item: $editing) { target in
            FoodEditSheet(target: target, onSave: { draft in
                switch target {
                case .new:               FoodLog.add(draft, context: modelContext)
                case .existing(let food): FoodLog.update(food, with: draft, context: modelContext)
                }
                // FoodLog posts .dialedDataDidChange, which reloads the list.
            }, onDelete: {
                if case .existing(let food) = target { delete(food) }
            })
            .presentationDetents([.large])
        }
        .sheet(item: $adding, onDismiss: reload) { request in
            AddFoodSheet(start: request.method, day: day) { draft in
                withAnimation { justLogged = draft.name.isEmpty ? "meal" : draft.name }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { justLogged = nil } }
            }
            .presentationDetents([.large])
        }
        .overlay(alignment: .bottom) {
            if let justLogged {
                Text("Logged \(justLogged)")
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

    // MARK: - Data

    /// Re-reads the day. FoodLog posts .dialedDataDidChange after every
    /// add, edit and delete, so changes land here once (not twice).
    private func reload() {
        let next = FoodLog.entries(on: day, context: modelContext)
        withAnimation(.snappy) { foods = next }
        recents = FoodLog.recents(context: modelContext)
        favorites = SavedMealsManager.load()
        let shown = day
        Task {
            let found = await EarnedCalories.day(shown, context: modelContext)
            if shown == day { withAnimation { earned = found } }
        }
    }

    private func delete(_ food: LoggedFood) {
        withAnimation(.snappy) { foods.removeAll { $0.id == food.id } }
        FoodLog.delete(food, context: modelContext)
    }

    /// One tap: log it now (or at noon on a past day).
    private func relog(_ draft: FoodDraft) {
        var d = draft
        d.time = calendar.isDateInToday(day) ? Date() : (calendar.date(byAdding: .hour, value: 12, to: day) ?? day)
        FoodLog.add(d, context: modelContext)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation { justLogged = d.name.isEmpty ? "meal" : d.name }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { justLogged = nil } }
    }

    // MARK: - Header

    private var dayStepper: some View {
        HStack(spacing: 10) {
            Button { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day } label: {
                Image(systemName: "chevron.left")
            }
            Text(calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 90)
            Button { day = min(calendar.startOfDay(for: Date()), calendar.date(byAdding: .day, value: 1, to: day) ?? day) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(calendar.isDateInToday(day))
        }
        .foregroundColor(Neka.ink)
    }

    private var summary: some View {
        let calories = foods.reduce(0) { $0 + $1.calories }
        let protein = foods.reduce(0) { $0 + $1.protein }
        let calTarget = CalorieTarget.current(settings: settings, weight: settings.currentWeight) + earned.earned
        let proteinTarget = settings.proteinTargetGrams
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                total("Calories", value: calories, target: calTarget, unit: "calories", tint: calories > calTarget ? Neka.rose : Neka.orange)
                total("Protein", value: protein, target: proteinTarget, unit: "g", tint: Neka.green)
            }
            if earned.earned > 0 { EarnedCaloriesPill(earned: earned) }
        }
    }

    private func total(_ title: String, value: Double, target: Double, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Int(value).formatted())
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText())
                Text("/ \(Int(target).formatted()) \(unit)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
            }
            NekaProgressBar(progress: target > 0 ? min(1, value / target) : 0, tint: tint, height: 6)
            Text(value <= target ? "\(Int(target - value).formatted()) \(unit) left" : "\(Int(value - target).formatted()) \(unit) over")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(value <= target || unit == "g" ? Neka.inkSecondary : Neka.rose)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard()
    }

    // MARK: - Quick add

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 12) {
            // One button to add food, plus one-tap shortcuts into each way —
            // the same sheet you get from Home and the + menu.
            HStack(spacing: 10) {
                Button { adding = AddRequest(method: nil) } label: {
                    Label("Log food", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
                shortcut("camera.fill", "Snap a meal", .photo)
                shortcut("barcode.viewfinder", "Scan a barcode", .scan)
                shortcut("text.bubble.fill", "Describe a meal", .describe)
            }
            NavigationLink { MealPlanView() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.greenText)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Neka.greenSoft))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Meal plan")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text("Go-to meals for the week and a grocery list")
                            .font(.system(size: 11))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Neka.inkTertiary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))
            }
            .buttonStyle(.dialedScale)
            if !favorites.isEmpty {
                chips(title: "Favorites", items: favorites.map(FoodDraft.init), icon: "star.fill")
            }
            if !recents.isEmpty {
                chips(title: "Recent", items: recents, icon: "clock.arrow.circlepath")
            }
        }
    }

    private func shortcut(_ icon: String, _ label: String, _ method: AddFoodSheet.Method) -> some View {
        Button { adding = AddRequest(method: method) } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Neka.ink)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Neka.surface))
                .overlay(Circle().stroke(Neka.hairline, lineWidth: 1))
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel(label)
    }

    private func chips(title: String, items: [FoodDraft], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button { relog(item) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Neka.ink)
                                    .lineLimit(1)
                                Text("\(Int(item.calories)) calories · \(Int(item.protein)) g protein")
                                    .font(.system(size: 10))
                                    .foregroundColor(Neka.inkSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Neka.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.dialedScale)
                        .accessibilityLabel("Log \(item.name)")
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func row(_ food: LoggedFood) -> some View {
        HStack(spacing: 12) {
            Text(food.time.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Neka.inkTertiary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(2)
                Text(macroLine(food))
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            }
            Spacer(minLength: 8)
            Text("\(Int(food.calories))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
            + Text(" calories")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func macroLine(_ food: LoggedFood) -> String {
        var parts = ["\(Int(food.protein)) g protein"]
        if food.servings != 1 { parts.insert(FoodEditSheet.servingsText(food.servings), at: 0) }
        if let c = food.carbs { parts.append("\(Int(c)) g carbs") }
        if let f = food.fat { parts.append("\(Int(f)) g fat") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Edit sheet

struct FoodEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: FoodLogView.EditTarget
    var onSave: (FoodDraft) -> Void
    var onDelete: () -> Void

    /// The numbers for one serving. Servings × this is what's logged, so
    /// changing servings always scales from here (no drift from repeated
    /// rounding); editing a number updates it.
    @State private var perServing: FoodDraft
    @State private var servings: Double
    @State private var name: String
    @State private var time: Date
    @State private var saveFavorite = false
    @State private var confirmDelete = false

    init(target: FoodLogView.EditTarget, onSave: @escaping (FoodDraft) -> Void, onDelete: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onDelete = onDelete
        let start: FoodDraft
        switch target {
        case .new(let d):         start = d
        case .existing(let food): start = FoodDraft(food)
        }
        let s = max(start.servings, 0.01)
        _perServing = State(initialValue: Self.scaled(start, by: 1 / s))
        _servings = State(initialValue: start.servings)
        _name = State(initialValue: start.name)
        _time = State(initialValue: start.time)
    }

    private static func scaled(_ d: FoodDraft, by factor: Double) -> FoodDraft {
        var out = d
        out.calories = d.calories * factor
        out.protein = d.protein * factor
        out.carbs = d.carbs.map { $0 * factor }
        out.fat = d.fat.map { $0 * factor }
        return out
    }

    /// What gets logged: per serving × servings.
    private var draft: FoodDraft {
        var d = Self.scaled(perServing, by: servings)
        d.servings = servings
        d.name = name
        d.time = time
        return d
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("What did you eat?", text: $name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        DatePicker("Time", selection: $time)
                            .font(.system(size: 14))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    .padding(16)
                    .nekaCard()

                    howMuch
                    numbers

                    Toggle(isOn: $saveFavorite) {
                        Label("Save to favorites", systemImage: "star")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    }
                    .tint(Neka.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .nekaCard()

                    if !isNew {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Neka.rose)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Neka.roseSoft))
                        }
                        .buttonStyle(.dialedScale)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .nekaPageBackground()
            .navigationTitle(isNew ? "Quick add" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Log" : "Save") {
                        let d = draft
                        if saveFavorite && !d.name.isEmpty {
                            SavedMealsManager.add(SavedMeal(name: d.name, calories: perServing.calories, proteinGrams: perServing.protein,
                                                            carbsGrams: perServing.carbs, fatGrams: perServing.fat))
                        }
                        onSave(d)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(perServing.calories <= 0 && perServing.protein <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Delete this food?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
    }

    // MARK: - How much

    /// Servings, and the totals rolling to match as you change them.
    private var howMuch: some View {
        let d = draft
        return VStack(alignment: .leading, spacing: 14) {
            Text("How much did you have?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            ServingsPicker(servings: servings) { setServings($0) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Int(d.calories.rounded()).formatted())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Neka.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: d.calories))
                Text("calories")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                Spacer(minLength: 0)
                macroTotal(d.protein, "protein", Neka.greenText)
                if let c = d.carbs { macroTotal(c, "carbs", Neka.sky) }
                if let f = d.fat { macroTotal(f, "fat", Neka.lavenderText) }
            }
            Text(servings == 1
                 ? "Had more or less? Change the servings and everything scales with it."
                 : "\(Int(perServing.calories.rounded())) calories per serving × \(ServingsPicker.number(servings)).")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .contentTransition(.numericText())
        }
        .padding(16)
        .nekaCard(wash: .mint)
    }

    private func macroTotal(_ grams: Double, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(Int(grams.rounded()))g")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Neka.ink)
                .monospacedDigit()
                .contentTransition(.numericText(value: grams))
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(tint)
        }
    }

    private func setServings(_ value: Double) {
        let s = ServingsPicker.clamp(value)
        guard s != servings else { return }
        withAnimation(.snappy(duration: 0.3)) { servings = s }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    // MARK: - Numbers

    private var numbers: some View {
        VStack(spacing: 14) {
            numberRow("Calories", unit: "cal", value: total(\.calories), steps: [-100, -25, 25, 100])
            Divider().overlay(Neka.hairline)
            numberRow("Protein", unit: "g", value: total(\.protein), steps: [-10, -5, 5, 10])
            Divider().overlay(Neka.hairline)
            optionalRow("Carbs", value: optionalTotal(\.carbs))
            optionalRow("Fat", value: optionalTotal(\.fat))
            Text(servings == 1 ? "Tap a number to type it." : "These are totals for \(ServingsPicker.number(servings)) servings. Tap a number to type it.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .nekaCard()
    }

    /// A total you can edit; the edit becomes the new per-serving value.
    private func total(_ key: WritableKeyPath<FoodDraft, Double>) -> Binding<Double> {
        Binding(
            get: { perServing[keyPath: key] * servings },
            set: { new in withAnimation(.snappy(duration: 0.25)) { perServing[keyPath: key] = max(0, new) / max(servings, 0.01) } }
        )
    }

    private func optionalTotal(_ key: WritableKeyPath<FoodDraft, Double?>) -> Binding<Double?> {
        Binding(
            get: { perServing[keyPath: key].map { $0 * servings } },
            set: { new in perServing[keyPath: key] = new.map { max(0, $0) / max(servings, 0.01) } }
        )
    }

    private func numberRow(_ title: String, unit: String, value: Binding<Double>, steps: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Neka.ink)
                Spacer()
                LiveNumberField(value: value, font: .system(size: 22, weight: .bold, design: .rounded))
                    .frame(width: 110, alignment: .trailing)
                Text(unit)
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                    .frame(width: 26, alignment: .leading)
            }
            HStack(spacing: 8) {
                ForEach(steps, id: \.self) { step in
                    Button { value.wrappedValue = max(0, value.wrappedValue + step) } label: {
                        Text(step > 0 ? "+\(Int(step))" : "\(Int(step))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Neka.track))
                    }
                    .buttonStyle(.dialedScale)
                }
            }
        }
    }

    private func optionalRow(_ title: String, value: Binding<Double?>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Neka.ink)
            Spacer()
            LiveNumberField(value: value)
                .frame(width: 110, alignment: .trailing)
            Text("g")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .frame(width: 26, alignment: .leading)
        }
    }

    static func servingsNumber(_ s: Double) -> String { ServingsPicker.number(s) }

    static func servingsText(_ s: Double) -> String {
        servingsNumber(s) + (s == 1 ? " serving" : " servings")
    }
}
