//
//  WaterLogSheet.swift
//  Dialed
//
//  One-tap water logging: today's total against your target (your
//  WaterH bottle's sips from Apple Health included), big + buttons, and
//  the sips you logged here with undo.
//

import SwiftUI
import SwiftData
import HealthKit

struct WaterLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var manual: [ContextEvent] = []
    @State private var bottleOz: Double = 0
    @State private var custom: Double = 20

    private let amounts: [Double] = [8, 12, 16, 24]
    private var target: Double { UserSettings.load().waterTargetOz }
    private var manualOz: Double { manual.reduce(0) { $0 + ($1.value ?? 0) } }
    private var total: Double { bottleOz + manualOz }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(total))")
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundColor(Neka.ink)
                                .contentTransition(.numericText())
                            Text("/ \(Int(target)) oz")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Neka.inkSecondary)
                        }
                        NekaProgressBar(progress: target > 0 ? min(1, total / target) : 0, tint: Neka.sky, height: 10)
                        Text(total >= target ? "Target hit. Nice." : "\(Int(target - total)) oz to go")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                        if bottleOz > 0 {
                            Label("\(Int(bottleOz)) oz from your bottle via Apple Health", systemImage: "waterbottle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Neka.inkTertiary)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(amounts, id: \.self) { oz in
                            Button { log(oz) } label: {
                                VStack(spacing: 2) {
                                    Text("+\(Int(oz))")
                                        .font(.system(size: 24, weight: .bold))
                                    Text("oz")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(Neka.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Neka.skySoft))
                            }
                            .buttonStyle(.dialedScale)
                        }
                    }

                    HStack {
                        Stepper("\(Int(custom)) oz", value: $custom, in: 1...64, step: 2)
                            .font(.system(size: 15, weight: .semibold))
                        Button("Log") { log(custom) }
                            .buttonStyle(.borderedProminent)
                            .tint(Neka.sky)
                    }
                    .padding(14)
                    .nekaCard()

                    if !manual.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Logged here today")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Neka.inkSecondary)
                            ForEach(manual.sorted { $0.timestamp > $1.timestamp }) { event in
                                HStack {
                                    Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 13))
                                        .foregroundColor(Neka.inkSecondary)
                                    Spacer()
                                    Text("\(Int(event.value ?? 0)) oz")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Neka.ink)
                                    Button {
                                        HealthWriteBack.remove(eventID: event.id)
                                        modelContext.delete(event)
                                        try? modelContext.save()
                                        reload()
                                        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Neka.inkTertiary)
                                    }
                                    .accessibilityLabel("Remove")
                                }
                            }
                        }
                        .padding(14)
                        .nekaCard()
                    }
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle("Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await loadBottle() }
            .onAppear(perform: reload)
        }
    }

    private func log(_ oz: Double) {
        let event = ContextEvent.water(oz)
        modelContext.insert(event)
        try? modelContext.save()
        HealthWriteBack.sync(event)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation { reload() }
        NotificationCenter.default.post(name: .dialedDataDidChange, object: nil)
    }

    private func reload() {
        let day = Calendar.current.logicalStartOfDay(for: Date())
        let water = ContextEvent.Kind.water.rawValue
        manual = (try? modelContext.fetch(FetchDescriptor<ContextEvent>(
            predicate: #Predicate { $0.logicalDate == day && $0.kindRaw == water }))) ?? []
    }

    private func loadBottle() async {
        let today = Calendar.current.startOfDay(for: Date())
        let sums = (try? await HealthKitManager.shared.fetchDailySums(.dietaryWater, unit: .fluidOunceUS(), days: 1)) ?? [:]
        bottleOz = sums[today] ?? 0
    }
}
