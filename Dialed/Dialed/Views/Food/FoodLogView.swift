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
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var foods: [LoggedFood] = []
    @State private var recents: [FoodDraft] = []
    @State private var favorites: [SavedMeal] = SavedMealsManager.load()
    @State private var editing: EditTarget?
    /// Add food, optionally jumping straight into a method.
    @State private var adding: AddRequest?
    @State private var justLogged: String?
    @AppStorage(HealthWriteBack.defaultsKey) private var writeBack = true

    private let calendar = Calendar.current
    private var settings: UserSettings { UserSettings.load() }

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
                reload()
            }, onDelete: {
                if case .existing(let food) = target { delete(food) }
            })
            .presentationDetents([.medium, .large])
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

    private func reload() {
        foods = FoodLog.entries(on: day, context: modelContext)
        recents = FoodLog.recents(context: modelContext)
        favorites = SavedMealsManager.load()
    }

    private func delete(_ food: LoggedFood) {
        FoodLog.delete(food, context: modelContext)
        reload()
    }

    /// One tap: log it now (or at noon on a past day).
    private func relog(_ draft: FoodDraft) {
        var d = draft
        d.time = calendar.isDateInToday(day) ? Date() : (calendar.date(byAdding: .hour, value: 12, to: day) ?? day)
        FoodLog.add(d, context: modelContext)
        reload()
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
        let earned = EarnedCalories.day(day, context: modelContext)
        let calTarget = (settings.calorieTarget ?? HomeViewModel.estimatedCutCalories(weight: settings.currentWeight)) + earned.earned
        let proteinTarget = settings.proteinTargetGrams
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                total("Calories", value: calories, target: calTarget, unit: "calories", tint: calories > calTarget ? Neka.rose : Neka.orange)
                total("Protein", value: protein, target: proteinTarget, unit: "g", tint: Neka.green)
            }
            if earned.burned > 0 { EarnedCaloriesPill(earned: earned) }
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
                    Label("Add food", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
                shortcut("camera.fill", "Snap a meal", .photo)
                shortcut("barcode.viewfinder", "Scan a barcode", .scan)
                shortcut("text.bubble.fill", "Describe a meal", .describe)
            }
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

    @State private var draft: FoodDraft
    /// The numbers for one serving; servings × this is what's logged.
    @State private var perServing: FoodDraft
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
        _draft = State(initialValue: start)
        _perServing = State(initialValue: Self.scaled(start, by: 1 / max(start.servings, 0.01)))
    }

    private static func scaled(_ d: FoodDraft, by factor: Double) -> FoodDraft {
        var out = d
        out.calories = d.calories * factor
        out.protein = d.protein * factor
        out.carbs = d.carbs.map { $0 * factor }
        out.fat = d.fat.map { $0 * factor }
        return out
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you eat?", text: $draft.name)
                        .font(.system(size: 17, weight: .semibold))
                    DatePicker("Time", selection: $draft.time)
                }
                Section {
                    servingsRow
                } header: {
                    Text("How much did you have?")
                } footer: {
                    Text(draft.servings == 1
                         ? "Ate more or less than you logged? Change the servings and everything below scales with it."
                         : "\(Int(perServing.calories.rounded())) calories per serving × \(Self.servingsText(draft.servings)).")
                }
                Section {
                    numberRow("Calories", value: $draft.calories, unit: "calories", steps: [-100, -25, 25, 100])
                    numberRow("Protein", value: $draft.protein, unit: "g", steps: [-10, -5, 5, 10])
                    optionalRow("Carbs", value: $draft.carbs)
                    optionalRow("Fat", value: $draft.fat)
                } footer: {
                    Text("Tap the numbers to type, or use the quick ± buttons.")
                }
                Section {
                    Toggle("Save to favorites", isOn: $saveFavorite)
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .onChange(of: draft.calories) { _, _ in syncPerServing() }
            .onChange(of: draft.protein) { _, _ in syncPerServing() }
            .onChange(of: draft.carbs) { _, _ in syncPerServing() }
            .onChange(of: draft.fat) { _, _ in syncPerServing() }
            .navigationTitle(isNew ? "Quick add" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Log" : "Save") {
                        if saveFavorite && !draft.name.isEmpty {
                            SavedMealsManager.add(SavedMeal(name: draft.name, calories: perServing.calories, proteinGrams: perServing.protein,
                                                            carbsGrams: perServing.carbs, fatGrams: perServing.fat))
                        }
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.calories <= 0 && draft.protein <= 0)
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

    // MARK: - Servings

    private static let quickServings: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    private var servingsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { setServings(draft.servings - 0.25) } label: {
                    Image(systemName: "minus").frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(draft.servings <= 0.25)
                Spacer()
                VStack(spacing: 0) {
                    Text(Self.servingsNumber(draft.servings))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: draft.servings))
                    Text(draft.servings == 1 ? "serving" : "servings")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { setServings(draft.servings + 0.25) } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }
            HStack(spacing: 6) {
                ForEach(Self.quickServings, id: \.self) { s in
                    Button { setServings(s) } label: {
                        Text(Self.servingsNumber(s) + "×")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(draft.servings == s ? Neka.ink : Neka.track))
                            .foregroundColor(draft.servings == s ? Neka.onInk : Neka.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func setServings(_ value: Double) {
        let s = min(20, max(0.25, (value * 4).rounded() / 4))
        withAnimation(.snappy) {
            let time = draft.time, name = draft.name
            draft = Self.scaled(perServing, by: s)
            draft.servings = s
            draft.time = time
            draft.name = name
        }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Typing a number or tapping ± changes what one serving is.
    private func syncPerServing() {
        let next = Self.scaled(draft, by: 1 / max(draft.servings, 0.01))
        if next.calories != perServing.calories || next.protein != perServing.protein
            || next.carbs != perServing.carbs || next.fat != perServing.fat {
            perServing = next
        }
    }

    static func servingsNumber(_ s: Double) -> String {
        s.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func servingsText(_ s: Double) -> String {
        servingsNumber(s) + (s == 1 ? " serving" : " servings")
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String, steps: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 90)
                Text(unit).foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(steps, id: \.self) { step in
                    Button(step > 0 ? "+\(Int(step))" : "\(Int(step))") {
                        value.wrappedValue = max(0, value.wrappedValue + step)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func optionalRow(_ title: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("g").foregroundColor(.secondary)
        }
    }
}
