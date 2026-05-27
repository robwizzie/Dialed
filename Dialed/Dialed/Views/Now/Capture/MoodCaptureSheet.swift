//
//  MoodCaptureSheet.swift
//  Dialed
//
//  Quick mood check-in. 1–5 face selector + optional note. Writes a
//  ContextEvent(kind: .mood).
//

import SwiftUI
import SwiftData

struct MoodCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var rating: Int = 3
    @State private var note: String = ""
    @FocusState private var noteFocused: Bool

    // SF Symbols only — `face.smiling.inverse` doesn't exist; the
    // previous set fell back to a placeholder square on real devices.
    private let faces: [(rating: Int, icon: String, label: String)] = [
        (1, "cloud.rain.fill",   "Low"),
        (2, "cloud.fill",        "Off"),
        (3, "face.smiling",      "OK"),
        (4, "face.smiling.fill", "Good"),
        (5, "sun.max.fill",      "Great")
    ]

    var body: some View {
        VStack(spacing: 22) {
            GrabberHandle()

            Text("How are you feeling?")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach(faces, id: \.rating) { face in
                    faceButton(rating: face.rating, icon: face.icon, label: face.label)
                }
            }

            // Note field
            TextField(
                "Add a note (optional)",
                text: $note,
                axis: .vertical
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(3...6)
            .focused($noteFocused)
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.6)
                    )
            )
            .accessibilityLabel("Optional note")

            Spacer()

            Button("Save check-in") { save() }
                .buttonStyle(.dialedPrimary(.recovery))
                .accessibilityLabel("Save mood check-in with rating \(rating) of 5")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(AppColors.nowBackground.ignoresSafeArea())
    }

    private func faceButton(rating: Int, icon: String, label: String) -> some View {
        let isSelected = self.rating == rating
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.rating = rating
            }
            #if os(iOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: isSelected ? 32 : 26, weight: .regular))
                    .foregroundStyle(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(
                                colors: AppColors.Pillar.recovery.gradient,
                                startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.white.opacity(0.55))
                    )
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(
                                colors: AppColors.Pillar.recovery.gradient.map { $0.opacity(0.18) },
                                startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                            .stroke(isSelected
                                    ? (AppColors.Pillar.recovery.gradient.last ?? .white).opacity(0.45)
                                    : Color.white.opacity(0.06),
                                    lineWidth: isSelected ? 1 : 0.5)
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Rate mood \(label), \(rating) of 5")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = ContextEvent.mood(rating, note: trimmed.isEmpty ? nil : trimmed)
        modelContext.insert(event)
        try? modelContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

#Preview {
    MoodCaptureSheet()
        .preferredColorScheme(.dark)
}
