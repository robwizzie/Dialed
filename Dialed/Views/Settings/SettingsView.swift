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
                Section("Targets") {
                    Text("Protein, water, calorie targets")
                        .foregroundColor(AppColors.textSecondary)
                }

                Section("Notifications") {
                    Text("Notification preferences")
                        .foregroundColor(AppColors.textSecondary)
                }

                Section("Integrations") {
                    Text("HealthKit permissions")
                        .foregroundColor(AppColors.textSecondary)
                }
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
