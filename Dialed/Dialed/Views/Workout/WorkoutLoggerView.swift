//
//  WorkoutLoggerView.swift
//  Dialed
//
//  Log a plan day: every exercise from the session with its
//  prescription, rows of sets (lb × reps) pre-filled from last time's
//  progression suggestion, quick +/- steppers, tap a set's number to
//  finish it (starts the optional 60/90 s rest timer), add/remove sets
//  and notes. Bike / walk days log duration and distance. Or just type
//  what you did ("bench 185x8x4, squat 225 5x5") and the sets fill in.
//  Saving stores the sets in SwiftData, checks the day off, and adjusts
//  the rest of the week if you trained a different day's workout.
//

import SwiftUI
import SwiftData

struct WorkoutLoggerView: View {
    let day: Date
    let session: WorkoutProgram.Session
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workout.restSeconds") private var restSeconds = 90

    @State private var exercises: [ExerciseDraft] = []
    @State private var notes = ""
    @State private var durationMinutes: Double?
    @State private var distanceMiles: Double?
    @State private var restEndsAt: Date?
    @State private var loaded = false
    @State private var hasExistingLog = false
    @State private var confirmDelete = false
    @State private var typed = ""
    @State private var reading = false
    @State private var typedResult: String?
    @State private var summary: [String]?
    @FocusState private var typing: Bool

    private var isCardio: Bool { session.kind == .bike || session.kind == .walk }
    private var dayKey: String { WorkoutPlanStore.key(day) }

    struct SetDraft: Identifiable, Equatable {
        let id = UUID()
        var weight: Double?
        var reps: Int
        var done = false
    }

    struct ExerciseDraft: Identifiable {
        let id = UUID()
        let order: Int
        let name: String
        let prescriptionText: String
        let prescription: StrengthProgression.Prescription?
        let equipment: StrengthProgression.Equipment
        let suggestion: StrengthProgression.Suggestion?
        let lastSummary: String?
        /// Long timed work ("15 min" bike) is just a done check.
        let checkOnly: Bool
        var sets: [SetDraft]

