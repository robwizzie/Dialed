//
//  WakeAlarmSettingsCard.swift
//  Dialed
//
//  The Alarm section of Wake-up times: turn on a real alarm for every
//  scheduled wake-up, pick the mission that turns it off (one, random, or
//  a random mix) and tune each one, register a photo spot or a barcode,
//  snooze, wake-up check and sound. Every mission can be tried out here
//  without anything ringing, and a real test alarm can ring in a minute.
//

import SwiftUI
import VisionKit
import Vision

struct WakeAlarmSettingsCard: View {
    @State private var settings = WakeAlarmSettings.load()
    @State private var schedule = WakeSchedule.load()
    /// The mission whose options are showing.
    @State private var focused = WakeAlarmSettings.load().mission
    @State private var capturing = false
    @State private var scanning = false
    @State private var thumbnail = WakeAlarmReference.thumbnail
    @State private var photoMessage: String?
    @State private var permission: AlarmPermission = .notAsked
    @State private var testRun: WakeAlarmCoordinator.Run?
    @State private var realTestAt: Date?
    @StateObject private var preview = AlarmSoundPreview()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { settings.enabled }, set: setEnabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alarm for every wake-up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text(WakeAlarmScheduler.ringsThroughSilent
                         ? "Rings like the Clock app, even on Silent. A mission turns it off."
                         : "Before iOS 26 this is loud notifications. They can't ring through Silent mode.")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            .tint(Neka.green)
            if permission == .denied { permissionWarning }

