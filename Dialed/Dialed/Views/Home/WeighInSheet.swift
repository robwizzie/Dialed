//
//  WeighInSheet.swift
//  Dialed
//
//  Manual weigh-in for when the scale didn't sync (or you weighed in at
//  the gym). Saves a WeightEntry; the Home + Challenge screens merge it
//  with Apple Health and Fitbit readings.
//

import SwiftUI
import SwiftData

struct WeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var pounds: Double

    init(lastWeight: Double?) {
        _pounds = State(initialValue: ((lastWeight ?? UserSettings.load().currentWeight) * 10).rounded() / 10)
    }

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Neka.muted)
                .frame(width: 38, height: 4)
                .padding(.top, 10)

            VStack(spacing: 4) {
                Text("Weigh in")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Neka.ink)
                Text(Date(), format: .dateTime.weekday(.wide).hour().minute())
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", pounds))
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .contentTransition(.numericText(value: pounds))
                    .animation(.snappy(duration: 0.2), value: pounds)
                Text("lb")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
            }

            HStack(spacing: 12) {
                step("−1", -1)
                step("−0.1", -0.1)
                step("+0.1", 0.1)
                step("+1", 1)
            }

            Spacer(minLength: 0)

            Button("Save \(String(format: "%.1f", pounds)) lb") { save() }
                .buttonStyle(.nekaPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Neka.paper.ignoresSafeArea())
    }

    private func step(_ label: String, _ delta: Double) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            pounds = max(50, min(600, ((pounds + delta) * 10).rounded() / 10))
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Neka.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Neka.surface)
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
                )
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("\(delta > 0 ? "Add" : "Subtract") \(String(format: "%.1f", abs(delta))) pounds")
    }

    private func save() {
        modelContext.insert(WeightEntry(pounds: pounds))
        try? modelContext.save()

        // Keep the profile's current weight fresh so targets track you.
        var settings = UserSettings.load()
        settings.currentWeight = pounds
        settings.save()

        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}