        var tracksWeight: Bool { equipment != .bodyweight && !checkOnly }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    typeCard
                    if isCardio {
                        cardioCard
                    } else {
                        restCard
                    }
                    ForEach($exercises) { $exercise in
                        exerciseCard($exercise)
                    }
                    notesCard
                    if hasExistingLog {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete this log", systemImage: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundColor(Neka.rose)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .nekaPageBackground()
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let end = restEndsAt {
                    restBanner(until: end)
                }
            }
            .confirmationDialog("Delete this workout log?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteLog() }
            } message: {
                Text("The sets are removed and the day is unchecked in your plan.")
            }
            .onAppear(perform: loadIfNeeded)
            .alert("Saved", isPresented: Binding(get: { summary != nil }, set: { if !$0 { finish() } })) {
                Button("Nice", role: .cancel) {}
            } message: {
                Text((summary ?? []).joined(separator: "\n"))
            }
        }
    }

    // MARK: - Type it

    /// Type (or dictate) what you did; the sets fill in below.
    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Type what you did", systemImage: "keyboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            TextField("bench 185x8x4, squat 225 5x5, lat pulldown 120 3x10", text: $typed, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 15))
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.track))
            HStack(spacing: 10) {
                Button {
                    Task { await fillFromText() }
                } label: {
                    HStack(spacing: 6) {
                        if reading { ProgressView().tint(Neka.onInk) } else { Image(systemName: "wand.and.stars") }
                        Text(reading ? "Reading…" : "Fill in sets")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.onInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || reading)
                Spacer()
                Text("weight × reps × sets, or sets × reps @ weight")
                    .font(.system(size: 10))
                    .foregroundColor(Neka.inkTertiary)
                    .multilineTextAlignment(.trailing)
            }
            if let typedResult {
                Label(typedResult, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.greenText)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func fillFromText() async {
        typing = false
        reading = true
        defer { reading = false }
        let known = exercises.map(\.name) + Self.allPlanExercises
        var parsed = WorkoutTextParser.parse(typed, known: known)
        if parsed.isEmpty, let ai = await DialedAI.parseWorkout(typed) {
            parsed = ai.map { e in
                var e = e
                e.name = WorkoutTextParser.canonical(e.name, known: known)
                return e
            }
        }
        guard !parsed.isEmpty else {
            typedResult = nil
            withAnimation { typedResult = "Couldn't read that — try \"bench 185x8x4\"." }
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { apply(parsed) }
        let setCount = parsed.reduce(0) { $0 + $1.sets.count }
        typedResult = "Filled \(parsed.count) exercise\(parsed.count == 1 ? "" : "s")\(setCount > 0 ? ", \(setCount) sets" : "") — check and save."
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Typed sets replace that exercise's rows (marked done); new exercises
    /// are added at the end; cardio fills duration and distance.
    private func apply(_ parsed: [WorkoutTextParser.ParsedExercise]) {
        for p in parsed {
            if p.sets.isEmpty {
                if isCardio || WeekPlanAdjuster.focus(of: p.name).contains(.cardio) {
                    if let m = p.minutes { durationMinutes = m }
                    if let mi = p.miles { distanceMiles = mi }
                    if !isCardio { notes = [notes, describe(p)].filter { !$0.isEmpty }.joined(separator: "\n") }
                    continue
                }
                if let i = exercises.firstIndex(where: { $0.name == p.name }) {
                    for j in exercises[i].sets.indices { exercises[i].sets[j].done = true }
                } else {
                    notes = [notes, describe(p)].filter { !$0.isEmpty }.joined(separator: "\n")
                }
                continue
            }
            let sets = p.sets.map { SetDraft(weight: $0.weight, reps: $0.reps, done: true) }
            if let i = exercises.firstIndex(where: { $0.name == p.name }) {
                exercises[i].sets = sets
            } else {
                let equipment = StrengthProgression.equipment(for: p.name)
                exercises.append(ExerciseDraft(
                    order: (exercises.map(\.order).max() ?? -1) + 1, name: p.name,
                    prescriptionText: "\(p.sets.count) × \(p.sets.first?.reps ?? 0)",
                    prescription: .setsReps(sets: p.sets.count, reps: p.sets.map(\.reps).max() ?? 0, perSide: false),
                    equipment: equipment, suggestion: nil, lastSummary: nil,
                    checkOnly: false, sets: sets))
            }
        }
    }

    private func describe(_ p: WorkoutTextParser.ParsedExercise) -> String {
        var parts = [p.name]
        if let m = p.minutes { parts.append(m < 1 ? "\(Int(m * 60)) s" : "\(formatPounds(m)) min") }
        if let mi = p.miles { parts.append(String(format: "%.1f mi", mi)) }
        return parts.joined(separator: " · ")
    }

    /// Every exercise in the plan, for matching typed names.
    static let allPlanExercises: [String] = {
        let sessions = [WorkoutProgram.strengthA, WorkoutProgram.strengthB, WorkoutProgram.strengthC(rounds: 3),
                        WorkoutProgram.light, WorkoutProgram.bike(week: 1, withLongWalk: false)]
        var seen = Set<String>()
        return sessions.flatMap { $0.exercises.map(\.name) }.filter { seen.insert($0).inserted }
    }()

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Calendar.current.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(Neka.inkTertiary)
            Text(session.title)
                .font(Neka.display(24, weight: .bold))
                .foregroundColor(Neka.ink)
            ForEach(session.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isCardio {
                Text("Tap a set's number when you finish it. Only finished sets count toward progress.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard(wash: .mint)
    }

    // MARK: - Rest

    private var restCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundColor(Neka.ink)
            Text("Rest timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            Spacer(minLength: 8)
            Picker("Rest timer", selection: $restSeconds) {
                Text("Off").tag(0)
                Text("60 s").tag(60)
                Text("90 s").tag(90)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
        .padding(14)
        .nekaCard()
    }

    private func restBanner(until end: Date) -> some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(end.timeIntervalSince(context.date).rounded(.up))
            let label: String = left > 0
                ? "Rest \(left / 60):" + String(format: "%02d", left % 60)
                : "Rest's up — next set"
            HStack(spacing: 12) {
                Image(systemName: left > 0 ? "timer" : "bolt.fill")
                    .font(.system(size: 16, weight: .bold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Spacer()
                Button(left > 0 ? "Skip" : "Dismiss") { restEndsAt = nil }
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(Neka.onInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(left > 0 ? Neka.ink : Neka.green))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Exercise

    private func exerciseCard(_ exercise: Binding<ExerciseDraft>) -> some View {
        let ex = exercise.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ex.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                NekaPill(text: ex.prescriptionText, tint: Neka.ink, fill: Neka.track)
            }

            if ex.tracksWeight {
                if let s = ex.suggestion {
                    Label("\(formatPounds(s.weight)) lb · \(s.reason)", systemImage: suggestionIcon(s.kind))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(suggestionColor(s.kind))
                } else if ex.prescription?.reps != nil {
                    Label(StrengthProgression.firstTimeHint, systemImage: "lightbulb")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            if let last = ex.lastSummary {
                Text(last)
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }

            ForEach(exercise.sets) { $set in
                let index = (ex.sets.firstIndex { $0.id == set.id } ?? 0) + 1
                setRow(index: index, set: $set, exercise: ex) {
                    finished(setID: set.id, in: exercise)
                }
            }

            if !ex.checkOnly {
                HStack(spacing: 10) {
                    Button { addSet(to: exercise) } label: {
                        Label("Add set", systemImage: "plus")
                    }
                    if ex.sets.count > 1 {
                        Button { exercise.wrappedValue.sets.removeLast() } label: {
                            Label("Remove set", systemImage: "minus")
                        }
                    }
                    Spacer()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func setRow(index: Int, set: Binding<SetDraft>, exercise: ExerciseDraft, onFinish: @escaping () -> Void) -> some View {
        let s = set.wrappedValue
        return HStack(spacing: 8) {
            Button {
                set.wrappedValue.done.toggle()
                if set.wrappedValue.done { onFinish() }
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                ZStack {
                    Circle().fill(s.done ? Neka.green : Neka.track)
                    if s.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Neka.onInk)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(index)\(s.done ? ", done" : "")")

            if exercise.checkOnly {
                Text(s.done ? "Done" : "Tap when done")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                Spacer()
            } else {
                if exercise.tracksWeight {
                    stepButton("minus") {
                        let w = set.wrappedValue.weight ?? 0
                        set.wrappedValue.weight = max(0, w - exercise.equipment.step)
                    }
                    TextField("lb", value: set.weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 52)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Neka.track))
                    stepButton("plus") {
                        set.wrappedValue.weight = (set.wrappedValue.weight ?? 0) + exercise.equipment.step
                    }
                    Text("×")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                }
                Spacer(minLength: 0)
                stepButton("minus") {
                    set.wrappedValue.reps = max(0, set.wrappedValue.reps - 1)
                }
                Text("\(s.reps)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Neka.ink)
                    .frame(minWidth: 26)
                stepButton("plus") {
                    set.wrappedValue.reps += 1
                }
                Text(exercise.prescription?.reps == nil ? "reps" : "")
                    .font(.system(size: 10))
                    .foregroundColor(Neka.inkTertiary)
                    .frame(width: exercise.prescription?.reps == nil ? 26 : 0)
            }
        }
        .opacity(s.done ? 0.75 : 1)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Neka.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Neka.track))
        }
        .buttonStyle(.plain)
    }

    private func suggestionIcon(_ kind: StrengthProgression.Suggestion.Kind) -> String {
        switch kind {
        case .increase:     return "arrow.up.circle.fill"
        case .repeatWeight: return "equal.circle.fill"
        case .deload:       return "arrow.down.circle.fill"
        }
    }

    private func suggestionColor(_ kind: StrengthProgression.Suggestion.Kind) -> Color {
        switch kind {
        case .increase:     return Neka.green
        case .repeatWeight: return Neka.inkSecondary
        case .deload:       return Neka.orange
        }
    }

    private func finished(setID: UUID, in exercise: Binding<ExerciseDraft>) {
        // Carry the weight forward to the next empty sets.
        if let i = exercise.wrappedValue.sets.firstIndex(where: { $0.id == setID }),
           let w = exercise.wrappedValue.sets[i].weight {
            for j in exercise.wrappedValue.sets.indices where j > i && exercise.wrappedValue.sets[j].weight == nil {
                exercise.wrappedValue.sets[j].weight = w
            }
        }
        if restSeconds > 0 && !exercise.wrappedValue.checkOnly {
            restEndsAt = Date().addingTimeInterval(TimeInterval(restSeconds))
        }
    }

    private func addSet(to exercise: Binding<ExerciseDraft>) {
        let last = exercise.wrappedValue.sets.last
        exercise.wrappedValue.sets.append(SetDraft(
            weight: last?.weight,
            reps: last?.reps ?? exercise.wrappedValue.prescription?.reps ?? 0
        ))
    }

    // MARK: - Cardio

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(session.exercises, id: \.self) { e in
                HStack {
                    Text(e.name)
                        .font(.system(size: 14))
                        .foregroundColor(Neka.ink)
                    Spacer(minLength: 8)
                    Text(e.prescription)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            Divider().overlay(Neka.hairline)
            cardioField(title: "Duration", unit: "min", value: $durationMinutes, step: 5)
            cardioField(title: "Distance", unit: "mi", value: $distanceMiles, step: 0.25)
            if let walk = session.walk {
                Label(walk, systemImage: "pawprint.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func cardioField(title: String, unit: String, value: Binding<Double?>, step: Double) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            Spacer()
            stepButton("minus") { value.wrappedValue = max(0, (value.wrappedValue ?? 0) - step) }
            TextField(unit, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .frame(width: 60)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Neka.track))
            stepButton("plus") { value.wrappedValue = (value.wrappedValue ?? 0) + step }
            Text(unit)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkTertiary)
                .frame(width: 26, alignment: .leading)
        }
    }

    // MARK: - Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            TextField("How did it feel? Anything to change next time?", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 14))
        }
        .padding(16)
        .nekaCard()
    }

    // MARK: - Load / save

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        let existing = PlanWorkoutLogStore.log(for: dayKey, context: context)
        hasExistingLog = existing != nil
        let savedSets = existing.map { PlanWorkoutLogStore.sets(for: $0.id, context: context) } ?? []
        notes = existing?.notes ?? ""
        durationMinutes = existing?.durationMinutes ?? (isCardio && session.minutes > 0 ? Double(session.minutes) : nil)
        distanceMiles = existing?.distanceMiles

        guard !isCardio else { return }
        let rounds = Self.rounds(in: session)
        exercises = session.exercises.enumerated().map { pair -> ExerciseDraft in
            let order = pair.offset
            let e = pair.element
            let rx = StrengthProgression.parse(e.prescription)
            let equipment = StrengthProgression.equipment(for: e.name)
            var checkOnly = false
            if case let .duration(seconds)? = rx, seconds > 120 { checkOnly = true }
            if rx == nil { checkOnly = true }

            let last = PlanWorkoutLogStore.lastSession(of: e.name, before: day, context: context)
            let suggestion = StrengthProgression.suggest(
                exerciseName: e.name, prescription: rx,
                lastSession: last.map(\.asLoggedSet)
            )
            let lastDone = last.filter(\.completed)
            let lastSummary: String? = lastDone.isEmpty ? nil : { () -> String in
                let when = lastDone[0].date.formatted(.dateTime.month(.abbreviated).day())
                let weights = Set(lastDone.map(\.weightLbs))
                let reps = lastDone.map { "\($0.reps)" }.joined(separator: ", ")
                if weights.count == 1, let w = weights.first, w > 0 {
                    return "Last (\(when)): \(formatPounds(w)) lb × \(reps)"
                }
                return "Last (\(when)): " + lastDone.map { $0.weightLbs > 0 ? "\(formatPounds($0.weightLbs))×\($0.reps)" : "\($0.reps)" }.joined(separator: ", ")
            }()

            let mine = savedSets.filter { $0.exerciseName == e.name }.sorted { $0.setIndex < $1.setIndex }
            let sets: [SetDraft]
            if !mine.isEmpty {
                sets = mine.map { SetDraft(weight: $0.weightLbs > 0 ? $0.weightLbs : nil, reps: $0.reps, done: $0.completed) }
            } else {
                let count = checkOnly ? 1 : (rx?.sets ?? rounds)
                let reps = rx?.reps ?? 0
                let lastWeight = lastDone.map(\.weightLbs).max()
                let weight = equipment == .bodyweight ? nil : (suggestion?.weight ?? (rx?.reps == nil ? lastWeight : nil))
                sets = (0..<max(1, count)).map { _ in SetDraft(weight: weight.flatMap { $0 > 0 ? $0 : nil }, reps: reps) }
            }
            return ExerciseDraft(
                order: order, name: e.name, prescriptionText: e.prescription, prescription: rx,
                equipment: equipment, suggestion: suggestion, lastSummary: lastSummary,
                checkOnly: checkOnly, sets: sets
            )
        }
    }

    /// "4 rounds · 45 s on…" → 4; circuits default to 3.
    static func rounds(in session: WorkoutProgram.Session) -> Int {
        for note in session.notes {
            let digits = note.prefix { $0.isNumber }
            if let n = Int(digits), n > 0, note.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).hasPrefix("round") {
                return n
            }
        }
        return 3
    }

    private func save() {
        let date = Calendar.current.startOfDay(for: day)
        let notesSummary = adjustWeek()
        let log: PlanWorkoutLog
        if let existing = PlanWorkoutLogStore.log(for: dayKey, context: context) {
            log = existing
            PlanWorkoutLogStore.deleteSets(of: existing.id, context: context)
        } else {
            log = PlanWorkoutLog(dayKey: dayKey, date: date, title: session.title, kindRaw: session.kind.rawValue)
            context.insert(log)
        }
        let ran = WorkoutPlanStore.session(on: day)
        log.title = ran.title
        log.kindRaw = ran.kind.rawValue
        log.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        log.durationMinutes = isCardio ? durationMinutes : nil
        log.distanceMiles = isCardio ? distanceMiles : nil
        log.savedAt = Date()

        do {
            for ex in exercises {
                for (i, s) in ex.sets.enumerated() {
                    context.insert(PlanSetLog(
                        workoutID: log.id, date: date, exerciseName: ex.name,
                        exerciseOrder: ex.order, setIndex: i,
                        weightLbs: s.weight ?? 0, reps: s.reps,
                        targetReps: ex.prescription?.reps, completed: s.done
                    ))
                }
            }
        }
        try? context.save()
        PlanWorkoutLogStore.setDone(dayKey, true)
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        let lines = notesSummary + nextTimeLines()
        if lines.isEmpty {
            finish()
        } else {
            summary = lines
        }
    }

    private func finish() {
        summary = nil
        onSaved()
        dismiss()
    }

    /// If you trained a later day's workout today, swap the two days so the
    /// rest of the week still covers everything. Returns what changed.
    private func adjustWeek() -> [String] {
        let calendar = Calendar.current
        let logged = exercises.filter { $0.sets.contains(where: \.done) }.map(\.name)
        let start = calendar.startOfDay(for: day)
        // The rest of this week (through Sunday), not yet done.
        let doneKeys = Set((UserDefaults.standard.string(forKey: WorkoutPlanStore.doneKey) ?? "").split(separator: ",").map(String.init))
        var upcoming: [(date: Date, session: WorkoutProgram.Session)] = []
        var d = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        while calendar.component(.weekday, from: d) != 2, upcoming.count < 6 {   // stop at Monday
            if !doneKeys.contains(WorkoutPlanStore.key(d)) {
                upcoming.append((d, WorkoutPlanStore.session(on: d)))
            }
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
        }
        guard let target = WeekPlanAdjuster.swapTarget(logged: logged, todayPlan: WorkoutPlanStore.session(on: day),
                                                       upcoming: upcoming) else { return [] }
        let todayPlan = WorkoutPlanStore.session(on: day)
        let targetPlan = WorkoutPlanStore.session(on: target)
        WorkoutPlanStore.swap(day, target)
        let weekday = target.formatted(.dateTime.weekday(.wide))
        return ["You did \(targetPlan.title) today, so \(weekday) is now \(todayPlan.title)."]
    }

    /// "Bench press: go up to 190 lb next time."
    private func nextTimeLines() -> [String] {
        exercises.compactMap { ex -> String? in
            guard ex.tracksWeight else { return nil }
            let done = ex.sets.filter(\.done)
            guard !done.isEmpty else { return nil }
            let logged = done.map { StrengthProgression.LoggedSet(weight: $0.weight ?? 0, reps: $0.reps, completed: true) }
            guard let s = StrengthProgression.suggest(exerciseName: ex.name, prescription: ex.prescription, lastSession: logged)
            else { return nil }
            switch s.kind {
            case .increase:     return "\(ex.name): go up to \(formatPounds(s.weight)) lb next time."
            case .repeatWeight: return "\(ex.name): stay at \(formatPounds(s.weight)) lb and own every rep."
            case .deload:       return "\(ex.name): drop to \(formatPounds(s.weight)) lb and rebuild."
            }
        }
    }

    private func deleteLog() {
        if let existing = PlanWorkoutLogStore.log(for: dayKey, context: context) {
            PlanWorkoutLogStore.delete(existing, context: context)
        }
        PlanWorkoutLogStore.setDone(dayKey, false)
        onSaved()
        dismiss()
    }
}

func formatPounds(_ pounds: Double) -> String {
    pounds.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(pounds))
        : String(format: "%.1f", pounds)
}
