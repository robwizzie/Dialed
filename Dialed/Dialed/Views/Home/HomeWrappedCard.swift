//
//  HomeWrappedCard.swift
//  Dialed
//
//  "Your Dialed Wrapped is ready" on Home for the last two days of the
//  challenge and the week after it ends. Opens the story recap. Takes no
//  space the rest of the time.
//

import SwiftUI

struct HomeWrappedCard: View {
    @State private var showing = false

    /// Last 2 days of the challenge through 7 days after it ends.
    static func isShowing(_ challenge: WeightChallenge? = WeightChallenge.load(), now: Date = Date()) -> Bool {
        guard let challenge else { return false }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: challenge.endDate)
        guard let from = calendar.date(byAdding: .day, value: -2, to: end),
              let until = calendar.date(byAdding: .day, value: 7, to: end) else { return false }
        let today = calendar.startOfDay(for: now)
        return today >= from && today <= until
    }

    var body: some View {
        if Self.isShowing() {
            let ended = (WeightChallenge.load().map { Date() >= $0.endDate }) ?? false
            Button { showing = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(.white.opacity(0.2)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ended ? "YOUR CHALLENGE, WRAPPED" : "ALMOST THERE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white.opacity(0.8))
                        Text(ended ? "Your Dialed Wrapped is ready" : "Watch your Wrapped so far")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Text("Pounds, miles, PRs and the moment it turned.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [Neka.lavender, Neka.rose, Neka.amber],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            }
            .buttonStyle(.dialedScale)
            .fullScreenCover(isPresented: $showing) { WrappedView() }
        }
    }
}
