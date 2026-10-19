//
//  AddFoodSheet.swift
//  Dialed
//
//  The one way to add food, wherever you start: Home, the + menu, the
//  Food log, the Nutrition page or a widget. Pick how — snap a photo
//  (Apple Intelligence estimates it), scan a barcode, describe it, or
//  type it in — or tap a favorite or recent. Every path ends on the same
//  review screen, so what you confirm and how it's logged never changes.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddFoodSheet: View {
    enum Method: String, Equatable {
        case photo, scan, describe, manual
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
    @State private var recents: [FoodDraft] = []
    @State private var didStart = false

    enum Stage: Equatable {
        case pick
        case photo
        case scan
        case describe
        case review(FoodDraft, Source)
    }

    /// Where the numbers came from — shown on the review screen.
    enum Source: Equatable {
        case photo(seen: [String], assumption: String?)
        case barcode
        case described(assumption: String?)
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
                        MealPhotoStep { draft, seen, note in
                            go(.review(stamped(draft), .photo(seen: seen, assumption: note)))
                        } onManual: { draft in
                            go(.review(stamped(draft), .manual))
                        }
                    case .scan:
                        BarcodeScanView { draft in
                            go(.review(stamped(draft), draft.name.isEmpty ? .manual : .barcode))
                        }
                        .frame(minHeight: 560)
                    case .describe:
                        DescribeMealStep { draft, note in
                            go(.review(stamped(draft), .described(assumption: note)))
                        } onManual: { draft in
                            go(.review(stamped(draft), .manual))
                        }
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
            .nekaPageBackground()
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
            recents = FoodLog.recents(context: modelContext)
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
        case .pick:     return "Add food"
        case .photo:    return "Snap a meal"
        case .scan:     return "Scan barcode"
        case .describe: return "Describe it"
        case .review:   return "Review & log"
        }
    }

    private func stageFor(_ method: Method) -> Stage {
        switch method {
        case .photo:    return .photo
        case .scan:     return .scan
        case .describe: return .describe
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

    private var picker: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    MethodTile(icon: "camera.fill", title: "Snap a meal",
                               subtitle: DialedAI.isAvailable ? "Apple Intelligence estimates it" : "Photo, then fill in",
                               tint: Neka.lavender, fill: Neka.lavenderSoft, sparkle: DialedAI.isAvailable) { go(.photo) }
                    MethodTile(icon: "barcode.viewfinder", title: "Scan barcode",
                               subtitle: "Packaged food, exact label",
                               tint: Neka.sky, fill: Neka.skySoft) { go(.scan) }
                }
                HStack(spacing: 12) {
                    MethodTile(icon: "text.bubble.fill", title: "Describe it",
                               subtitle: "\"Chipotle bowl, double chicken\"",
                               tint: Neka.green, fill: Neka.greenSoft, sparkle: DialedAI.isAvailable) { go(.describe) }
                    MethodTile(icon: "square.and.pencil", title: "Enter by hand",
                               subtitle: "Calories, protein, carbs, fat",
                               tint: Neka.orange, fill: Neka.orangeSoft) { go(stageFor(.manual)) }
                }
            }

            if !favorites.isEmpty {
                savedList(title: "Favorites", icon: "star.fill", items: favorites.map(FoodDraft.init))
            }
            if !recents.isEmpty {
                savedList(title: "Recent", icon: "clock.arrow.circlepath", items: Array(recents.prefix(6)))
            }
        }
    }

    private func savedList(title: String, icon: String, items: [FoodDraft]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
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
                                Text("\(Int(item.calories)) kcal · \(Int(item.protein)) g protein")
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

// MARK: - Method tile

private struct MethodTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let fill: Color
    var sparkle = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Neka.surface))
                    Spacer()
                    if sparkle {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LinearGradient(colors: Neka.intelligence, startPoint: .leading, endPoint: .trailing))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(Neka.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill))
        }
        .buttonStyle(.dialedScale)
    }
}

// MARK: - Photo

