//
//  WakeMissionScreen.swift
//  Dialed
//
//  The full-screen mission that turns the alarm off, then "You're up".
//  Opening it silenced the alarm; any progress here keeps it quiet, and
//  stalling or leaving rings it again (WakeAlarmCoordinator). Every
//  mission reports progress so the re-ring keeps getting pushed back.
//  A test run (from settings) rings nothing, records nothing and can be
//  left at any time.
//

import SwiftUI
import SwiftData
import CoreMotion
import VisionKit
import Vision

struct WakeMissionScreen: View {
    let run: WakeAlarmCoordinator.Run
    /// Closes a test run (real runs end through the coordinator).
    var onLeaveTest: () -> Void
    @ObservedObject private var coordinator = WakeAlarmCoordinator.shared
    @State private var testPassed = false

    init(run: WakeAlarmCoordinator.Run, onLeaveTest: @escaping () -> Void = {}) {
        self.run = run
        self.onLeaveTest = onLeaveTest
    }

    private var awake: Bool { run.isTest ? testPassed : coordinator.phase == .awake }

    var body: some View {
        ZStack {
            LinearGradient(colors: awake
                           ? [Color(hex: "FFB347"), Color(hex: "FF7A59"), Color(hex: "7B5CFF")]
                           : [Color(hex: "0F1226"), Color(hex: "1E2350"), Color(hex: "3A2C6B")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: awake)

            if awake {
                YoureUpView(isTest: run.isTest, wakeCheck: run.wakeCheck) {
                    if run.isTest { onLeaveTest() } else { coordinator.finish() }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                VStack(spacing: 20) {
                    header
                    mission
                        .frame(maxHeight: .infinity)
                    if run.canSnooze {
                        Button {
                            if run.isTest { onLeaveTest() } else { coordinator.snooze() }
                        } label: {
                            Text(run.snoozeLabel + (run.isTest ? " (ends the test)" : ""))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(20)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if run.isTest && !awake {
                Button(action: onLeaveTest) {
                    Label("Leave test", systemImage: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 6) {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            if run.isTest {
                Text("TEST")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "0F1226"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: "FFB347")))
            }
            Label("\(run.mission.title) mission · \(run.tuning.summary(for: run.mission))", systemImage: run.mission.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Text(run.isTest
                 ? "Just a try-out: no alarm rings and nothing is saved. Leave whenever you like."
                 : "The alarm stays quiet while you're at it. Stop or leave and it rings again.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.top, run.isTest ? 36 : 12)
    }

    @ViewBuilder
    private var mission: some View {
        let isTest = run.isTest
        let progress: () -> Void = { if !isTest { coordinator.progress() } }
        let done: () -> Void = {
            if isTest {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { testPassed = true }
            } else {
                coordinator.complete()
            }
        }
        let t = run.tuning
        switch run.mission {
        case .math:
            MathMissionView(difficulty: t.mathDifficulty, count: t.mathProblems, seed: run.seed, onProgress: progress, onDone: done)
        case .shake:
            ShakeMissionView(target: t.shakes, onProgress: progress, onDone: done)
        case .steps:
            if CMPedometer.isStepCountingAvailable() {
                StepsMissionView(target: t.steps, onProgress: progress, onDone: done)
            } else {
                ShakeMissionView(target: t.shakes, onProgress: progress, onDone: done)
            }
        case .memory:
            MemoryMissionView(difficulty: t.memoryDifficulty, side: t.memoryGrid, tiles: t.memoryTiles,
                              rounds: t.memoryRounds, seed: run.seed, onProgress: progress, onDone: done)
        case .typing:
            TypingMissionView(phrase: MissionContent.phrase(friend: WeightChallenge.load()?.friendDisplayName,
                                                            difficulty: t.typingDifficulty, lines: t.typingLines,
                                                            seed: run.seed),
                              onProgress: progress, onDone: done)
        case .photo:
            PhotoMissionView(difficulty: t.photoDifficulty, onProgress: progress, onDone: done)
        case .barcode:
            BarcodeMissionView(expected: WakeAlarmSettings.load().barcode ?? "", onProgress: progress, onDone: done)
        }
    }
}

// MARK: - Shared pieces

/// Big progress ring with a count in the middle.
struct MissionRing: View {
    let progress: Double
    let value: String
    let caption: String

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 18)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: [Color(hex: "7CF2B0"), Color(hex: "39C3FF"), Color(hex: "7CF2B0")], center: .center),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: progress)
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(width: 230, height: 230)
    }
}

private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

private func errorHaptic() {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
}

// MARK: - Math

private struct MathMissionView: View {
    let difficulty: MissionDifficulty
    let count: Int
    let seed: UInt64
    var onProgress: () -> Void
    var onDone: () -> Void

    @State private var problems: [MissionContent.Problem] = []
    @State private var index = 0
    @State private var input = ""
    @State private var attempt: UInt64 = 0
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<max(problems.count, 1), id: \.self) { i in
                    Capsule().fill(i < index ? Color(hex: "7CF2B0") : .white.opacity(0.2))
                        .frame(height: 6)
                }
            }
            .frame(maxWidth: min(220, CGFloat(max(problems.count, 1)) * 40))
            Spacer(minLength: 0)
            if index < problems.count {
                Text(problems[index].text + " =")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                Text(input.isEmpty ? " " : input)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(wrong ? Color(hex: "FF6B6B") : Color(hex: "7CF2B0"))
                    .frame(height: 50)
                    .scaleEffect(wrong ? 1.15 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.4), value: wrong)
            }
            Spacer(minLength: 0)
            keypad
        }
        .onAppear { if problems.isEmpty { problems = MissionContent.mathProblems(difficulty, count: count, seed: seed) } }
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "✓"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(keys, id: \.self) { key in
                Button { tap(key) } label: {
                    Text(key)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(key == "✓" ? Color(hex: "0F1226") : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(key == "✓" ? Color(hex: "7CF2B0") : .white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tap(_ key: String) {
        haptic()
        onProgress()
        switch key {
        case "⌫": input = String(input.dropLast())
        case "✓": check()
        default: if input.count < 5 { input += key }
        }
    }

    private func check() {
        guard index < problems.count, let value = Int(input) else { return }
        if value == problems[index].answer {
            input = ""
            index += 1
            haptic(.medium)
            if index >= problems.count { onDone() }
        } else {
            // A miss swaps in a fresh problem: no brute-forcing half asleep.
            errorHaptic()
            wrong = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wrong = false }
            input = ""
            attempt += 1
            var fresh = problems
            fresh[index] = MissionContent.mathProblems(difficulty, count: 1, seed: seed &+ attempt &* 7919)[0]
            problems = fresh
        }
    }
}

// MARK: - Shake

private final class ShakeCounter: ObservableObject {
    @Published var count = 0
    private let manager = CMMotionManager()
    private var last = Date.distantPast

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let a = motion?.userAcceleration else { return }
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let now = Date()
            if magnitude > 1.5, now.timeIntervalSince(self.last) > 0.18 {
                self.last = now
                self.count += 1
            }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

private struct ShakeMissionView: View {
    let target: Int
    var onProgress: () -> Void
    var onDone: () -> Void
    @StateObject private var counter = ShakeCounter()
    @State private var finished = false

    var body: some View {
        VStack(spacing: 24) {
            MissionRing(progress: Double(counter.count) / Double(target),
                        value: "\(max(0, target - counter.count))", caption: "shakes to go")
            Text("Shake it like you mean it")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
        .onAppear { counter.start() }
        .onDisappear { counter.stop() }
        .onChange(of: counter.count) { _, n in
            haptic()
            onProgress()
            if n >= target, !finished { finished = true; counter.stop(); onDone() }
        }
    }
}

// MARK: - Steps

private final class StepCounter: ObservableObject {
    @Published var steps = 0
    private let pedometer = CMPedometer()

    func start() {
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let n = data?.numberOfSteps.intValue else { return }
            Task { @MainActor in self?.steps = n }
        }
    }

    func stop() { pedometer.stopUpdates() }
}

private struct StepsMissionView: View {
    let target: Int
    var onProgress: () -> Void
    var onDone: () -> Void
    @StateObject private var counter = StepCounter()
    @State private var finished = false

    var body: some View {
        VStack(spacing: 24) {
            MissionRing(progress: Double(counter.steps) / Double(target),
                        value: "\(max(0, target - counter.steps))", caption: "steps to go")
            Text("Out of bed. Walk to the kitchen and grab some water.")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .onAppear { counter.start() }
        .onDisappear { counter.stop() }
        .onChange(of: counter.steps) { _, n in
            haptic()
            onProgress()
            if n >= target, !finished { finished = true; counter.stop(); onDone() }
        }
    }
}

// MARK: - Memory

private struct MemoryMissionView: View {
    let difficulty: MissionDifficulty
    let side: Int
    let tiles: Int
    let rounds: Int
    let seed: UInt64
    var onProgress: () -> Void
    var onDone: () -> Void

    @State private var round = 0
    @State private var attempt: UInt64 = 0
    @State private var pattern: Set<Int> = []
    @State private var picked: Set<Int> = []
    @State private var showing = true
    @State private var miss: Int?

    private var setup: (side: Int, tiles: Int, rounds: Int) {
        let s = max(2, side)
        return (s, min(max(1, tiles), s * s - 1), max(1, rounds))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(showing ? "Remember the lit tiles" : "Tap them back")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text("Round \(min(round + 1, setup.rounds)) of \(setup.rounds)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            let side = setup.side
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: side), spacing: 10) {
                ForEach(0..<(side * side), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color(i))
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture { tap(i) }
                        .animation(.easeOut(duration: 0.2), value: picked)
                        .animation(.easeOut(duration: 0.2), value: showing)
                }
            }
            .frame(maxWidth: 330)
        }
        .onAppear(perform: newRound)
    }

    private func color(_ i: Int) -> Color {
        if miss == i { return Color(hex: "FF6B6B") }
        if showing && pattern.contains(i) { return Color(hex: "7CF2B0") }
        if picked.contains(i) { return Color(hex: "39C3FF") }
        return .white.opacity(0.1)
    }

    private func newRound() {
        let s = setup
        pattern = MissionContent.memoryPattern(side: s.side, count: s.tiles, seed: seed &+ UInt64(round) &* 31 &+ attempt &* 977)
        picked = []
        miss = nil
        showing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + MissionContent.memoryFlash(difficulty)) { showing = false }
    }

    private func tap(_ i: Int) {
        guard !showing, !picked.contains(i) else { return }
        onProgress()
        if pattern.contains(i) {
            haptic()
            picked.insert(i)
            if picked == pattern {
                round += 1
                if round >= setup.rounds { onDone() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { newRound() } }
            }
        } else {
            errorHaptic()
            miss = i
            attempt += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { newRound() }
        }
    }
}

// MARK: - Typing

private struct TypingMissionView: View {
    let phrase: String
    var onProgress: () -> Void
    var onDone: () -> Void
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Type it exactly")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text(phrase)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            TextField("", text: $typed, axis: .vertical)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(hex: "7CF2B0"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.1)))
            ProgressView(value: Double(commonPrefix), total: Double(max(phrase.count, 1)))
                .tint(Color(hex: "7CF2B0"))
        }
        .onAppear { focused = true }
        .onChange(of: typed) { _, text in
            onProgress()
            if MissionContent.typedMatches(text, phrase) { focused = false; onDone() }
        }
    }

