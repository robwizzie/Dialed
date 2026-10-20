//
//  WakeAlarmSettingsCard.swift
//  Dialed
//
//  The Alarm section of Wake-up times: turn on a real alarm for every
//  scheduled wake-up, pick the mission that turns it off (and how hard),
//  register a photo spot or a barcode, snooze and wake-up check, and a
//  test alarm that rings in ten seconds.
//

import SwiftUI
import VisionKit
import Vision

struct WakeAlarmSettingsCard: View {
    @State private var settings = WakeAlarmSettings.load()
    @State private var capturing = false
    @State private var scanning = false
    @State private var thumbnail = WakeAlarmReference.thumbnail
    @State private var photoMessage: String?
    @State private var testQueued = false
    @State private var denied = false

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
            if denied {
                Text("Alarms are off for Dialed. Turn them on in Settings › Dialed.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Neka.rose)
            }

            if settings.enabled {
                Divider().overlay(Neka.hairline)
                Text("MISSION TO TURN IT OFF")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(Neka.inkTertiary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(WakeMission.allCases) { m in
                        missionTile(m)
                    }
                }
                Text(settings.mission.blurb)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                if settings.mission == .photo { photoRow }
                if settings.mission == .barcode { barcodeRow }

                Picker("Difficulty", selection: $settings.difficulty) {
                    ForEach(MissionDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Divider().overlay(Neka.hairline)
                Picker("Snooze", selection: $settings.snoozes) {
                    Text("No snooze").tag(0)
                    Text("Once, 5 min").tag(1)
                }
                .font(.system(size: 15))
                Toggle("Wake-up check", isOn: $settings.wakeCheck)
                    .tint(Neka.green)
                    .font(.system(size: 15))
                Text("5 minutes after the mission Dialed checks you're still up. Ignore it for 2 minutes and the alarm rings again.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
                HStack {
                    Label("Sound", systemImage: "speaker.wave.3.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Neka.ink)
                    Spacer()
                    Text("System alarm")
                        .font(.system(size: 14))
                        .foregroundColor(Neka.inkSecondary)
                }

                Button(action: test) {
                    Label(testQueued ? "Rings in 10 seconds… lock your phone" : "Test the alarm", systemImage: "alarm.waves.left.and.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Neka.ink))
                }
                .buttonStyle(.dialedScale)
                .disabled(testQueued)
            }
        }
        .padding(16)
        .nekaCard()
        .animation(.easeOut(duration: 0.2), value: settings.enabled)
        .onChange(of: settings) { _, s in
            s.save()
            Task { await WakeAlarmScheduler.reschedule() }
        }
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
    }

    private func missionTile(_ m: WakeMission) -> some View {
        let selected = settings.mission == m
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.mission = m }
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
            .foregroundColor(selected ? Neka.onInk : Neka.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Neka.ink : Neka.track))
        }
        .buttonStyle(.plain)
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

    private func setEnabled(_ on: Bool) {
        if !on {
            settings.enabled = false
            return
        }
        Task {
            let ok = await WakeAlarmScheduler.requestAuthorization()
            denied = !ok
            settings.enabled = ok
        }
    }

    private func test() {
        settings.extra.append(Date().addingTimeInterval(10))
        testQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { testQueued = false }
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
