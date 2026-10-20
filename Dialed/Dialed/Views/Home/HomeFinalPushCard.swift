//
//  HomeFinalPushCard.swift
//  Dialed
//
//  The last 14 days of the challenge: a big countdown, today's tighter
//  calorie target, where you stand against your friend, and the "every
//  day counts" check-in (on plan yesterday? weighed in? moved?) with a
//  streak. Takes no space outside the final push.
//

import SwiftUI

struct HomeFinalPushCard: View {
    let challenge: WeightChallenge?
    let race: RacePace.Report?
    /// Today's calorie budget (the tighter target plus anything earned).
    let target: Double
    /// Your usual target, when final push has tightened it.
    var usualTarget: Double?

    @State private var checkIn = FinalPushStore.checkIn()
    @State private var streak = FinalPush.streak(FinalPushStore.checkIns)
    @State private var glow = false

    private var daysLeft: Int? {
        guard let c = challenge, FinalPush.isActive(end: c.endDate) else { return nil }
        return FinalPush.daysLeft(end: c.endDate)
    }

    var body: some View {
        if let left = daysLeft, let c = challenge {
            card(left, friend: c.friendDisplayName)
        }
    }

    private func card(_ left: Int, friend: String) -> some View {
        let phase = FinalPush.phase(daysLeft: left)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("FINAL PUSH", systemImage: "flame.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.85))
                    Text(phase.title)
                        .font(Neka.display(26, weight: .bold))
                        .foregroundColor(.white)
                    Text(phase.line)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: Double(FinalPush.windowDays - left) / Double(FinalPush.windowDays))
                        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -3) {
                        Text("\(left)")
                            .font(Neka.display(30, weight: .heavy))
                            .foregroundColor(.white)
                            .contentTransition(.numericText(value: Double(left)))
                        Text(left == 1 ? "day" : "days")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .frame(width: 78, height: 78)
                .scaleEffect(glow ? 1.04 : 1)
            }

            HStack(spacing: 10) {
                tile("Today's target", "\(Int(target).formatted())",
                     usualTarget.map { "usual \(Int($0).formatted())" } ?? "calories")
                if let r = race?.result {
                    tile("Needed pace", "\(RacePaceCard.rate(r.needed))", "lb / week")
                    tile("Vs \(friend)", statusText(r.status), r.friendProjectedLoss.map { "\(friend) → −\(String(format: "%.1f", $0))" } ?? "")
                }
            }

            checkInBlock
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Neka.orange, Neka.rose], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: Neka.rose.opacity(0.25), radius: 14, y: 6)
        .onAppear {
            reload()
            withAnimation(.easeInOut(duration: 1.4).repeatCount(3, autoreverses: true)) { glow = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: FinalPushStore.didChange)) { _ in reload() }
    }

    // MARK: - Check-in

    private var checkInBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Every day counts")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Neka.ink)
                Spacer()
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Neka.orangeText)
                }
            }
            question("On plan yesterday?", \.onPlan)
            question("Weighed in today?", \.weighedIn)
            question("Moved today?", \.moved)
            if checkIn.isComplete {
                Text(checkIn.allYes ? "Clean day. Stack another tomorrow." : "Noted. Tighten up the next one.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(checkIn.allYes ? Neka.greenText : Neka.inkSecondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))
    }

    private func question(_ text: String, _ path: WritableKeyPath<FinalPush.CheckIn, Bool?>) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Neka.ink)
            Spacer()
            chip("Yes", selected: checkIn[keyPath: path] == true, tint: Neka.green) { answer(path, true) }
            chip("No", selected: checkIn[keyPath: path] == false, tint: Neka.rose) { answer(path, false) }
        }
    }

    private func chip(_ title: String, selected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(selected ? .white : Neka.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? tint : Neka.track))
        }
        .buttonStyle(.dialedScale)
    }

    private func answer(_ path: WritableKeyPath<FinalPush.CheckIn, Bool?>, _ value: Bool) {
        var updated = checkIn
        updated[keyPath: path] = value
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { checkIn = updated }
        FinalPushStore.save(updated)
        #if os(iOS)
        if updated.allYes { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { UISelectionFeedbackGenerator().selectionChanged() }
        #endif
    }

    private func reload() {
        checkIn = FinalPushStore.checkIn()
        streak = FinalPush.streak(FinalPushStore.checkIns)
    }

    // MARK: - Pieces

    private func tile(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.16)))
    }

    private func statusText(_ s: RacePace.Status) -> String {
        switch s {
        case .ahead:   return "Ahead"
        case .onTrack: return "On track"
        case .behind:  return "Behind"
        case .unknown: return "—"
        }
    }
}