            if settings.enabled {
                nextAlarmRow
                Divider().overlay(Neka.hairline)
                missionSection
                Divider().overlay(Neka.hairline)
                snoozeSection
                Divider().overlay(Neka.hairline)
                Toggle("Wake-up check", isOn: $settings.wakeCheck)
                    .tint(Neka.green)
                    .font(.system(size: 15))
                Text("5 minutes after the mission Dialed checks you're still up. Ignore it for 2 minutes and the alarm rings again.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                Divider().overlay(Neka.hairline)
                soundSection
                Divider().overlay(Neka.hairline)
                testSection
            }
        }
        .padding(16)
        .nekaCard()
        .animation(.easeOut(duration: 0.2), value: settings.enabled)
        .onChange(of: settings) { _, s in
            s.save()
            Task { await WakeAlarmScheduler.reschedule() }
        }
        .onChange(of: settings.sound) { _, _ in preview.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermission() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wakeScheduleDidChange)) { _ in
            schedule = WakeSchedule.load()
        }
        .task { await refreshPermission() }
        .onDisappear { preview.stop() }
        .fullScreenCover(isPresented: $capturing) {
            CameraCapture { image in
                capturing = false
                guard let image else { return }
                if WakeAlarmReference.save(image) {
                    thumbnail = WakeAlarmReference.thumbnail
                    settings.hasPhotoReference = true
                    photoMessage = nil
                } else {
                    photoMessage = "Couldn't read that photo. Try somewhere with more detail."
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $scanning) {
            BarcodeRegisterSheet { code in
                settings.barcode = code
                scanning = false
            }
        }
        .background(
            Color.clear
                .fullScreenCover(item: $testRun) { run in
                    WakeMissionScreen(run: run) { testRun = nil }
                }
        )
    }

    // MARK: - Status

    private var permissionWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Neka.rose)
            VStack(alignment: .leading, spacing: 4) {
                Text(WakeAlarmScheduler.ringsThroughSilent
                     ? "Alarms are off for Dialed, so nothing will ring."
                     : "Notifications are off for Dialed, so nothing will ring.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.roseText)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.roseSoft))
    }

    /// "Next alarm · Tue 6:30 AM · in 9 h 12 m"
    private var nextAlarmRow: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { context in
            let next = WakeAlarmPlan.fireDates(schedule: schedule, extra: settings.extra, from: context.date).first
            HStack(spacing: 10) {
                Image(systemName: next == nil ? "moon.zzz.fill" : "alarm.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.amber)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Neka.amberSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text(next == nil ? "No alarms this week" : "Next alarm")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                    if let next {
                        Text("\(next.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · \(WakeAlarmPlan.countdown(to: next, from: context.date))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    } else {
                        Text("Set a wake-up time below")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Neka.ink)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Mission

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("MISSION TO TURN IT OFF")
            Picker("Mission", selection: $settings.pickMode) {
                ForEach(MissionPickMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(pickModeCaption)
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(WakeMission.allCases) { m in
                    missionTile(m)
                }
            }
            optionsPanel(settings.pickMode == .single ? settings.mission : focused)
            Button { testRun = WakeAlarmCoordinator.Run.test(nil, settings: settings) } label: {
                Label("Try the full wake-up", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Neka.track))
            }
            .buttonStyle(.dialedScale)
        }
    }

    private var pickModeCaption: String {
        switch settings.pickMode {
        case .single:
            return "Tap a mission to use it every morning."
        case .randomAny:
            return "A different mission each morning. Photo and barcode join once registered. Tap one to tune it."
        case .randomFrom:
            return "A random pick from the ones you tick. Tap to add, tap again to remove."
        }
    }

    private func isIncluded(_ m: WakeMission) -> Bool {
        switch settings.pickMode {
        case .single:     return settings.mission == m
        case .randomAny:  return settings.canRun(m)
        case .randomFrom: return settings.randomPool.contains(m)
        }
    }

    private func tapTile(_ m: WakeMission) {
        switch settings.pickMode {
        case .single:
            settings.mission = m
        case .randomAny:
            break
        case .randomFrom:
            if !settings.randomPool.contains(m) {
                settings.randomPool.append(m)
            } else if focused == m, settings.randomPool.count > 1 {
                settings.randomPool.removeAll { $0 == m }
            }
        }
        focused = m
    }

    private func missionTile(_ m: WakeMission) -> some View {
        let included = isIncluded(m)
        let isFocused = focused == m
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tapTile(m) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: m.symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(m.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(included ? Neka.onInk : Neka.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(included ? Neka.ink : Neka.track))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Neka.green.opacity(isFocused && settings.pickMode != .single ? 1 : 0), lineWidth: 2.5))
            .overlay(alignment: .topTrailing) {
                if m.needsReference && !settings.canRun(m) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.orange)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Options

    private func optionsPanel(_ m: WakeMission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Neka.ink)
                    Text(m.blurb)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer(minLength: 8)
                Button { testRun = WakeAlarmCoordinator.Run.test(m, settings: settings) } label: {
                    Label("Try it", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Neka.onInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(settings.canRun(m) ? Neka.ink : Neka.muted))
                }
                .buttonStyle(.dialedScale)
                .disabled(!settings.canRun(m))
            }

            if m.hasDifficulty {
                Picker("Difficulty", selection: difficultyBinding(m)) {
                    ForEach(MissionDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(difficultyCaption(m))
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }

            switch m {
            case .math:
                stepperRow("Problems", value: $settings.tuning.mathProblems, in: MissionTuning.problemRange)
            case .memory:
                stepperRow("Grid", value: memoryGridBinding, in: MissionTuning.gridRange) { "\($0) × \($0)" }
                stepperRow("Squares to remember", value: $settings.tuning.memoryTiles,
                           in: MissionTuning.tileRange(grid: settings.tuning.memoryGrid))
                stepperRow("Rounds", value: $settings.tuning.memoryRounds, in: MissionTuning.roundRange)
            case .shake:
                stepperRow("Shakes", value: $settings.tuning.shakes, in: MissionTuning.shakeRange, step: 10)
            case .steps:
                stepperRow("Steps", value: $settings.tuning.steps, in: MissionTuning.stepRange, step: 10)
            case .typing:
                stepperRow("Lines to type", value: $settings.tuning.typingLines, in: MissionTuning.lineRange)
            case .photo:
                photoRow
            case .barcode:
                barcodeRow
            }

            if settings.pickMode == .randomFrom {
                Toggle("In the mix", isOn: Binding(
                    get: { settings.randomPool.contains(m) },
                    set: { on in
                        if on, !settings.randomPool.contains(m) { settings.randomPool.append(m) }
                        if !on, settings.randomPool.count > 1 { settings.randomPool.removeAll { $0 == m } }
                    }))
                    .tint(Neka.green)
                    .font(.system(size: 14))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Neka.track))
    }

    private func difficultyBinding(_ m: WakeMission) -> Binding<MissionDifficulty> {
        Binding(get: { settings.tuning.difficulty(for: m) },
                set: { settings.tuning.setDifficulty($0, for: m) })
    }

    /// Changing the grid keeps the squares inside it.
    private var memoryGridBinding: Binding<Int> {
        Binding(get: { settings.tuning.memoryGrid },
                set: { grid in
                    settings.tuning.memoryGrid = grid
                    let range = MissionTuning.tileRange(grid: grid)
                    settings.tuning.memoryTiles = min(max(settings.tuning.memoryTiles, range.lowerBound), range.upperBound)
                })
    }

    private func difficultyCaption(_ m: WakeMission) -> String {
        let d = settings.tuning.difficulty(for: m)
        switch m {
        case .math:
            switch d {
            case .easy:   return "Two-digit addition, like 34 + 27."
            case .normal: return "Multiply and add, like 7 × 9 + 23."
            case .hard:   return "Bigger numbers, like 27 × 8 + 64."
            }
        case .memory:
            return "The pattern shows for \(String(format: "%.1f", MissionContent.memoryFlash(d))) s. Picking a level also resets the grid below."
        case .shake, .steps:
            return "Picking a level sets the count. Fine-tune it below."
        case .typing:
            switch d {
            case .easy:   return "Short lines."
            case .normal: return "Short or long lines."
            case .hard:   return "Long lines only."
            }
        case .photo:
            return "How closely your photo has to match the spot."
        case .barcode:
            return ""
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
                            format: @escaping (Int) -> String = { "\($0)" }) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(Neka.ink)
                Spacer(minLength: 8)
                Text(format(value.wrappedValue))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Neka.inkSecondary)
            }
        }
    }

    private var photoRow: some View {
        HStack(spacing: 12) {
            if let thumbnail, settings.hasPhotoReference {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.hasPhotoReference ? "Spot registered" : "Register a spot")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(photoMessage ?? "Pick somewhere out of bed: the bathroom sink, the coffee maker.")
                    .font(.system(size: 11))
                    .foregroundColor(photoMessage == nil ? Neka.inkSecondary : Neka.rose)
            }
            Spacer(minLength: 0)
            Button(settings.hasPhotoReference ? "Retake" : "Take photo") { capturing = true }
                .font(.system(size: 13, weight: .semibold))
        }
    }

    private var barcodeRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.barcode == nil ? "Register a barcode" : "Barcode registered")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text(settings.barcode.map { "Code \($0)" } ?? "Scan something in another room, like your toothpaste.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkSecondary)
            }
            Spacer(minLength: 0)
            Button(settings.barcode == nil ? "Scan" : "Rescan") { scanning = true }
                .font(.system(size: 13, weight: .semibold))
        }
    }

    // MARK: - Snooze

    private var snoozeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Snooze", isOn: $settings.snoozeEnabled)
                .tint(Neka.green)
                .font(.system(size: 15))
            if settings.snoozeEnabled {
                stepperRow("Length", value: $settings.snoozeMinutes, in: WakeAlarmSettings.snoozeMinuteRange) { "\($0) min" }
                HStack {
                    Text("Snoozes per alarm")
                        .font(.system(size: 14))
                        .foregroundColor(Neka.ink)
                    Spacer()
                    Picker("Snoozes per alarm", selection: snoozeCountBinding) {
                        ForEach(snoozeCountOptions, id: \.self) { n in
                            Text(n == 0 ? "Unlimited" : "\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Neka.inkSecondary)
                }
                Toggle("Each snooze makes it harder", isOn: $settings.snoozeHarder)
                    .tint(Neka.green)
                    .font(.system(size: 14))
                Text("After each snooze the mission goes up a level and adds a bit more to do.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            } else {
                Text("No snooze: the mission is the only way out.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
    }

    /// 0 = unlimited.
    private var snoozeCountBinding: Binding<Int> {
        Binding(get: { settings.snoozeUnlimited ? 0 : settings.snoozes },
                set: { n in
                    settings.snoozeUnlimited = n == 0
                    if n > 0 { settings.snoozes = n }
                })
    }

    private var snoozeCountOptions: [Int] {
        Array(Set([1, 2, 3, 5, 10, settings.snoozes])).sorted() + [0]
    }

    // MARK: - Sound

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Sound", systemImage: "speaker.wave.3.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Neka.ink)
                Spacer()
                Picker("Sound", selection: $settings.sound) {
                    ForEach(AlarmSound.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Neka.inkSecondary)
                Button { preview.toggle(settings.sound, ramp: settings.soundRamp) } label: {
                    Image(systemName: preview.playing == settings.sound ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(settings.sound.isCustom ? Neka.onInk : Neka.inkTertiary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(settings.sound.isCustom ? Neka.ink : Neka.track))
                }
                .buttonStyle(.plain)
                .disabled(!settings.sound.isCustom)
            }
            if settings.sound.isCustom {
                Toggle("Gentle start", isOn: $settings.soundRamp)
                    .tint(Neka.green)
                    .font(.system(size: 14))
                Text("Starts soft and builds to full volume over 20 seconds.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            } else {
                Text("The standard alarm tone. Pick one of Dialed's sounds to preview it or have it fade in.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
            if !WakeAlarmScheduler.ringsThroughSilent {
                Text("As notifications, sounds play for up to 30 seconds at your ringer volume.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
    }

    // MARK: - Real test

    private var testSection: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let pending = realTestAt.map { $0 > context.date } ?? false
            VStack(alignment: .leading, spacing: 6) {
                Button(action: ringRealTest) {
                    Label(pending
                          ? "Real alarm in \(max(0, Int((realTestAt ?? context.date).timeIntervalSince(context.date)))) s… lock your phone"
                          : "Ring a real test alarm in 1 minute",
                          systemImage: "alarm.waves.left.and.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .disabled(pending)
                Text("This one really rings and needs its mission, just like a morning. Use Try it above to practise quietly.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
        }
    }

    // MARK: - Actions

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundColor(Neka.inkTertiary)
    }

    private func refreshPermission() async {
        permission = await WakeAlarmScheduler.permission()
    }

    private func setEnabled(_ on: Bool) {
        if !on {
            settings.enabled = false
            return
        }
        Task {
            let ok = await WakeAlarmScheduler.requestAuthorization()
            await refreshPermission()
            if !ok { permission = .denied }
            settings.enabled = ok
        }
    }

    private func ringRealTest() {
        let at = Date().addingTimeInterval(60)
        settings.extra.append(at)
        realTestAt = at
    }
}

/// Scan the barcode the barcode mission will ask for.
private struct BarcodeRegisterSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .qr]) { code in
                        onCode(code)
                    }
                    .ignoresSafeArea()
                } else {
                    Text("This iPhone can't scan barcodes.")
                        .foregroundColor(Neka.inkSecondary)
                }
            }
            .navigationTitle("Scan a barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
