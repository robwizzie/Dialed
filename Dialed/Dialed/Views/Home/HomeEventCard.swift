//
//  HomeEventCard.swift
//  Dialed
//
//  The big-day card (your brother's wedding). It stays out of the way
//  until the last week, then it's a look-your-best checklist. On the day
//  it just says have fun; the day after, back on it.
//

import SwiftUI

struct HomeEventCard: View {
    /// Home's weigh-ins (kept for the call site; the card no longer charts them).
    var weightReadings: [WeightReading] = []

    @State private var current = EventModeStore.current()
    @State private var checks = EventModeStore.checks()

    var body: some View {
        Group {
            if let current {
                switch current.phase {
                case .lookYourBest(let days):
                    lookYourBest(current.event, days: days)
                case .eventDay:
                    eventDay(current.event)
                case .recovery:
                    recovery(current.event)
                case .ahead, .none:
                    EmptyView()
                }
            }
        }
        .onAppear {
            // A new day may have moved the phase or cleared the list.
            current = EventModeStore.current()
            checks = EventModeStore.checks()
        }
        .onReceive(NotificationCenter.default.publisher(for: GoalEvent.didChangeNotification)) { _ in
            withAnimation { current = EventModeStore.current() }
        }
    }

    // MARK: - Header

    private func header(_ event: GoalEvent, days: Int, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(LinearGradient(colors: [Neka.lavender, Neka.rose],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 3) {
                Text(subtitle)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.lavenderText)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(days)")
                        .font(Neka.display(38, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Neka.ink)
                        .contentTransition(.numericText(value: Double(days)))
                    Text(days == 1 ? "day to go" : "days to go")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
                Text("\(event.name) · \(event.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Look your best

    private func lookYourBest(_ event: GoalEvent, days: Int) -> some View {
        let bedtime = WakeSchedule.load().bedtime(before: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let items = EventMode.checklist(daysLeft: days, bedtime: bedtime.map { $0.formatted(date: .omitted, time: .shortened) })
        let done = items.filter { checks.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 14) {
            header(event, days: days, subtitle: "LOOK-YOUR-BEST WEEK")
            HStack {
                Text("Today's list")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Spacer()
                Text("\(done)/\(items.count)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(done == items.count ? Neka.greenText : Neka.inkSecondary)
            }
            VStack(spacing: 8) {
                ForEach(items) { item in
                    checkRow(item, on: checks.contains(item.id))
                }
            }
            Text("This is about holding less water, not cutting it. Keep drinking, and keep it boring.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .nekaCard(wash: .lavender)
    }

    private func checkRow(_ item: EventMode.Item, on: Bool) -> some View {
        Button {
            EventModeStore.toggle(item.id)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { checks = EventModeStore.checks() }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(on ? Neka.green : Neka.lavenderSoft)
                    Image(systemName: on ? "checkmark" : item.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(on ? .white : Neka.lavenderText)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .strikethrough(on, color: Neka.inkTertiary)
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface.opacity(on ? 0.5 : 0.85)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The day, and the day after

    private func eventDay(_ event: GoalEvent) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Celebration()
                    .frame(height: 90)
                SuitIllustration(isWedding: EventMode.isWedding(event.name))
                    .frame(width: 62, height: 74)
            }
            Text(EventMode.eventDayTitle(event.name))
                .font(Neka.display(24, weight: .bold))
                .foregroundColor(Neka.ink)
            Text("Nothing to track today. No reminders, no budget, no quests. Dance, eat the cake, have fun.")
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .nekaCard(wash: .peach)
    }

    private func recovery(_ event: GoalEvent) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Neka.amber)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Neka.amberSoft))
            VStack(alignment: .leading, spacing: 3) {
                Text("Back on it, no guilt")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Neka.ink)
                Text("Yesterday was for celebrating. The scale will be up from salt and water; ignore it for 2–3 days. Water, protein, a walk and you're back.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .nekaCard(wash: .peach)
    }
}

// MARK: - Illustrations

/// A suit (or tux for a wedding) drawn in shapes: jacket, lapels, shirt,
/// bow tie or tie, and a pocket square.
struct SuitIllustration: View {
    var isWedding = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // Jacket
                Path { p in
                    p.move(to: CGPoint(x: w * 0.22, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.12))
                    p.addQuadCurve(to: CGPoint(x: w * 0.98, y: h * 0.32), control: CGPoint(x: w * 0.95, y: h * 0.14))
                    p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.98))
                    p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.98))
                    p.addLine(to: CGPoint(x: w * 0.02, y: h * 0.32))
                    p.addQuadCurve(to: CGPoint(x: w * 0.22, y: h * 0.12), control: CGPoint(x: w * 0.05, y: h * 0.14))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color(hex: "3A3F5C"), Color(hex: "1E2236")], startPoint: .top, endPoint: .bottom))

