//
//  ManualEntrySheet.swift
//  Dialed
//
//  Manual entry sheets for water and protein tracking
//

import SwiftUI

struct WaterEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var currentAmount: Double
    let target: Double

    @State private var entryAmount: String = ""
    @FocusState private var isFocused: Bool

    private let quickAddAmounts = [8.0, 12.0, 16.0, 20.0, 24.0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Current progress
                VStack(spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("\(Int(currentAmount)) / \(Int(target)) oz")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("\(Int((currentAmount / target) * 100))% Complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Quick add buttons
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Add")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        ForEach(quickAddAmounts, id: \.self) { amount in
                            Button(action: {
                                addWater(amount)
                            }) {
                                Text("+\(Int(amount))oz")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.blue, .cyan],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                                    )
                            }
                        }
                    }
                }

                // Custom amount
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Amount")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        TextField("Amount", text: $entryAmount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                            .focused($isFocused)

                        Text("oz")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: {
                        if let amount = Double(entryAmount) {
                            addWater(amount)
                        }
                    }) {
                        Text("Add Water")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                            )
                    }
                    .disabled(entryAmount.isEmpty || Double(entryAmount) == nil)
                }

                Spacer()
            }
            .padding()
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Add Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onTapGesture {
                isFocused = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addWater(_ amount: Double) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            currentAmount += amount
        }
        entryAmount = ""
        isFocused = false

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

struct ProteinEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var currentAmount: Double
    let target: Double

    @State private var entryAmount: String = ""
    @FocusState private var isFocused: Bool

    private let quickAddAmounts = [20.0, 30.0, 40.0, 50.0]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Current progress
                VStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("\(Int(currentAmount)) / \(Int(target)) g")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("\(Int((currentAmount / target) * 100))% Complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Quick add buttons
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Add")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        ForEach(quickAddAmounts, id: \.self) { amount in
                            Button(action: {
                                addProtein(amount)
                            }) {
                                Text("+\(Int(amount))g")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.orange, .red],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                                    )
                            }
                        }
                    }
                }

                // Custom amount
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Amount")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        TextField("Amount", text: $entryAmount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                            .focused($isFocused)

                        Text("g")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: {
                        if let amount = Double(entryAmount) {
                            addProtein(amount)
                        }
                    }) {
                        Text("Add Protein")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                            )
                    }
                    .disabled(entryAmount.isEmpty || Double(entryAmount) == nil)
                }

                Spacer()
            }
            .padding()
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Add Protein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onTapGesture {
                isFocused = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addProtein(_ amount: Double) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            currentAmount += amount
        }
        entryAmount = ""
        isFocused = false

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

#Preview {
    WaterEntrySheet(currentAmount: .constant(64.0), target: 120.0)
}
