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
//  Or write it like a text ("1 set of 10 for 135, then 3 sets of 10 of
//  100 on the pec deck… worked out 6:15-6:45, ran a mile first"). It
//  saves as you go; Done checks the day off and adjusts the rest of the
//  week if you trained a different day's workout. Workouts your watch
//  recorded (Apple Health, Google Health) fill in the time and cardio.
//

import SwiftUI
import SwiftData

struct WorkoutLoggerView: View {
    let day: Date
    let session: WorkoutProgram.Session
    /// Watch sessions found for this day (times, runs) to start from.
    var detected: [DetectedWorkout] = []
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
    @State private var startedAt: Date?
    @State private var endedAt: Date?
    @State private var cardioKind: String?
    @State private var cardioMinutes: Double?
    @State private var cardioMiles: Double?
    @State private var known: [String] = []
    @State private var newExercise = ""
    @State private var addingExercise = false
    @State private var savedAt: Date?
    @State private var savedFingerprint = ""
    @State private var autosave: Task<Void, Never>?
    @State private var watch: [DetectedWorkout] = []
    /// PRs from the session just saved, shown before the summary.
    @State private var celebration: [StrengthMilestones.PR] = []
    @State private var pendingSummary: [String]?
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
                    whenCard
                    if isCardio {
                        cardioCard
                    } else {
                        restCard
                    }
                    ForEach($exercises) { $exercise in
                        exerciseCard($exercise)
                    }
                    if !isCardio { addExerciseCard }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { closeKeepingChanges() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(session.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        savedStatus
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: fingerprint) { _, _ in
                scheduleAutosave()
                syncLiveActivity()
            }
            .onChange(of: restEndsAt) { _, _ in syncLiveActivity() }
            .onDisappear {
                flushAutosave()
                if WorkoutLiveActivityController.isRunning { WorkoutLiveActivityController.end(liveState) }
                if hasExistingLog { onSaved() }
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
            .task { await lookForWatchWorkouts() }
            .overlay {
                if !celebration.isEmpty {
                    PRCelebrationView(prs: celebration, onDone: endCelebration)
                        .transition(.opacity)
                }
            }
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
            Label("Tell it what you did", systemImage: "text.bubble")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Neka.ink)
            TextField("Bench 135 for 10, 145 for 10, 155 for 8. Then pec deck 3 sets of 10 at 100. Worked out 6:15-6:45, ran a mile first.", text: $typed, axis: .vertical)
                .lineLimit(3...10)
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
                        Text(reading ? "Reading…" : "Add to workout")
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
                Text("Write it like a text, or 185x8x4")
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
        let names = exercises.map(\.name) + known
        let now = Calendar.current.isDateInToday(day)
            ? Date()
            : Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
        var heard = WorkoutNarrative.read(typed, known: names, now: now)
        if heard.exercises.isEmpty {
            // Gym shorthand ("bench 185x8x4, squat 225 5x5").
            let parsed = WorkoutTextParser.parse(typed, known: names)
            heard.exercises = parsed.filter { !$0.sets.isEmpty }
            if heard.cardio.isEmpty, let c = parsed.first(where: { $0.sets.isEmpty && ($0.minutes != nil || $0.miles != nil) }) {
                heard.cardio = [.init(kind: c.name, miles: c.miles, minutes: c.minutes)]
            }
        }
        if heard.exercises.isEmpty, let ai = await DialedAI.parseWorkout(typed, known: names) {
            heard.exercises = ai.filter { !$0.sets.isEmpty }.map { e in
                var e = e
                e.name = WorkoutTextParser.canonical(e.name, known: names)
                return e
            }
            if heard.cardio.isEmpty, let c = ai.first(where: { $0.sets.isEmpty && ($0.minutes != nil || $0.miles != nil) }) {
                heard.cardio = [.init(kind: c.name, miles: c.miles, minutes: c.minutes)]
            }
        }
        guard !heard.isEmpty else {
            typedResult = nil
            withAnimation { typedResult = "Couldn't read that. Try \"bench 135 for 10, 155 for 8\"." }
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { apply(heard) }
        typedResult = Self.describe(heard)
        typed = ""
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// "3 exercises · 9 sets · 6:15–6:45 · 1 mi run"
    static func describe(_ r: WorkoutNarrative.Reading) -> String {
        var parts: [String] = []
        if !r.exercises.isEmpty {
            let sets = r.exercises.reduce(0) { $0 + $1.sets.count }
            parts.append("\(r.exercises.count) exercise\(r.exercises.count == 1 ? "" : "s")")
            if sets > 0 { parts.append("\(sets) sets") }
        }
        if let start = r.start, let end = r.end {
            let f = Date.FormatStyle.dateTime.hour().minute()
            parts.append("\(start.formatted(f))–\(end.formatted(f))")
        }
        for c in r.cardio {
            if let mi = c.miles { parts.append(String(format: "%@ %.1f mi", c.kind.lowercased(), mi)) }
            else if let m = c.minutes { parts.append("\(c.kind.lowercased()) \(Int(m)) min") }
        }
        return "Added " + parts.joined(separator: " · ") + ". Saved as you go."
    }

    /// Lifting fills its rows; time and cardio fill the When card.
    private func apply(_ r: WorkoutNarrative.Reading) {
        apply(r.exercises)
        if let start = r.start, let end = r.end {
            startedAt = start
            endedAt = end
        }
        if let c = r.cardio.first {
            if isCardio {
                if let m = c.minutes { durationMinutes = m }
                if let mi = c.miles { distanceMiles = mi }
            } else {
                cardioKind = c.kind
                cardioMinutes = c.minutes ?? cardioMinutes
                cardioMiles = c.miles ?? cardioMiles
            }
            // A run before lifting with no session time: the run starts it.
            if startedAt == nil, let s = c.start { startedAt = s; endedAt = c.end }
        }
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
                // Added mid-workout ("then 155 for 8"): keep what's done.
                let kept = exercises[i].sets.filter(\.done)
                exercises[i].sets = kept + sets
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

    // MARK: - When

    /// Start / end time and any cardio done alongside the lifting.
    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("When", systemImage: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                if let start = startedAt, let end = endedAt, end > start {
                    Text("\(Int(end.timeIntervalSince(start) / 60)) min")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Neka.greenText)
                }
            }
            if startedAt != nil {
                HStack(spacing: 8) {
                    DatePicker("Start", selection: timeBinding($startedAt), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("to")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkTertiary)
                    DatePicker("End", selection: timeBinding($endedAt), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    Button { withAnimation { startedAt = nil; endedAt = nil } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Neka.inkTertiary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Neka.track))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear time")
                }
            } else {
                Button {
                    withAnimation {
                        let now = Calendar.current.isDateInToday(day) ? Date() : day.addingTimeInterval(18 * 3600)
                        endedAt = now
                        startedAt = now.addingTimeInterval(-Double(max(session.minutes, 30)) * 60)
                    }
                } label: {
                    Label("Add start and end time", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            ForEach(watch.filter { !$0.isCardio || isCardio }) { w in
                Label("\(w.source) recorded \(w.title.lowercased()) · \(w.timeText)", systemImage: "applewatch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Neka.inkTertiary)
            }

            if !isCardio {
                Divider().overlay(Neka.hairline)
                if let kind = cardioKind {
                    HStack(spacing: 8) {
                        Image(systemName: Self.cardioSymbol(kind))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.orangeText)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Neka.orangeSoft))
                        Menu {
                            ForEach(["Run", "Walk", "Bike", "Row", "Elliptical", "Stairs"], id: \.self) { k in
                                Button(k) { cardioKind = k }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(kind)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                        }
                        Spacer()
                        Button { withAnimation { cardioKind = nil; cardioMinutes = nil; cardioMiles = nil } } label: {
                            Text("Remove")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Neka.inkTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    cardioField(title: "Distance", unit: "mi", value: $cardioMiles, step: 0.25)
                    cardioField(title: "Time", unit: "min", value: $cardioMinutes, step: 5)
                    if let mi = cardioMiles, mi >= 1, ["Run", "Walk"].contains(kind) {
                        Label("Counts toward your mile today", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Neka.greenText)
                    }
                } else {
                    Menu {
                        ForEach(["Run", "Walk", "Bike", "Row", "Elliptical", "Stairs"], id: \.self) { k in
                            Button(k) { withAnimation { cardioKind = k } }
                        }
                    } label: {
                        Label("Add cardio", systemImage: "figure.run")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func timeBinding(_ value: Binding<Date?>) -> Binding<Date> {
        Binding(
            get: { value.wrappedValue ?? Date() },
            set: { picked in
                // Keep the logged day; only the clock time changes.
                let c = Calendar.current.dateComponents([.hour, .minute], from: picked)
                value.wrappedValue = Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day)
            }
        )
    }

    static func cardioSymbol(_ kind: String) -> String {
        switch kind {
        case "Walk":       return "figure.walk"
        case "Bike":       return "figure.outdoor.cycle"
        case "Row":        return "figure.rower"
        case "Elliptical": return "figure.elliptical"
        case "Stairs":     return "figure.stairs"
        default:           return "figure.run"
        }
    }

    // MARK: - Add an exercise

    private var addExerciseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if addingExercise {
                HStack(spacing: 8) {
                    TextField("Exercise name (e.g. Pec deck fly)", text: $newExercise)
                        .font(.system(size: 15))
                        .submitLabel(.done)
                        .onSubmit(addExercise)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
                    Button("Add", action: addExercise)
                        .font(.system(size: 14, weight: .semibold))
                        .disabled(newExercise.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                let suggestions = exerciseSuggestions
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { name in
                                Button { newExercise = name; addExercise() } label: {
                                    Text(name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Neka.ink)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Neka.track))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                Button { withAnimation { addingExercise = true } } label: {
                    Label("Add an exercise", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .nekaCard()
    }

    /// Your own and past exercises first, filtered by what's typed.
    private var exerciseSuggestions: [String] {
        let have = Set(exercises.map(\.name))
        let q = newExercise.lowercased().trimmingCharacters(in: .whitespaces)
        let pool = PlanWorkoutLogStore.customExercises + known + Self.commonExercises
        var seen = Set<String>()
        return pool.filter { !have.contains($0) && seen.insert($0).inserted && (q.isEmpty || $0.lowercased().contains(q)) }
            .prefix(10).map { $0 }
    }

    static let commonExercises = ["Incline bench press", "Pec deck fly", "Leg press", "Leg extension", "Leg curl",
                                  "Lateral raise", "Tricep pushdown", "Hammer curl", "Preacher curl", "Chest press machine",
                                  "Shoulder press machine", "Seated row", "Hip thrust", "Calf raise", "Pull-up", "Dip"]

    private func addExercise() {
        let typedName = newExercise.trimmingCharacters(in: .whitespaces)
        guard !typedName.isEmpty else { return }
        let name = WorkoutTextParser.canonical(typedName, known: exercises.map(\.name) + known)
        newExercise = ""
        guard !exercises.contains(where: { $0.name == name }) else { return }
        let last = PlanWorkoutLogStore.lastSession(of: name, before: day, context: context).filter(\.completed)
        let sets = last.isEmpty
            ? (0..<3).map { _ in SetDraft(weight: nil, reps: 10) }
            : last.map { SetDraft(weight: $0.weightLbs > 0 ? $0.weightLbs : nil, reps: $0.reps) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            exercises.append(ExerciseDraft(
                order: (exercises.map(\.order).max() ?? -1) + 1, name: name,
                prescriptionText: "Added", prescription: nil,
                equipment: StrengthProgression.equipment(for: name), suggestion: nil,
                lastSummary: last.isEmpty ? nil : "Last time: " + last.map { "\(formatPounds($0.weightLbs))×\($0.reps)" }.joined(separator: ", "),
                checkOnly: false, sets: sets))
            addingExercise = false
        }
        PlanWorkoutLogStore.remember([name])
    }

    // MARK: - Autosave

    @ViewBuilder
    private var savedStatus: some View {
        if let savedAt {
            Label("Saved \(savedAt.formatted(.dateTime.hour().minute()))", systemImage: "checkmark.icloud")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Neka.inkTertiary)
                .labelStyle(.titleAndIcon)
                .transition(.opacity)
        }
    }

    /// Everything that changes what would be saved.
    private var fingerprint: String {
        let sets = exercises.map { e in
            e.name + ":" + e.sets.map { "\($0.weight ?? -1)x\($0.reps)\($0.done ? "d" : "")" }.joined(separator: ",")
        }.joined(separator: "|")
        let times = [startedAt, endedAt].map { $0.map { "\(Int($0.timeIntervalSince1970))" } ?? "-" }.joined(separator: "-")
        let cardio = "\(cardioKind ?? "-")\(cardioMinutes ?? -1)\(cardioMiles ?? -1)\(durationMinutes ?? -1)\(distanceMiles ?? -1)"
        return [sets, times, cardio, notes].joined(separator: "#")
    }

    /// Something worth keeping: a finished set, a time, cardio or a note.
    private var hasContent: Bool {
        exercises.contains { $0.sets.contains(where: \.done) } || startedAt != nil || cardioKind != nil
            || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCardio
    }

    private func scheduleAutosave() {
        guard loaded, fingerprint != savedFingerprint else { return }
        autosave?.cancel()
        autosave = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            persistIfNeeded()
        }
    }

    private func flushAutosave() {
        autosave?.cancel()
        autosave = nil
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        guard loaded, fingerprint != savedFingerprint, hasContent || hasExistingLog else { return }
        persist()
        withAnimation { savedAt = Date() }
    }

    /// Nothing to lose: it's been saving all along.
    private func closeKeepingChanges() {
        flushAutosave()
        dismiss()
    }

    // MARK: - Live Activity

    /// Lock Screen / Dynamic Island: starts with your first finished set
    /// today and follows along until you close the logger.
    private func syncLiveActivity() {
        guard loaded, !isCardio, Calendar.current.isDateInToday(day) else { return }
        if WorkoutLiveActivityController.isRunning {
            WorkoutLiveActivityController.update(liveState)
        } else if exercises.contains(where: { $0.sets.contains(where: \.done) }), !liveState.isFinished {
            WorkoutLiveActivityController.start(title: session.title, state: liveState)
        }
    }

    /// The next undone set (first exercise that still has one), sets done,
    /// and the rest timer.
    private var liveState: WorkoutActivityAttributes.ContentState {
        let tracked = exercises.filter { !$0.checkOnly }
        let all = tracked.flatMap(\.sets)
        var state = WorkoutActivityAttributes.ContentState(
            exercise: nil, setNumber: 0, setCount: 0, nextWeight: nil, nextReps: 0,
            restEndsAt: restEndsAt.flatMap { $0 > Date() ? $0 : nil },
            setsDone: all.filter(\.done).count, setsTotal: all.count)
        for ex in tracked {
            guard let i = ex.sets.firstIndex(where: { !$0.done }) else { continue }
            state.exercise = ex.name
            state.setNumber = i + 1
            state.setCount = ex.sets.count
            state.nextWeight = ex.tracksWeight ? ex.sets[i].weight : nil
            state.nextReps = ex.sets[i].reps
            break
        }
        return state
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

        known = PlanWorkoutLogStore.knownExercises(context: context)
        let existing = PlanWorkoutLogStore.log(for: dayKey, context: context)
        hasExistingLog = existing != nil
        let savedSets = existing.map { PlanWorkoutLogStore.sets(for: $0.id, context: context) } ?? []
        notes = existing?.notes ?? ""
        durationMinutes = existing?.durationMinutes ?? (isCardio && session.minutes > 0 ? Double(session.minutes) : nil)
        distanceMiles = existing?.distanceMiles
        startedAt = existing?.startedAt
        endedAt = existing?.endedAt
        cardioKind = existing?.cardioKind
        cardioMinutes = existing?.cardioMinutes
        cardioMiles = existing?.cardioMiles
        watch = detected
        prefillFromWatch(hasLog: existing != nil)
        defer { savedFingerprint = fingerprint }

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
        // Exercises you added that aren't in the plan.
        let planNames = Set(session.exercises.map(\.name))
        var extraNames: [String] = []
        for s in savedSets where !planNames.contains(s.exerciseName) && !extraNames.contains(s.exerciseName) {
            extraNames.append(s.exerciseName)
        }
        for name in extraNames {
            let mine = savedSets.filter { $0.exerciseName == name }.sorted { $0.setIndex < $1.setIndex }
            exercises.append(ExerciseDraft(
                order: mine.first?.exerciseOrder ?? exercises.count, name: name,
                prescriptionText: "\(mine.count) × \(mine.map(\.reps).max() ?? 0)",
                prescription: .setsReps(sets: mine.count, reps: mine.map(\.reps).max() ?? 0, perSide: false),
                equipment: StrengthProgression.equipment(for: name), suggestion: nil, lastSummary: nil,
                checkOnly: false,
                sets: mine.map { SetDraft(weight: $0.weightLbs > 0 ? $0.weightLbs : nil, reps: $0.reps, done: $0.completed) }))
        }
    }

    /// Apple Health / Google Health sessions for this day, if the caller
    /// didn't pass them. Filling them in doesn't count as an edit.
    private func lookForWatchWorkouts() async {
        if !loaded { loadIfNeeded() }
        guard detected.isEmpty else { return }
        let found = await WorkoutDetector.workouts(on: day, context: context)
        guard !found.isEmpty else { return }
        let untouched = fingerprint == savedFingerprint
        watch = found
        prefillFromWatch(hasLog: hasExistingLog)
        if untouched { savedFingerprint = fingerprint }
    }

    /// Times and cardio from the watch, until you've saved your own.
    private func prefillFromWatch(hasLog: Bool) {
        guard !watch.isEmpty else { return }
        if startedAt == nil {
            let main = watch.first { $0.kind == .strength } ?? (isCardio ? watch.first : watch.first { !$0.isCardio })
            if let main { startedAt = main.start; endedAt = main.end }
        }
        if isCardio {
            if !hasLog, let w = watch.first(where: \.isCardio) ?? watch.first {
                durationMinutes = (w.minutes).rounded()
                if let mi = w.miles { distanceMiles = (mi * 100).rounded() / 100 }
            }
        } else if cardioKind == nil, let w = watch.first(where: \.isCardio) {
            cardioKind = WorkoutDetector.title(for: w.kind)
            cardioMinutes = w.minutes.rounded()
            cardioMiles = w.miles.map { ($0 * 100).rounded() / 100 }
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

    /// Writes the log as it stands (autosave and Done both land here).
    private func persist() {
        let date = Calendar.current.startOfDay(for: day)
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
        log.startedAt = startedAt
        log.endedAt = endedAt
        log.cardioKind = isCardio ? nil : cardioKind
        log.cardioMinutes = isCardio ? nil : cardioMinutes
        log.cardioMiles = isCardio ? nil : cardioMiles
        log.savedAt = Date()

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
        try? context.save()
        hasExistingLog = true
        savedFingerprint = fingerprint
        PlanWorkoutLogStore.remember(exercises.filter { $0.sets.contains(where: \.done) }.map(\.name))
        if hasContent { PlanWorkoutLogStore.setDone(dayKey, true) }
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    private func save() {
        autosave?.cancel()
        let notesSummary = adjustWeek()
        persist()
        PlanWorkoutLogStore.setDone(dayKey, true)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        let records = sessionPRs()
        let lines = records.map { "🏆 \($0.text)" } + notesSummary + nextTimeLines()
        guard !records.isEmpty else { return showSummary(lines) }
        // Celebrate first; the summary follows (tap skips ahead).
        pendingSummary = lines
        withAnimation { celebration = records }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if !celebration.isEmpty { endCelebration() }
        }
    }

    private func showSummary(_ lines: [String]) {
        if lines.isEmpty {
            finish()
        } else {
            summary = lines
        }
    }

    private func endCelebration() {
        withAnimation(.easeOut(duration: 0.2)) { celebration = [] }
        let lines = pendingSummary ?? []
        pendingSummary = nil
        showSummary(lines)
    }

    /// Records this session set against everything logged before this day.
    private func sessionPRs() -> [StrengthMilestones.PR] {
        let start = Calendar.current.startOfDay(for: day)
        let logID = PlanWorkoutLogStore.log(for: dayKey, context: context)?.id
        let history = PlanWorkoutLogStore.allSets(context: context)
            .filter { $0.completed && $0.workoutID != logID && $0.date < start }
            .map { StrengthMilestones.SetRecord(exercise: $0.exerciseName, date: $0.date, weight: $0.weightLbs, reps: $0.reps) }
        let session = exercises.filter(\.tracksWeight).flatMap { ex in
            ex.sets.filter(\.done).map {
                StrengthMilestones.SetRecord(exercise: ex.name, date: start, weight: $0.weight ?? 0, reps: $0.reps)
            }
        }
        return StrengthMilestones.prs(session: session, history: history)
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
        autosave?.cancel()
        savedFingerprint = fingerprint
        hasExistingLog = false
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
