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
            GrabberHandle()

            HStack(spacing: 12) {
                Text(isJournal ? "Journal entry" : "Quick note")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: isJournal)
                Spacer()
                Toggle("Journal", isOn: $isJournal)
                    .toggleStyle(.switch)
                    .tint(AppColors.Pillar.recovery.gradient.last ?? .blue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize()
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
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.inputRadius, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.6)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isJournal)
            .accessibilityLabel(isJournal ? "Journal entry text" : "Quick note text")

            Spacer()

            Button("Save") { save() }
                .buttonStyle(.dialedPrimary(.strain))
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .accessibilityLabel(isJournal ? "Save journal entry" : "Save quick note")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(AppColors.nowBackground.ignoresSafeArea())
        .onAppear { fieldFocused = true }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let event: ContextEvent = isJournal
            ? ContextEvent.journal(trimmed)
            : ContextEvent(timestamp: Date(), kind: .note, text: trimmed, source: .manual)
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
