//
//  WaterCaptureSheet.swift
//  Dialed
//
//  Quick water log. Big number stepper + three preset pills (8/16/24 oz).
//  Writes a ContextEvent(kind: .water) on save.
//

import SwiftUI
import SwiftData

struct WaterCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var ounces: Double = 16
    private let presets: [Double] = [8, 16, 24]

    var body: some View {
        VStack(spacing: 22) {
            GrabberHandle()

            Image(systemName: "drop.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.Pillar.readiness.gradient,
                        startPoint: .top, endPoint: .bottom
                    )
                )

            Text("Log water")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            // Big number — content transition animates the digit changes.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(ounces))")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText(value: ounces))
                    .animation(.snappy(duration: 0.25), value: ounces)
                Text("oz")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            // +/- stepper row
            HStack(spacing: 28) {
                stepperButton(icon: "minus", label: "Decrease by 4 ounces") {
                    ounces = max(0, ounces - 4)
                }
                stepperButton(icon: "plus", label: "Increase by 4 ounces") {
                    ounces = min(128, ounces + 4)
                }
            }

            // Presets
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { preset in
                    presetPill(value: preset)
                }
            }
            .padding(.top, 4)

            Spacer()

            Button("Log \(Int(ounces)) oz") { save() }
                .buttonStyle(.dialedPrimary(.readiness))
                .disabled(ounces <= 0)
                .opacity(ounces <= 0 ? 0.5 : 1)
                .accessibilityLabel("Save \(Int(ounces)) ounces of water")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .background(AppColors.nowBackground.ignoresSafeArea())
    }

    private func stepperButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(.white.opacity(0.08))
                        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.6))
                )
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel(label)
    }

    private func presetPill(value: Double) -> some View {
        let isActive = abs(ounces - value) < 0.5
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                ounces = value
            }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
        } label: {
            Text("\(Int(value)) oz")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(isActive ? .white : .white.opacity(0.65))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isActive
                              ? AnyShapeStyle(LinearGradient(
                                  colors: AppColors.Pillar.readiness.gradient.map { $0.opacity(0.35) },
                                  startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.05)))
                )
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel("Set to \(Int(value)) ounces")
    }

    private func save() {
        let event = ContextEvent.water(ounces)
        modelContext.insert(event)
        try? modelContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

#Preview {
    WaterCaptureSheet()
        .preferredColorScheme(.dark)
}
