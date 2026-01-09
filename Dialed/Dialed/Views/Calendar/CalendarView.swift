//
//  CalendarView.swift
//  Dialed
//
//  Calendar view with daily scores and streaks
//

import SwiftUI

struct CalendarView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Calendar View")
                    .font(.largeTitle)
                    .foregroundColor(AppColors.textPrimary)

                Text("Calendar with scores and streaks will go here")
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Calendar")
        }
    }
}

#Preview {
    CalendarView()
}