                // Shirt
                Path { p in
                    p.move(to: CGPoint(x: w * 0.36, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.64, y: h * 0.12))
                    p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.62))
                    p.closeSubpath()
                }
                .fill(Color.white)

                // Lapels
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Path { p in
                        let x0 = w * 0.5 + side * w * 0.14
                        p.move(to: CGPoint(x: x0, y: h * 0.12))
                        p.addLine(to: CGPoint(x: w * 0.5 + side * w * 0.02, y: h * 0.62))
                        p.addLine(to: CGPoint(x: w * 0.5 + side * w * 0.24, y: h * 0.36))
                        p.closeSubpath()
                    }
                    .fill(Color(hex: "2A2E45"))
                }

                // Bow tie (wedding) or tie
                if isWedding {
                    HStack(spacing: 0) {
                        Triangle().rotation(.degrees(90)).fill(Color(hex: "151827")).frame(width: w * 0.12, height: w * 0.1)
                        Circle().fill(Color(hex: "151827")).frame(width: w * 0.05)
                        Triangle().rotation(.degrees(-90)).fill(Color(hex: "151827")).frame(width: w * 0.12, height: w * 0.1)
                    }
                    .position(x: w * 0.5, y: h * 0.2)
                } else {
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.46, y: h * 0.16))
                        p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.16))
                        p.addLine(to: CGPoint(x: w * 0.56, y: h * 0.5))
                        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.58))
                        p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.5))
                        p.closeSubpath()
                    }
                    .fill(Neka.lavender)
                }

                // Buttons and pocket square
                VStack(spacing: h * 0.08) {
                    Circle().fill(Color.white.opacity(0.55)).frame(width: w * 0.05)
                    Circle().fill(Color.white.opacity(0.55)).frame(width: w * 0.05)
                }
                .position(x: w * 0.5, y: h * 0.76)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.68, y: h * 0.48))
                    p.addLine(to: CGPoint(x: w * 0.74, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.47))
                    p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.5))
                    p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.5))
                    p.closeSubpath()
                }
                .fill(Neka.rose)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Confetti that drifts down behind the suit on the big day (still with
/// Reduce Motion).
private struct Celebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SkyMotion.self) private var motion: SkyMotion?
    private let colors: [Color] = [Neka.rose, Neka.amber, Neka.lavender, Neka.sky, Neka.green]

    var body: some View {
        // Capped frame rate, and still while Home scrolls.
        SwiftUI.TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || (motion?.isScrolling ?? false))) { context in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                for i in 0..<28 {
                    let seed = Double(i) * 37.3
                    let x = (sin(seed) * 0.5 + 0.5) * size.width
                    let fall = (t * (12 + Double(i % 5) * 4) + seed * 3).truncatingRemainder(dividingBy: Double(size.height + 20))
                    let y = fall - 10
                    let rect = CGRect(x: x + sin(t + seed) * 6, y: y, width: 5, height: 9)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[i % colors.count].opacity(0.8)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
