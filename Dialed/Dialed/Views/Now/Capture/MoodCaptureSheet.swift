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

    private let faces: [(rating: Int, icon: String, label: String)] = [
        (1, "face.dashed", "Low"),
        (2, "face.smiling.inverse", "Off"),
        (3, "face.smiling", "OK"),
        (4, "face.smiling.fill", "Good"),
        (5, "sun.max.fill", "Great")
    ]

    var body: some View {
        VStack(spacing: 22) {
            grabber

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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.6)
                    )
            )

            Spacer()

            saveButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(AppColors.nowBackground.ignoresSafeArea())
    }

    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.15))
            .frame(width: 38, height: 4)
            .padding(.top, 10)
    }

    private func faceButton(rating: Int, icon: String, label: String) -> some View {
        let isSelected = self.rating == rating
        return Button {
            self.rating = rating
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
                            : AnyShapeStyle(Color.white.opacity(0.45))
                    )
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(
                                colors: AppColors.Pillar.recovery.gradient.map { $0.opacity(0.18) },
                                startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.04)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected
                                    ? (AppColors.Pillar.recovery.gradient.last ?? .white).opacity(0.45)
                                    : Color.white.opacity(0.06),
                                    lineWidth: isSelected ? 1 : 0.5)
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save check-in")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: AppColors.Pillar.recovery.gradient,
                            startPoint: .top, endPoint: .bottom
                        ))
                )
        }
        .buttonStyle(.plain)
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
