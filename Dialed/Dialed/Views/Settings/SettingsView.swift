//
//  SettingsView.swift
//  Dialed
//
//  Settings and preferences
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Protein, water, calorie targets")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Targets")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )

                Section {
                    Text("Notification preferences")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Notifications")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )

                Section {
                    Text("HealthKit permissions")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Integrations")
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
