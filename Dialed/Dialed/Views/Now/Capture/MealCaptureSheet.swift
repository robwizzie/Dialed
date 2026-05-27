//
//  MealCaptureSheet.swift
//  Dialed
//
//  Quick meal log. Calories + protein + optional item list. Writes a
//  ContextEvent(kind: .meal). Heavier capture (photo + AI parsing) can
//  layer on later — this keeps the friction near zero for now.
//

import SwiftUI
import SwiftData

struct MealCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var itemsText: String = ""
    @FocusState private var focusedField: Field?

    enum Field { case calories, protein, items }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GrabberHandle()
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.Pillar.energy.gradient,
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                Text("Log a meal")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 12) {
                numberField(
                    title: "Calories",
                    placeholder: "0",
                    suffix: "kcal",
                    binding: $calories,
                    field: .calories
                )
                numberField(
                    title: "Protein",
                    placeholder: "0",
                    suffix: "g",
                    binding: $protein,
                    field: .protein
                )
                itemsField
            }

            Spacer()

            Button("Log meal") { save() }
                .buttonStyle(.dialedPrimary(.energy))
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .accessibilityLabel("Save meal entry")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(AppColors.nowBackground.ignoresSafeArea())
        .onAppear { focusedField = .calories }
    }

    private func numberField(
        title: String,
        placeholder: String,
        suffix: String,
        binding: Binding<String>,
        field: Field
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)
            TextField(placeholder, text: binding)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
                .accessibilityLabel(title)
            Text(suffix)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.6)
                )
        )
    }

    private var itemsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items (optional)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            TextField("e.g. chicken, rice, broccoli", text: $itemsText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .focused($focusedField, equals: .items)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 0.6)
                        )
                )
        }
    }

    private var canSave: Bool {
        (Double(calories) ?? 0) > 0 || (Double(protein) ?? 0) > 0
    }

    private func save() {
        let cals = Double(calories) ?? 0
        let prot = Double(protein) ?? 0
        let items = itemsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let event = ContextEvent.meal(calories: cals, protein: prot, items: items)
        modelContext.insert(event)
        try? modelContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

#Preview {
    MealCaptureSheet()
        .preferredColorScheme(.dark)
}