    private var commonPrefix: Int {
        zip(typed.lowercased(), phrase.lowercased()).prefix { $0 == $1 }.count
    }
}

// MARK: - Photo

private struct PhotoMissionView: View {
    let difficulty: MissionDifficulty
    var onProgress: () -> Void
    var onDone: () -> Void
    @State private var capturing = false
    @State private var message: String?
    @State private var checking = false

    var body: some View {
        VStack(spacing: 20) {
            if let thumb = WakeAlarmReference.thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 2))
            }
            Text("Go to this spot and take the same photo")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "FFB347"))
            }
            Button { capturing = true; onProgress() } label: {
                Label(checking ? "Checking…" : "Take photo", systemImage: "camera.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "0F1226"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color(hex: "7CF2B0")))
            }
            .disabled(checking)
        }
        .fullScreenCover(isPresented: $capturing) {
            CameraCapture { image in
                capturing = false
                guard let image else { return }
                check(image)
            }
            .ignoresSafeArea()
        }
    }

    private func check(_ image: UIImage) {
        checking = true
        onProgress()
        Task.detached(priority: .userInitiated) {
            let distance = WakeAlarmReference.distance(to: image)
            await MainActor.run {
                checking = false
                if let distance, PhotoMatch.isMatch(distance: distance, difficulty: difficulty) {
                    onDone()
                } else {
                    errorHaptic()
                    message = "Not quite the same spot. Line it up and try again."
                }
            }
        }
    }
}

