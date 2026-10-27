//
//  AddFoodSheet.swift
//  Dialed
//
//  The one way to add food, wherever you start: Home, the + menu, the
//  Food log, the Nutrition page or a widget. Search everything you've
//  ever logged, re-log a usual in one tap, or pick how — snap a photo,
//  scan a barcode, describe it, or type it in. Photos and descriptions go
//  to Claude via your Dialed server when it's set up (FoodCloud), else
//  Apple Intelligence on-device. Every path ends on the same review
//  screen, so what you confirm and how it's logged never changes.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddFoodSheet: View {
    enum Method: String, Equatable {
        case photo, scan, describe, manual, eatingOut
    }

    /// Jump straight into a method (e.g. the + menu's "Scan barcode").
    var start: Method? = nil
    /// Log onto this day (the Food log's selected day); nil = now.
    var day: Date? = nil
    var onLogged: (FoodDraft) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var stage: Stage = .pick
    @State private var favorites: [SavedMeal] = SavedMealsManager.load()
    /// Everything you've ever logged, newest first.
    @State private var history: [FoodLog.HistoryFood] = []
    @State private var query = ""
    /// How much of the history list is shown; "Show more" adds a page.
    @State private var historyShown = 30
    /// Text carried from search into Describe it.
    @State private var describeSeed = ""
    @State private var didStart = false

    enum Stage: Equatable {
        case pick
        case photo
        case scan
        case describe
        case eatingOut
        case review(FoodDraft, Source)
    }

    /// Where the numbers came from — shown on the review screen.
    enum Source: Equatable {
        case photo(seen: [String], assumption: String?, parts: [MealPart] = [])
        case barcode
        case described(assumption: String?, parts: [MealPart] = [])
        case manual
        case saved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch stage {
                    case .pick:
                        picker
                    case .photo:
                        MealPhotoStep(usuals: cloudUsuals) { draft, seen, estimate in
                            go(.review(stamped(draft), .photo(seen: seen, assumption: estimate.assumption, parts: estimate.parts)))
                        } onManual: { draft in
                            go(.review(stamped(draft), .manual))
                        }
                    case .scan:
                        BarcodeScanView { draft in
                            go(.review(stamped(draft), draft.name.isEmpty ? .manual : .barcode))
                        }
                        .frame(minHeight: 560)
                    case .describe:
                        DescribeMealStep(seed: describeSeed, usuals: cloudUsuals) { draft, estimate in
                            go(.review(stamped(draft), .described(assumption: estimate.assumption, parts: estimate.parts)))
                        } onManual: { draft in
                            go(.review(stamped(draft), .manual))
                        }
                    case .eatingOut:
                        EatingOutView { _ in dismiss() }
                    case .review(let draft, let source):
                        FoodReviewStep(draft: draft, source: source) { final in
                            log(final)
                        }
                    }
                }
                .padding(16)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)
            .nekaSceneBackground(.ice)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if stage == .pick || (start != nil && isStartStage) {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button {
                            go(.pick)
                        } label: {
                            Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
        }
        .onAppear {
            history = FoodLog.history(context: modelContext)
            if !didStart, let start {
                didStart = true
                stage = stageFor(start)
            }
        }
    }

    private var isStartStage: Bool {
        guard let start else { return false }
        return stage == stageFor(start)
    }

    private var title: String {
        switch stage {
        case .pick:     return "Log food"
        case .photo:    return "Snap a meal"
        case .scan:     return "Scan barcode"
        case .describe: return "Describe it"
        case .eatingOut: return "Eating out"
        case .review:   return "Review & log"
        }
    }

    private func stageFor(_ method: Method) -> Stage {
        switch method {
        case .photo:    return .photo
        case .scan:     return .scan
        case .describe: return .describe
        case .eatingOut: return .eatingOut
        case .manual:   return .review(stamped(FoodDraft()), .manual)
        }
    }

    private func go(_ next: Stage) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { stage = next }
    }

    /// Time it: now, or noon on a past day.
    private func stamped(_ draft: FoodDraft) -> FoodDraft {
        var d = draft
        if let day, !Calendar.current.isDateInToday(day) {
            d.time = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: day)) ?? day
        } else {
            d.time = Date()
        }
        return d
    }

    private func log(_ draft: FoodDraft) {
        FoodLog.add(draft, context: modelContext)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        onLogged(draft)
        dismiss()
    }

    // MARK: - Pick

    /// Your most-logged foods with their numbers, so Claude can resolve
    /// "my usual cold brew".
    private var cloudUsuals: [FoodCloud.Usual] {
        history.sorted { $0.count > $1.count }.prefix(40).map {
            FoodCloud.Usual(name: $0.draft.name, calories: $0.draft.calories, protein: $0.draft.protein,
                            carbs: $0.draft.carbs ?? 0, fat: $0.draft.fat ?? 0)
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 18) {
            searchField
            if trimmedQuery.isEmpty {
                methods
                eatingOutCard
                if !favorites.isEmpty {
                    savedList(title: "Favorites", icon: "star.fill", items: favorites.map(FoodDraft.init))
                }
                usualsStrip
                historySection
            } else {
                searchResults
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            TextField("Search your history or any food", text: $query)
                .font(.system(size: 16))
                .submitLabel(.search)
                .onSubmit { if !trimmedQuery.isEmpty { describe(trimmedQuery) } }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Neka.inkTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Capsule().fill(Neka.surface.opacity(0.8)))
        .overlay(Capsule().stroke(Neka.Scene.ice.glassStroke, lineWidth: 1))
    }

    private var methods: some View {
        HStack(spacing: 8) {
            MethodChip(icon: "camera.fill", title: "Photo", tint: Neka.lavenderText) { go(.photo) }
            MethodChip(icon: "barcode.viewfinder", title: "Barcode", tint: Neka.skyText) { go(.scan) }
            MethodChip(icon: "text.bubble.fill", title: "Describe", tint: Neka.greenText) { describe("") }
            MethodChip(icon: "square.and.pencil", title: "Manual", tint: Neka.orangeText) { go(stageFor(.manual)) }
        }
    }

    // Eating out: pick a restaurant, get an order that fits today.
    private var eatingOutCard: some View {
        Button { go(.eatingOut) } label: {
            HStack(spacing: 14) {
                Text("🍽️")
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Neka.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eating out?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(FoodCloud.isConfigured ? "Full menus, tagged by what fits today" : "Pick a restaurant — get an order that fits today")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Neka.amberSoft, Neka.orangeSoft], startPoint: .leading, endPoint: .trailing))
            )
        }
        .buttonStyle(.dialedScale)
    }

    @ViewBuilder
    private var usualsStrip: some View {
        let usuals = FoodLog.usuals(history)
        if !usuals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Your usuals", icon: "repeat")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(usuals) { food in
                            Button { go(.review(stamped(food.draft), .saved)) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.draft.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Neka.ink)
                                        .lineLimit(1)
                                    Text("\(Int(food.draft.calories)) cal · \(food.count)×")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Neka.inkSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(maxWidth: 180, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface))
                            }
                            .buttonStyle(.dialedScale)
                            .accessibilityLabel("Add \(food.draft.name)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("History · \(history.count) foods", icon: "clock.arrow.circlepath")
                historyList(Array(history.prefix(historyShown)), groupedByMonth: true)
                if history.count > historyShown {
                    Button("Show more") { historyShown += 50 }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.skyText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let q = trimmedQuery.lowercased()
        let matches = history.filter { $0.draft.name.lowercased().contains(q) }
        VStack(alignment: .leading, spacing: 8) {
            // Anything not in your history: Claude (or the food table) reads it.
            Button { describe(trimmedQuery) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: Neka.intelligence, startPoint: .leading, endPoint: .trailing))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Neka.surface))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Look up “\(trimmedQuery)”")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .lineLimit(1)
                        Text("Any food, brand or restaurant item")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Neka.inkTertiary)
                }
                .padding(14)
                .nekaCard()
            }
            .buttonStyle(.dialedScale)
            if !matches.isEmpty {
                sectionLabel("From your history · \(matches.count)", icon: "clock.arrow.circlepath")
                    .padding(.top, 6)
                historyList(Array(matches.prefix(60)), groupedByMonth: false)
            }
        }
    }

    private func describe(_ text: String) {
        describeSeed = text
        go(.describe)
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Neka.inkSecondary)
    }

    /// Rows of past foods; month headers between them when `groupedByMonth`.
    private func historyList(_ foods: [FoodLog.HistoryFood], groupedByMonth: Bool) -> some View {
        let calendar = Calendar.current
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                let month = calendar.dateInterval(of: .month, for: food.lastEaten)?.start
                let previousMonth = index > 0 ? calendar.dateInterval(of: .month, for: foods[index - 1].lastEaten)?.start : nil
                if groupedByMonth, index > 0, month != previousMonth {
                    Text(food.lastEaten.formatted(.dateTime.month(.wide).year()).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(Neka.inkTertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                } else if index > 0 {
                    Divider().overlay(Neka.hairline).padding(.leading, 14)
                }
                historyRow(food)
            }
        }
        .nekaCard()
    }

    private func historyRow(_ food: FoodLog.HistoryFood) -> some View {
        Button { go(.review(stamped(food.draft), .saved)) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.draft.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .lineLimit(1)
                    Text(historyMeta(food))
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Neka.green)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(food.draft.name)")
    }

    /// "Sep 14 · 610 cal · 44 g · had 6×"
    private func historyMeta(_ food: FoodLog.HistoryFood) -> String {
        let calendar = Calendar.current
        let when: String
        if calendar.isDateInToday(food.lastEaten) {
            when = "Today"
        } else if calendar.isDateInYesterday(food.lastEaten) {
            when = "Yesterday"
        } else if calendar.isDate(food.lastEaten, equalTo: Date(), toGranularity: .year) {
            when = food.lastEaten.formatted(.dateTime.month(.abbreviated).day())
        } else {
            when = food.lastEaten.formatted(.dateTime.month(.abbreviated).day().year())
        }
        var parts = [when, "\(Int(food.draft.calories)) cal", "\(Int(food.draft.protein)) g"]
        if food.count > 1 { parts.append("had \(food.count)×") }
        return parts.joined(separator: " · ")
    }

    private func savedList(title: String, icon: String, items: [FoodDraft]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title, icon: icon)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider().overlay(Neka.hairline).padding(.leading, 14) }
                    Button { go(.review(stamped(item), .saved)) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name.isEmpty ? "Meal" : item.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Neka.ink)
                                    .lineLimit(1)
                                Text("\(Int(item.calories)) calories · \(Int(item.protein)) g protein")
                                    .font(.system(size: 12))
                                    .foregroundColor(Neka.inkSecondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Neka.green)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(item.name)")
                }
            }
            .nekaCard()
        }
    }
}

