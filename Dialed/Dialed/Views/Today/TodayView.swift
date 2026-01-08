//
//  TodayView.swift
//  Dialed
//
//  Main dashboard view
//

import SwiftUI

struct TodayView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Today View")
                        .font(.largeTitle)
                        .foregroundColor(AppColors.textPrimary)

                    Text("Daily score, progress bars, and checklist will go here")
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding()
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Today")
        }
    }
}

#Preview {
    TodayView()
}
