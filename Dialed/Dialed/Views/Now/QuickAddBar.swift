//
//  QuickAddBar.swift
//  Dialed
//
//  Four-button row for the most common quick log actions. Tapping fires a
//  haptic and surfaces the right capture sheet. Designed to live just under
//  the Now/Next strip — Apple Fitness-style quick controls.
//

import SwiftUI

struct QuickAddBar: View {
    enum Action: Hashable {
        case water
        case meal
        case mood
        case note
    }

    let onTap: (Action) -> Void

    var body: some View {
        HStack(spacing: 10) {
            quickButton(
                action: .water,
                icon: "drop.fill",
                label: "Water",
                gradient: AppColors.Pillar.readiness.gradient
            )
            quickButton(
                action: .meal,
                icon: "fork.knife",
                label: "Meal",
                gradient: AppColors.Pillar.energy.gradient
            )
            quickButton(
                action: .mood,
                icon: "face.smiling.fill",
                label: "Mood",
                gradient: AppColors.Pillar.recovery.gradient
            )
            quickButton(
                action: .note,
                icon: "square.and.pencil",
                label: "Note",
                gradient: AppColors.Pillar.strain.gradient
            )
        }
    }

    private func quickButton(
        action: Action,
        icon: String,
        label: String,
        gradient: [Color]
    ) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            onTap(action)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                    )
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous)
                            .stroke(gradient.first?.opacity(0.18) ?? .clear, lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Log \(label.lowercased())")
        .accessibilityHint("Opens the \(label.lowercased()) capture sheet")
    }
}

#Preview {
    ZStack {
        AppColors.nowBackground.ignoresSafeArea()
        QuickAddBar(onTap: { _ in })
            .padding()
    }
    .preferredColorScheme(.dark)
}
