//
//  NoteCaptureSheet.swift
//  Dialed
//
//  Free-text note. Defaults to kind = .note for short captures, but offers
//  a "Journal" toggle for longer-form entries (changes the kind so it
//  renders distinctly on the Timeline + can be queried separately).
//

import SwiftUI
import SwiftData

struct NoteCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text: String = ""
    @State private var isJournal: Bool = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            grabber

            HStack {
                Text(isJournal ? "Journal entry" : "Quick note")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Toggle(isOn: $isJournal) {
                    Text("Journal")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
                .toggleStyle(.switch)
                .tint(AppColors.Pillar.recovery.gradient.last ?? .blue)
                .labelsHidden()
                Text("Journal")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }

            TextField(
                isJournal
                    ? "What's on your mind?"
                    : "Capture a quick thought",
                text: $text,
                axis: .vertical
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(isJournal ? 8...20 : 3...6)
            .focused($fieldFocused)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
        .onAppear { fieldFocused = true }
    }

    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.15))
            .frame(width: 38, height: 4)
            .padding(.top, 10)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: AppColors.Pillar.strain.gradient,
                            startPoint: .top, endPoint: .bottom
                        ))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let event: ContextEvent = isJournal
            ? ContextEvent.journal(trimmed)
            : ContextEvent(timestamp: Date(), kind: .note, text: trimmed)
        modelContext.insert(event)
        try? modelContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

#Preview {
    NoteCaptureSheet()
        .preferredColorScheme(.dark)
}
