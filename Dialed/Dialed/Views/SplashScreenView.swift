//
//  SplashScreenView.swift
//  Dialed
//
//  Splash screen with app icon and gradient
//

import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5

    var body: some View {
        if isActive {
            // Main app content
            ContentView()
                .environmentObject(appState)
        } else {
            // Splash screen
            ZStack {
                // Gradient background matching the app icon
                LinearGradient(
                    colors: [
                        Color(hex: "0b0a23"),   // Dark blue (top)
                        Color(hex: "73afc4")    // Light blue (bottom)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    // App Icon
                    Image("SplashIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26.4, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .scaleEffect(size)
                        .opacity(opacity)

                    // App Name
                    Text("DIALED")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .opacity(opacity)

                    // Tagline
                    Text("Track • Train • Transform")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .opacity(opacity)
                }
            }
            .onAppear {
                // Animate the splash screen
                withAnimation(.easeIn(duration: 0.8)) {
                    self.size = 1.0
                    self.opacity = 1.0
                }

                // Transition to main app after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        self.isActive = true
                    }
                }
            }
            .task {
                // Run the legacy → Dialed 2.0 migration once. Cheap no-op
                // after the first launch; failure mode is "try again next launch".
                LegacyMigrationService.runIfNeeded(context: modelContext)
            }
        }
    }
}

#Preview {
    SplashScreenView()
        .environmentObject(AppState())
}
