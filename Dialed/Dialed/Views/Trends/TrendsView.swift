//
//  TrendsView.swift
//  Dialed
//
//  Trends charts and red flag insights
//

import SwiftUI

struct TrendsView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Trends View")
                    .font(.largeTitle)
                    .foregroundColor(AppColors.textPrimary)

                Text("Charts and insights will go here")
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Trends")
        }
    }
}

#Preview {
    TrendsView()
}