/// Take or pick a meal photo; Vision names the foods on-device, you tick
/// what's right and add anything it can't see, then Apple Intelligence
/// estimates the meal.
private struct MealPhotoStep: View {
    var onEstimate: (FoodDraft, [String], String?) -> Void
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
                Text("Dialed spots the food on your phone, then Apple Intelligence estimates calories, protein, carbs and fat. You confirm before anything's logged.")
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

                if DialedAI.isAvailable {
                    Button {
                        Task { await estimate() }
                    } label: {
                        HStack {
                            if estimating { ProgressView().tint(Neka.onInk) } else { Image(systemName: "sparkles") }
                            Text(estimating ? "Estimating on-device…" : "Estimate with Apple Intelligence")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.nekaPrimary)
                    .disabled(estimating || (chosen.isEmpty && extra.trimmingCharacters(in: .whitespaces).isEmpty))
                } else {
                    Text(DialedAI.availability.explanation)
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
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
        guard let r = await DialedAI.estimateMeal(extra, seen: keptItems) else {
            failed = true
            return
        }
        var d = FoodDraft()
        d.name = r.name
        d.calories = Double(r.calories)
        d.protein = Double(r.proteinGrams)
        d.carbs = r.carbsGrams.map(Double.init)
        d.fat = r.fatGrams.map(Double.init)
        onEstimate(d, keptItems, r.assumption)
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
    var onEstimate: (FoodDraft, String?) -> Void
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

            if DialedAI.isAvailable {
                Button {
                    Task { await estimate() }
                } label: {
                    HStack {
                        if estimating { ProgressView().tint(Neka.onInk) } else { Image(systemName: "sparkles") }
                        Text(estimating ? "Estimating on-device…" : "Estimate with Apple Intelligence")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || estimating)
            } else {
                Text(DialedAI.availability.explanation)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            }
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
        .onAppear { focused = true }
    }

    private func estimate() async {
        estimating = true
        failed = false
        defer { estimating = false }
        guard let r = await DialedAI.estimateMeal(text) else {
            failed = true
            return
        }
        var d = FoodDraft()
        d.name = r.name
        d.calories = Double(r.calories)
        d.protein = Double(r.proteinGrams)
        d.carbs = r.carbsGrams.map(Double.init)
        d.fat = r.fatGrams.map(Double.init)
        onEstimate(d, r.assumption)
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

    init(draft: FoodDraft, source: AddFoodSheet.Source, onLog: @escaping (FoodDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.source = source
        self.onLog = onLog
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

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", value: $draft.calories, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(Neka.ink)
                        .fixedSize()
                    Text("kcal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    ForEach([-100.0, -25, 25, 100], id: \.self) { step in
                        Button(step > 0 ? "+\(Int(step))" : "\(Int(step))") {
                            draft.calories = max(0, draft.calories + step)
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
                    macro("Protein", value: $draft.protein, tint: Neka.green, fill: Neka.greenSoft)
                    macro("Carbs", value: optional($draft.carbs), tint: Neka.sky, fill: Neka.skySoft)
                    macro("Fat", value: optional($draft.fat), tint: Neka.lavender, fill: Neka.lavenderSoft)
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
                    SavedMealsManager.add(SavedMeal(name: draft.name, calories: draft.calories, proteinGrams: draft.protein,
                                                    carbsGrams: draft.carbs, fatGrams: draft.fat))
                }
                onLog(draft)
            } label: {
                Label("Log \(Int(draft.calories)) kcal", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.nekaPrimary)
            .disabled(draft.calories <= 0 && draft.protein <= 0)
        }
    }

    @ViewBuilder
    private var sourceNote: some View {
        switch source {
        case .photo(let seen, let assumption):
            note("sparkles", "Estimated by Apple Intelligence from your photo\(seen.isEmpty ? "" : " (\(seen.joined(separator: ", ")))")." + (assumption.map { " \($0)" } ?? ""))
        case .described(let assumption):
            note("sparkles", "Estimated by Apple Intelligence." + (assumption.map { " \($0)" } ?? ""))
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
                TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Neka.ink)
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
