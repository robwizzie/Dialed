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
        let calTarget = settings.calorieTarget ?? HomeViewModel.estimatedCutCalories(weight: settings.currentWeight)
        let proteinTarget = settings.proteinTargetGrams
        return HStack(spacing: 12) {
            total("Calories", value: calories, target: calTarget, unit: "kcal", tint: calories > calTarget ? Neka.rose : Neka.orange)
            total("Protein", value: protein, target: proteinTarget, unit: "g", tint: Neka.green)
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
                                Text("\(Int(item.calories)) kcal · \(Int(item.protein)) g protein")
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
            + Text(" kcal")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func macroLine(_ food: LoggedFood) -> String {
        var parts = ["\(Int(food.protein)) g protein"]
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
    @State private var saveFavorite = false
    @State private var confirmDelete = false

    init(target: FoodLogView.EditTarget, onSave: @escaping (FoodDraft) -> Void, onDelete: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onDelete = onDelete
        switch target {
        case .new(let d):         _draft = State(initialValue: d)
        case .existing(let food): _draft = State(initialValue: FoodDraft(food))
        }
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
                    numberRow("Calories", value: $draft.calories, unit: "kcal", steps: [-100, -25, 25, 100])
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
            .navigationTitle(isNew ? "Quick add" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Log" : "Save") {
                        if saveFavorite && !draft.name.isEmpty {
                            SavedMealsManager.add(SavedMeal(name: draft.name, calories: draft.calories, proteinGrams: draft.protein,
                                                            carbsGrams: draft.carbs, fatGrams: draft.fat))
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
