//
//  ChallengeSetupSheet.swift
//  Dialed
//
//  Create or edit the weight-loss challenge: who you're up against, the
//  window, your goal and how the winner is scored.
//

import SwiftUI

struct ChallengeSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existing: WeightChallenge?

    @State private var draft: WeightChallenge
    @State private var useAutoStartWeight: Bool
    @State private var startWeight: Double
    @State private var friendStart: Double
    @State private var confirmEnd = false

    init(existing: WeightChallenge?, suggestedStartWeight: Double?) {
        self.existing = existing
        let base = existing ?? WeightChallenge.makeDefault()
        _draft = State(initialValue: base)
        _useAutoStartWeight = State(initialValue: base.startWeightOverride == nil)
        _startWeight = State(initialValue: base.startWeightOverride ?? suggestedStartWeight ?? UserSettings.load().currentWeight)
        _friendStart = State(initialValue: base.friendStartWeight ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Friend's name", text: $draft.friendName)
                        .textContentType(.name)
                } header: {
                    Text("Opponent")
                }

                Section {
                    DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $draft.endDate, in: draft.startDate.addingTimeInterval(86_400)..., displayedComponents: .date)
                    HStack {
                        Text("Length")
                        Spacer()
                        Text("\(lengthInDays) days")
                            .foregroundColor(Neka.inkSecondary)
                    }
                } header: {
                    Text("Window")
                }

                Section {
                    Stepper(value: $draft.goalLossLbs, in: 1...30, step: 0.5) {
                        HStack {
                            Text("Goal")
                            Spacer()
                            Text(String(format: "−%.1f lb", draft.goalLossLbs))
                                .foregroundColor(Neka.inkSecondary)
                        }
                    }
                    Toggle("Start weight from my scale", isOn: $useAutoStartWeight)
                    if !useAutoStartWeight {
                        weightField("My start weight", value: $startWeight)
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text(paceFooter)
                }

                Section {
                    weightField("\(draft.friendDisplayName)'s start weight", value: $friendStart)
                    Picker("Winner decided by", selection: $draft.scoring) {
                        ForEach(WeightChallenge.Scoring.allCases) { scoring in
                            Text(scoring.displayName).tag(scoring)
                        }
                    }
                } header: {
                    Text("Scoring")
                } footer: {
                    Text("Percent of body weight is fairest when you start at different weights. Leave your friend's start blank to use their first weigh-in.")
                }

                if existing != nil {
                    Section {
                        Button("End challenge", role: .destructive) { confirmEnd = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Neka.paper.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New challenge" : "Edit challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Start" : "Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("End this challenge?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End challenge", role: .destructive) {
                    WeightChallenge.clear()
                    dismiss()
                }
            } message: {
                Text("Your weigh-ins stay in Dialed and Apple Health. Only the challenge settings are removed.")
            }
        }
        .tint(Neka.ink)
        .environment(\.colorScheme, .light)
    }

    private var lengthInDays: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: draft.startDate), to: cal.startOfDay(for: draft.endDate)).day ?? 0
    }

    private var paceFooter: String {
        let weeks = max(1, Double(lengthInDays) / 7)
        let perWeek = draft.goalLossLbs / weeks
        let note = perWeek > 2 ? " That's aggressive — 1–2 lb/week is the sustainable range." : ""
        return String(format: "%.1f lb/week pace.", perWeek) + note
    }

    private func weightField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("lb", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("lb").foregroundColor(Neka.inkSecondary)
        }
    }

    private func save() {
        var c = draft
        c.startDate = Calendar.current.startOfDay(for: c.startDate)
        c.endDate = Calendar.current.startOfDay(for: c.endDate)
        if c.endDate <= c.startDate {
            c.endDate = Calendar.current.date(byAdding: .month, value: 1, to: c.startDate) ?? c.startDate.addingTimeInterval(30 * 86_400)
        }
        c.startWeightOverride = useAutoStartWeight ? nil : (startWeight > 50 ? startWeight : nil)
        c.friendStartWeight = friendStart > 50 ? friendStart : nil
        c.save()
        dismiss()
    }
}
