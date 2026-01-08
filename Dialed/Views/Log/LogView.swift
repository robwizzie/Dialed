//
//  LogView.swift
//  Dialed
//
//  Food and workout logging
//

import SwiftUI

struct LogView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Log View")
                    .font(.largeTitle)
                    .foregroundColor(AppColors.textPrimary)

                Text("Food and workout logging will go here")
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Log")
        }
    }
}

#Preview {
    LogView()
}
