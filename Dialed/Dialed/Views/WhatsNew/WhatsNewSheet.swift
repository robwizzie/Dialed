//
//  WhatsNewSheet.swift
//  Dialed
//
//  Once-per-version sheet that tells upgrading users what's actually
//  different. Triggered by AppState.shouldShowWhatsNew when the
//  persisted lastSeenWhatsNewVersion trails WhatsNew.currentVersion.
//
//  Bump WhatsNew.currentVersion + add a new WhatsNew.Feature list to
//  reuse this sheet on the next major release.
//

import SwiftUI

/// Single source of truth for "what version's content is in this sheet."
enum WhatsNew {
    /// Bump on every release that should re-present the sheet.
    static let currentVersion: Int = 3

    static let title = "Dialed 3.0"
    static let subtitle = "A brand-new Home, built around you."

    /// Features rendered as a vertical card stack. Order matters —
    /// the biggest behavior shift goes first.
    static let features: [Feature] = [
        Feature(
            pillar: .readiness,
            icon: "person.crop.rectangle.fill",
            title: "You, on your dashboard",
            blurb: "Add a photo and Dialed lifts you off the background, then pins your live heart rate, breathing, blood oxygen and weight right onto it."
        ),
        Feature(
            pillar: .strain,
            icon: "flag.2.crossed.fill",
            title: "Weight-loss challenge",
            blurb: "Go head-to-head with a friend. Dialed tracks who's ahead, your pace vs. goal, where your trend lands on the final day, and the deficit it takes to win."
        ),
        Feature(
            pillar: .recovery,
            icon: "dot.radiowaves.left.and.right",
            title: "Watch, scale and bottle",
            blurb: "Pixel Watch data through Google Health, weigh-ins from your smart scale, and water from your smart bottle all land on Home automatically."
        ),
        Feature(
            pillar: .readiness,
            icon: "wand.and.sparkles",
            title: "Dialed Intelligence",
            blurb: "Apple Intelligence, fully on-device: a daily brief written from your real numbers, Ask Dialed chat, \"describe your meal\" calorie estimates, and trash talk for your opponent."
        ),
        Feature(
            pillar: .energy,
            icon: "sparkles",
            title: "Coach",
            blurb: "A short, ranked list of what to do next: drink to catch up, take a walk, close your protein, or step on the scale."
        ),
        Feature(
            pillar: .readiness,
            icon: "square.grid.2x2.fill",
            title: "Everything at a glance",
            blurb: "Weight, water, HRV, sleep, resting heart rate, steps, fuel and today's timeline in one phone-first layout — in light or dark mode."
        )
    ]

    struct Feature: Identifiable {
        let id = UUID()
        let pillar: AppColors.Pillar
        let icon: String
        let title: String
        let blurb: String
    }
}

struct WhatsNewSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.nowBackground.ignoresSafeArea()
            ambientBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    VStack(spacing: 14) {
                        ForEach(WhatsNew.features) { feature in
                            featureCard(feature)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 120)  // clear the CTA
            }

            ctaButton
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [AppColors.nowBackground.opacity(0), AppColors.nowBackground.opacity(0.95)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 140)
                    .allowsHitTesting(false),
                    alignment: .bottom
                )
        }
        .interactiveDismissDisabled(false)
        .onDisappear { appState.markWhatsNewSeen() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's new")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1.5)

            Text(WhatsNew.title)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            Text(WhatsNew.subtitle)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Feature card

    private func featureCard(_ feature: WhatsNew.Feature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: feature.pillar.gradient.map { $0.opacity(0.22) },
                        startPoint: .top, endPoint: .bottom
                    ))
                Image(systemName: feature.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: feature.pillar.gradient,
                        startPoint: .top, endPoint: .bottom
                    ))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(.init(feature.blurb))  // markdown — italic for emphasis
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColors.glassStroke, lineWidth: 0.5)
                )
        )
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            appState.markWhatsNewSeen()
            dismiss()
        } label: {
            Text("Let's go")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: AppColors.Pillar.readiness.gradient,
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .shadow(
                            color: AppColors.Pillar.readiness.gradient.last!.opacity(0.35),
                            radius: 18, x: 0, y: 8
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ambient

    private var ambientBackground: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(AppColors.Pillar.readiness.gradient.first!)
                    .frame(width: proxy.size.width * 1.1)
                    .blur(radius: 110)
                    .offset(x: -proxy.size.width * 0.45, y: -proxy.size.height * 0.4)
                    .opacity(0.38)

                Circle()
                    .fill(AppColors.Pillar.recovery.gradient.last!)
                    .frame(width: proxy.size.width * 0.85)
                    .blur(radius: 130)
                    .offset(x: proxy.size.width * 0.4, y: -proxy.size.height * 0.3)
                    .opacity(0.32)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    WhatsNewSheet()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