/// The system camera, for one photo.
struct CameraCapture: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
    }
}

// MARK: - Barcode

private struct BarcodeMissionView: View {
    let expected: String
    var onProgress: () -> Void
    var onDone: () -> Void
    @State private var attempt = 0
    @State private var message: String?

    static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .code39, .qr]

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan your registered barcode")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerRepresentable(symbologies: Self.symbologies) { code in
                    onProgress()
                    if code == expected {
                        onDone()
                    } else {
                        errorHaptic()
                        message = "That's a different barcode."
                        attempt += 1
                    }
                }
                .id(attempt)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                Text("This iPhone can't scan barcodes. Change the mission in Wake-up times › Alarm.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                MathMissionView(difficulty: .easy, count: 2, seed: 1, onProgress: onProgress, onDone: onDone)
            }
            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "FFB347"))
            }
        }
    }
}

// MARK: - You're up

/// After the mission: last night's sleep, today's first quest, and water.
private struct YoureUpView: View {
    var isTest = false
    var wakeCheck = false
    var onClose: () -> Void
    @Environment(\.modelContext) private var context
    @State private var score: Int?
    @State private var hours: Double?
    @State private var quest: String?
    @State private var drank = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: appeared)
            Text(isTest ? "Test passed." : "You're up.")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            if isTest {
                Text("That's what your alarm will ask for. Nothing was saved.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            } else if wakeCheck {
                Text("Quick check-in in 5 minutes. Open Dialed when it asks.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            if !isTest { morningRows }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text(isTest ? "Done" : "Let's go")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "3A2C6B"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(.white))
            }
        }
        .padding(24)
        .task { if !isTest { await load() } }
        .onAppear { appeared = true }
    }

    private var morningRows: some View {
        VStack(spacing: 12) {
            if let score {
                row(icon: "moon.zzz.fill", title: "Sleep score \(score)",
                    detail: hours.map { String(format: "%.1f h last night", $0) } ?? "Last night")
            }
            if let quest {
                row(icon: "checklist.checked", title: "First quest", detail: quest)
            }
            Button {
                QuickLogService.logWater(8, context: context)
                withAnimation { drank = true }
                haptic(.medium)
            } label: {
                row(icon: drank ? "checkmark.circle.fill" : "drop.fill",
                    title: drank ? "8 oz logged" : "Drink a glass of water",
                    detail: drank ? "Nice start." : "Tap when it's done")
            }
            .buttonStyle(.plain)
            .disabled(drank)
        }
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Text(detail).font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.15)))
    }

    private func load() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let sessions = (try? context.fetch(FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.logicalDate >= today && $0.logicalDate < tomorrow }))) ?? []
        let night = HealthInsights.combine(sessions.map { s in
            HealthInsights.Night(
                wakeDay: today, bedtime: s.startTime, wakeTime: s.endTime,
                inBedMinutes: s.inBedMinutes, asleepMinutes: s.asleepMinutes,
                deepMinutes: s.deepMinutes, remMinutes: s.remMinutes, lightMinutes: s.lightMinutes,
                awakeMinutes: s.awakeMinutes, awakenings: s.awakeningCount, vendorScore: s.vendorSleepScore,
                segments: s.stageTimeline)
        })
        score = night.map(HealthInsights.sleepScore)
        hours = night.map { Double($0.asleepMinutes) / 60 }
        quest = await GameService.today(context: context).quests.first?.quest.title
    }
}
