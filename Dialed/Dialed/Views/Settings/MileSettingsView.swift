//
//  MileSettingsView.swift
//  Dialed
//
//  Recalibrate the daily mile: the distance goal, and the stride used to
//  turn steps into miles on days Apple Health has steps but no distance
//  (e.g. steps from the Pixel Watch). Auto learns your stride from days
//  Health has both; Manual lets you set it — or measure it on a walk.
//

import SwiftUI

struct MileSettingsView: View {
    @State private var settings = MileSettings.load()
    @State private var goal: Double
    @State private var manual: Bool
    @State private var stride: Double
    @State private var walkSteps = ""
    @State private var walkMiles = ""

    init() {
        let s = MileSettings.load()
        _goal = State(initialValue: s.goalMiles)
        _manual = State(initialValue: s.manualStepsPerMile != nil)
        _stride = State(initialValue: (s.manualStepsPerMile ?? s.learnedStepsPerMile ?? MileSettings.defaultStepsPerMile).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                goalCard
                strideCard
                if manual { measureCard }
                Text("Apple Health's walking + running distance is used whenever it's there — this only changes the step estimate and the goal.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .nekaPageBackground()
        .navigationTitle("Mile a day")
        .navigationBarTitleDisplayMode(.inline)
        // Saved on the way out, not per dial click, so Home refreshes once.
        .onDisappear(perform: save)
    }

    // MARK: - Goal

    private var goalCard: some View {
        VStack(spacing: 12) {
            header("Daily goal", "Turn the dial — walked or run, it all counts.")
            DialPicker(value: $goal, range: 0.5...5, step: 0.25, unit: "mi", format: "%.2f")
                .frame(width: 180, height: 180)
            HStack(spacing: 8) {
                ForEach([1.0, 1.5, 2, 3], id: \.self) { g in
                    Button(MileADay.format(g)) { goal = g }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(goal == g ? .white : Neka.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(goal == g ? Neka.green : Neka.track))
                        .buttonStyle(.dialedScale)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .nekaCard()
    }

    // MARK: - Stride

    private var strideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Steps per mile", "Used when Health has steps but no distance.")
            Picker("Stride", selection: $manual) {
                Text("Auto").tag(false)
                Text("Manual").tag(true)
            }
            .pickerStyle(.segmented)

            if manual {
                DialPicker(value: $stride, range: 1_500...3_000, step: 10, unit: "steps / mi")
                    .frame(width: 180, height: 180)
                    .frame(maxWidth: .infinity)
            } else if let learned = settings.learnedStepsPerMile {
                Label("\(Int(learned).formatted()) steps per mile, learned from your walks", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
            } else {
                Label("Still learning — needs 3 days where Apple Health has both your steps and distance. Using \(Int(MileSettings.defaultStepsPerMile).formatted()) until then.",
                      systemImage: "hourglass")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }
        }
        .padding(16)
        .nekaCard()
    }

    /// Walk a known distance (a track lap, a measured route), then enter
    /// the steps it took.
    private var measureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Measure it on a walk", "Walk a known distance, then enter the steps it took.")
            HStack(spacing: 10) {
                field("Steps", text: $walkSteps)
                field("Miles", text: $walkMiles)
                Button("Set") {
                    if let st = Double(walkSteps), let mi = Double(walkMiles), mi > 0 {
                        stride = min(3_000, max(1_500, (st / mi / 10).rounded() * 10))
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Neka.green))
                .buttonStyle(.dialedScale)
                .disabled(Double(walkSteps) == nil || (Double(walkMiles) ?? 0) <= 0)
            }
            Text("A standard track lap is 0.25 mi (4 laps ≈ 1 mi).")
                .font(.system(size: 12))
                .foregroundColor(Neka.inkTertiary)
        }
        .padding(16)
        .nekaCard()
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.track))
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Neka.title)
                .foregroundColor(Neka.ink)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        var s = MileSettings.load()
        s.goalMiles = goal
        s.manualStepsPerMile = manual ? stride : nil
        s.save()
        settings = s
    }
}

#Preview {
    NavigationStack { MileSettingsView() }
}