// MARK: - Method chip

private struct MethodChip: View {
    let icon: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Neka.Scene.ice.glass))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Neka.Scene.ice.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.dialedScale)
    }
}

// MARK: - Photo

/// Take or pick a meal photo; Vision names the foods on-device, you tick
/// what's right and add anything it can't see, then Apple Intelligence
/// estimates the meal.
private struct MealPhotoStep: View {
    var usuals: [FoodCloud.Usual] = []
    var onEstimate: (FoodDraft, [String], AIMealEstimate) -> Void
    var onManual: (FoodDraft) -> Void

    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var seen: [String] = []
    @State private var chosen: Set<String> = []
    @State private var reading = false
    @State private var extra = ""
    @State private var estimating = false
    @State private var failed = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { reset() } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(9)
                                .background(Circle().fill(.black.opacity(0.45)))
                        }
                        .padding(10)
                        .accessibilityLabel("Retake")
                    }
                    .overlay(IntelligenceRim(cornerRadius: 24, active: reading || estimating).allowsHitTesting(false))
                found
            } else {
                capture
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { picked in
                showCamera = false
                if let picked { use(picked) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    use(ui)
                }
                pickerItem = nil
            }
        }
    }

    private var capture: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(LinearGradient(colors: Neka.intelligence, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Snap your plate")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(FoodCloud.isConfigured
                     ? "Claude reads your plate and prices each food from USDA data. You confirm before anything's logged."
                     : "Dialed spots the food on your phone, then Apple Intelligence estimates calories, protein, carbs and fat. You confirm before anything's logged.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)

            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label("Take photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Neka.surface))
                    .overlay(Capsule().stroke(Neka.hairline, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var found: some View {
        VStack(alignment: .leading, spacing: 12) {
            if reading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking at your plate…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            } else {
                Text(seen.isEmpty ? "Couldn't make out the food — tell it what's there:" : "On your plate — tap to keep or drop:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                if !seen.isEmpty {
                    FlowChips(items: seen, selected: $chosen)
                }
                TextField("Add details: portion, sauce, drink…", text: $extra, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))

                Button {
                    Task { await estimate() }
                } label: {
                    HStack {
                        if estimating { ProgressView().tint(Neka.onInk) } else { Image(systemName: "sparkles") }
                        Text(estimating ? (FoodCloud.isConfigured ? "Reading your plate…" : "Estimating on-device…") : "Estimate it")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
                // With the server, the photo alone is enough.
                .disabled(estimating || (!FoodCloud.isConfigured && chosen.isEmpty && extra.trimmingCharacters(in: .whitespaces).isEmpty))
                if failed {
                    Text("Couldn't estimate that one — add a detail or two, or fill it in yourself.")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.rose)
                }
                Button("Fill it in myself") {
                    var d = FoodDraft()
                    d.name = mealName
                    onManual(d)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private var keptItems: [String] { seen.filter { chosen.contains($0) } }

    private var mealName: String {
        let items = keptItems.map { $0.capitalized }
        if !items.isEmpty { return items.prefix(3).joined(separator: ", ") }
        return extra.trimmingCharacters(in: .whitespaces)
    }

    private func use(_ picked: UIImage) {
        image = picked
        reading = true
        failed = false
        Task {
            let names = await MealPhotoReader.foods(in: picked)
            withAnimation {
                seen = names
                chosen = Set(names.prefix(4))
                reading = false
            }
        }
    }

    /// Longest side 1280 px, JPEG 0.7 — plenty to read a plate, a few hundred KB to send.
    private static func uploadJPEG(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 1280 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    private func reset() {
        image = nil
        seen = []
        chosen = []
        extra = ""
        failed = false
    }

    private func estimate() async {
        estimating = true
        failed = false
        defer { estimating = false }
        let jpeg = FoodCloud.isConfigured ? image.flatMap(Self.uploadJPEG) : nil
        guard let r = await DialedAI.estimateMeal(extra, seen: keptItems, photoJPEG: jpeg, usuals: usuals) else {
            failed = true
            return
        }
        var d = FoodDraft()
        d.name = r.name
        d.calories = Double(r.calories)
        d.protein = Double(r.proteinGrams)
        d.carbs = r.carbsGrams.map(Double.init)
        d.fat = r.fatGrams.map(Double.init)
        onEstimate(d, keptItems, r)
    }
}

/// Wrapping, tappable chips.
private struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        // Two-column grid keeps it tidy without a custom layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    if on { selected.remove(item) } else { selected.insert(item) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(item.capitalized)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(on ? Neka.ink : Neka.inkTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(on ? Neka.lavenderSoft : Neka.track))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// UIKit camera, for the meal photo.
struct CameraPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage?) -> Void
        init(onPicked: @escaping (UIImage?) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPicked(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPicked(nil)
        }
    }
}

// MARK: - Describe

private struct DescribeMealStep: View {
    /// Text carried over from search.
    var seed: String = ""
    var usuals: [FoodCloud.Usual] = []
    var onEstimate: (FoodDraft, AIMealEstimate) -> Void
    var onManual: (FoodDraft) -> Void

    @State private var text = ""
    @State private var estimating = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What did you eat?")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Neka.ink)
            TextField("e.g. Chipotle bowl, double chicken, no rice, guac", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 16))
                .focused($focused)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface))
                .overlay(IntelligenceRim(cornerRadius: 16, active: estimating).allowsHitTesting(false))

            Button {
                Task { await estimate() }
            } label: {
                HStack {
                    if estimating { ProgressView().tint(Neka.onInk) } else { Image(systemName: "sparkles") }
                    Text(estimating ? (FoodCloud.isConfigured ? "Reading it…" : "Estimating on-device…") : "Estimate it")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.nekaPrimary)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || estimating)
            if failed {
                Text("Couldn't estimate that one — try adding portion sizes, or fill it in yourself.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.rose)
            }
            Button("Fill it in myself") {
                var d = FoodDraft()
                d.name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                onManual(d)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Neka.inkSecondary)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if text.isEmpty, !seed.isEmpty { text = seed }
            focused = true
        }
    }

    private func estimate() async {
        estimating = true
        failed = false
        defer { estimating = false }
        guard let r = await DialedAI.estimateMeal(text, usuals: usuals) else {
            failed = true
            return
        }
        var d = FoodDraft()
        d.name = r.name
        d.calories = Double(r.calories)
        d.protein = Double(r.proteinGrams)
        d.carbs = r.carbsGrams.map(Double.init)
        d.fat = r.fatGrams.map(Double.init)
        onEstimate(d, r)
    }
}

// MARK: - Review

/// The one confirm screen: name, time, calories with quick nudges, the
/// macros, where the numbers came from, save-as-favorite, then Log.
private struct FoodReviewStep: View {
    @State var draft: FoodDraft
    let source: AddFoodSheet.Source
    var onLog: (FoodDraft) -> Void

    @State private var saveFavorite = false
    /// What's in it, when the estimate was itemized.
    @State private var parts: [MealPart]
    /// How many of what was estimated / scanned you had; the numbers above
    /// are always `base` × this.
    @State private var servings: Double
    @State private var base: FoodDraft
    @State private var baseParts: [MealPart]

    init(draft: FoodDraft, source: AddFoodSheet.Source, onLog: @escaping (FoodDraft) -> Void) {
        _draft = State(initialValue: draft)
        // Opened on 2 servings (a recent you had twice)? Keep it at 2, scaling from one.
        let s = ServingsPicker.clamp(draft.servings)
        var one = draft
        one.calories /= s
        one.protein /= s
        one.carbs = draft.carbs.map { $0 / s }
        one.fat = draft.fat.map { $0 / s }
        _base = State(initialValue: one)
        _servings = State(initialValue: s)
        self.source = source
        self.onLog = onLog
        let start: [MealPart]
        switch source {
        case .photo(_, _, let parts), .described(_, let parts): start = parts
        default: start = []
        }
        _parts = State(initialValue: start)
        _baseParts = State(initialValue: start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("What is it?", text: $draft.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Neka.ink)
                DatePicker("Time", selection: $draft.time)
                    .font(.system(size: 14))
                    .foregroundColor(Neka.inkSecondary)
                sourceNote
            }
            .padding(16)
            .nekaCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("How much did you have?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                ServingsPicker(servings: servings) { setServings($0) }
            }
            .padding(16)
            .nekaCard()

            if !parts.isEmpty { breakdown }

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    LiveNumberField(value: edited(\.calories), font: .system(size: 44, weight: .bold, design: .rounded),
                                    alignment: .leading)
                        .fixedSize()
                    Text("calories")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    ForEach([-100.0, -25, 25, 100], id: \.self) { step in
                        Button(step > 0 ? "+\(Int(step))" : "\(Int(step))") {
                            edited(\.calories).wrappedValue = max(0, draft.calories + step)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Neka.track))
                        .buttonStyle(.dialedScale)
                    }
                }
                HStack(spacing: 10) {
                    macro("Protein", value: edited(\.protein), tint: Neka.green, fill: Neka.greenSoft)
                    macro("Carbs", value: optional(editedOptional(\.carbs)), tint: Neka.sky, fill: Neka.skySoft)
                    macro("Fat", value: optional(editedOptional(\.fat)), tint: Neka.lavender, fill: Neka.lavenderSoft)
                }
            }
            .padding(16)
            .nekaCard()

            Toggle(isOn: $saveFavorite) {
                Label("Save to favorites", systemImage: "star")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
            .tint(Neka.green)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .nekaCard()

            Button {
                if saveFavorite && !draft.name.isEmpty {
                    // A favorite is one serving.
                    SavedMealsManager.add(SavedMeal(name: draft.name, calories: base.calories, proteinGrams: base.protein,
                                                    carbsGrams: base.carbs, fatGrams: base.fat))
                }
                var logged = draft
                logged.servings = servings
                onLog(logged)
            } label: {
                Label("Log \(Int(draft.calories.rounded())) calories", systemImage: "checkmark")
                    .contentTransition(.numericText(value: draft.calories))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.nekaPrimary)
            .disabled(draft.calories <= 0 && draft.protein <= 0)
        }
    }

    // MARK: Breakdown

    /// Each food with its amount and calories; nudge a portion or drop an
    /// item and the totals follow.
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What's in it")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Text("\(Int(parts.reduce(0) { $0 + $1.calories })) calories")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                    .contentTransition(.numericText(value: parts.reduce(0) { $0 + $1.calories }))
            }
            ForEach(parts) { part in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(part.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        Text(part.sourceLabel.map { "\(part.amount) · \($0)" } ?? (part.fromTable ? part.amount : "\(part.amount) · estimated"))
                            .font(.system(size: 11.5))
                            .foregroundColor(Neka.inkSecondary)
                    }
                    Spacer(minLength: 6)
                    Text("\(Int(part.calories.rounded()))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Neka.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: part.calories))
                    if part.calories > 0 {
                        portionButton("minus") { adjust(part, by: -1) }
                        portionButton("plus") { adjust(part, by: 1) }
                    }
                    Button { remove(part) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Neka.inkTertiary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(part.name)")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func portionButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Neka.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Neka.track))
        }
        .buttonStyle(.plain)
    }

    /// One step more or less of a food: whole units at 2+, halves below.
    private func adjust(_ part: MealPart, by direction: Double) {
        guard let i = parts.firstIndex(where: { $0.id == part.id }) else { return }
        let fractions: [String: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75, "1½": 1.5, "2½": 2.5]
        let first = String(part.amount.split(separator: " ").first ?? "")
        let current = Double(first) ?? fractions[first] ?? 1
        let step = current > 2 || (current == 2 && direction > 0) ? 1.0 : 0.5
        let next = max(step == 1 ? 1 : 0.5, current + direction * step)
        guard next != current, current > 0 else { return }
        let factor = next / current
        withAnimation(.snappy(duration: 0.3)) {
            parts[i] = part.scaled(factor)
            if let b = baseParts.firstIndex(where: { $0.id == part.id }) { baseParts[b] = baseParts[b].scaled(factor) }
            recalc()
        }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    private func remove(_ part: MealPart) {
        withAnimation(.snappy(duration: 0.3)) {
            parts.removeAll { $0.id == part.id }
            baseParts.removeAll { $0.id == part.id }
            recalc()
        }
    }

    /// Totals from the items (when itemized), for one serving and for all.
    private func recalc() {
        func sum(_ list: [MealPart], _ key: KeyPath<MealPart, Double>) -> Double { list.reduce(0) { $0 + $1[keyPath: key] } }
        base.calories = sum(baseParts, \.calories)
        base.protein = sum(baseParts, \.protein)
        base.carbs = sum(baseParts, \.carbs)
        base.fat = sum(baseParts, \.fat)
        applyServings()
    }

    // MARK: Servings

    private func setServings(_ value: Double) {
        let s = ServingsPicker.clamp(value)
        guard s != servings else { return }
        withAnimation(.snappy(duration: 0.3)) {
            servings = s
            parts = baseParts.map { $0.scaled(s) }
            applyServings()
        }
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// The shown numbers are always one serving × servings.
    private func applyServings() {
        draft.calories = (base.calories * servings).rounded()
        draft.protein = (base.protein * servings).rounded()
        draft.carbs = base.carbs.map { ($0 * servings).rounded() }
        draft.fat = base.fat.map { ($0 * servings).rounded() }
    }

    /// A total you can type or nudge; it becomes the new per-serving value.
    private func edited(_ key: WritableKeyPath<FoodDraft, Double>) -> Binding<Double> {
        Binding(
            get: { draft[keyPath: key] },
            set: { new in
                withAnimation(.snappy(duration: 0.25)) {
                    draft[keyPath: key] = max(0, new)
                    base[keyPath: key] = max(0, new) / servings
                }
            }
        )
    }

    private func editedOptional(_ key: WritableKeyPath<FoodDraft, Double?>) -> Binding<Double?> {
        Binding(
            get: { draft[keyPath: key] },
            set: { new in
                draft[keyPath: key] = new.map { max(0, $0) }
                base[keyPath: key] = new.map { max(0, $0) / servings }
            }
        )
    }

    @ViewBuilder
    private var sourceNote: some View {
        switch source {
        case .photo(let seen, let assumption, _):
            note("sparkles", "From your photo\(seen.isEmpty ? "" : " (\(seen.joined(separator: ", ")))")." + (assumption.map { " \($0)" } ?? ""))
        case .described(let assumption, let parts):
            note(parts.allSatisfy(\.fromTable) && !parts.isEmpty ? "list.bullet.rectangle" : "sparkles",
                 assumption ?? (FoodCloud.isConfigured ? "Estimated by Claude." : "Estimated by Apple Intelligence."))
        case .barcode:
            note("barcode", "From the label via Open Food Facts — double-check the serving.")
        case .saved:
            note("star", "From your favorites and recents.")
        case .manual:
            EmptyView()
        }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12))
            .foregroundColor(Neka.inkSecondary)
    }

    private func optional(_ binding: Binding<Double?>) -> Binding<Double> {
        Binding(get: { binding.wrappedValue ?? 0 }, set: { binding.wrappedValue = $0 })
    }

    private func macro(_ title: String, value: Binding<Double>, tint: Color, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                LiveNumberField(value: value, font: .system(size: 22, weight: .semibold, design: .rounded), alignment: .leading)
                    .fixedSize()
                Text("g")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
            HStack(spacing: 6) {
                stepButton("minus") { value.wrappedValue = max(0, value.wrappedValue - 5) }
                stepButton("plus") { value.wrappedValue += 5 }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Neka.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Neka.surface.opacity(0.8)))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddFoodSheet()
}
