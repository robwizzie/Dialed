//
//  MetabolismView.swift
//  Dialed
//
//  "How fast is my metabolism?" A gauge from slow to fast, your metabolic
//  age next to your real age, what you actually burn (from food + trend
//  weight) against what the formulas predict, how sure the estimate is,
//  and what protects your metabolism during a cut.
//

import SwiftUI
import SwiftData

struct MetabolismView: View {
    @Environment(\.modelContext) private var context
    @State private var report: MetabolismLoader.Report?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let report {
                    gaugeCard(report)
                    numbersCard(report)
                    if !report.result.notes.isEmpty { notesCard(report.result) }
                    howCard
                    tipsCard
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .nekaPageBackground()
        .navigationTitle("Metabolism")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let r = await MetabolismLoader.load(context: context)
        withAnimation(.easeOut(duration: 0.3)) { report = r }
    }

    // MARK: - Gauge

    private func gaugeCard(_ report: MetabolismLoader.Report) -> some View {
        let r = report.result
        return VStack(spacing: 14) {
            ZStack {
                SpeedArc(ratio: r.ratio)
                    .frame(height: 150)
                VStack(spacing: 2) {
                    Text(r.speed?.rawValue ?? "Learning")
                        .font(Neka.display(30, weight: .bold))
                        .foregroundColor(color(r.speed))
                    Text(r.ratio.map { "\(Int(($0 * 100).rounded()))% of predicted" } ?? "needs ~2 weeks of data")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
                .offset(y: 34)
            }
            Text(MetabolismEstimator.summary(r))
                .font(.system(size: 13))
                .foregroundColor(Neka.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let mAge = r.metabolicAge {
                HStack(spacing: 10) {
                    ageTile("Metabolic age", "\(Int(mAge))", tint: color(r.speed))
                    if let real = r.actualAge {
                        ageTile("Your age", "\(Int(real))", tint: Neka.ink)
                    }
                    if let delta = r.ageDelta {
                        ageTile(delta <= 0 ? "Younger by" : "Older by", "\(Int(abs(delta).rounded())) yr",
                                tint: delta <= 0 ? Neka.greenText : Neka.orangeText)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                Text("Confidence: \(r.confidence.rawValue) · \(r.loggedDays) logged days of \(r.windowDays + 1)")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Neka.inkTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .nekaCard(wash: .mint)
    }

    private func ageTile(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundColor(Neka.inkTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Neka.surface.opacity(0.8)))
    }

    private func color(_ speed: MetabolismEstimator.Speed?) -> Color {
        switch speed {
        case .fast?:    return Neka.greenText
        case .slow?:    return Neka.orangeText
        case .average?: return Neka.skyText
        case nil:       return Neka.inkSecondary
        }
    }

    // MARK: - Numbers

    private func numbersCard(_ report: MetabolismLoader.Report) -> some View {
        let r = report.result
        return VStack(alignment: .leading, spacing: 10) {
            HealthCardHeader(title: "Your numbers", trailing: "calories / day")
            row("Measured total burn", r.measuredTDEE, "Food eaten + what your trend weight lost")
            row("Measured resting burn", r.measuredRMR, "Total minus movement (Apple Health) and digestion")
            row("Formula (Mifflin-St Jeor)", r.predictedBMR.map { $0.rounded() }, "Predicted for your weight, height, age and sex")
            row("Lean-mass formula", r.leanMassBMR.map { $0.rounded() }, "From your scale's body fat (Katch-McArdle)")
            Divider().overlay(Neka.hairline)
            row("Average eaten", r.averageEaten, nil)
            row("Average active energy", r.averageActive, nil)
            if let loss = r.weeklyLoss {
                HStack {
                    Text("Trend change")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkSecondary)
                    Spacer()
                    Text((loss >= 0 ? "−" : "+") + String(format: "%.1f lb/week", abs(loss)))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Neka.ink)
                }
            }
        }
        .padding(16)
        .nekaCard()
    }

    private func row(_ title: String, _ value: Double?, _ note: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: note == nil ? .regular : .semibold))
                    .foregroundColor(note == nil ? Neka.inkSecondary : Neka.ink)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkTertiary)
                }
            }
            Spacer()
            Text(value.map { Int($0).formatted() } ?? "—")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(value == nil ? Neka.inkTertiary : Neka.ink)
        }
    }

    // MARK: - Notes, how, tips

    private func notesCard(_ r: MetabolismEstimator.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthCardHeader(title: "To sharpen the estimate")
            ForEach(r.notes, id: \.self) { note in
                Label(note, systemImage: "arrow.right.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .nekaCard()
    }

    private var howCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthCardHeader(title: "How it's worked out")
            Text("Over your last three weeks: everything you ate, plus 3,500 calories for each pound your trend weight dropped, is what your body actually burned. Take away movement (Apple Health's active energy) and about 10% for digesting food, and what's left is your resting burn.")
            Text("That's compared with the Mifflin-St Jeor formula for someone your weight, height, age and sex. 7% or more above is fast, 7% or more below is slow. Your metabolic age is the age the formula would need to predict the resting burn you actually have.")
        }
        .font(.system(size: 12))
        .foregroundColor(Neka.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .nekaCard()
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthCardHeader(title: "Keep it running hot")
            tip("dumbbell.fill", "Lift 2–4 times a week. Muscle is what keeps resting burn up while you lose fat.")
            tip("fork.knife", "Hit your protein. It protects muscle and costs more to digest than carbs or fat.")
            tip("gauge.with.needle", "Avoid crash deficits. Losing more than ~1% of body weight a week makes the body slow down to match.")
            tip("figure.walk", "Daily steps (your mile a day) move the needle more than the gym on most days.")
            tip("bed.double.fill", "Short sleep lowers burn and raises hunger. Your wake-up schedule helps.")
        }
        .padding(16)
        .nekaCard()
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Neka.greenText)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Half-circle from Slow (left) to Fast (right) with a needle at `ratio`
/// (80 % – 120 % of predicted).
private struct SpeedArc: View {
    let ratio: Double?

    private var position: Double {
        guard let ratio else { return 0.5 }
        return max(0, min(1, (ratio - 0.8) / 0.4))
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height * 2)
            let center = CGPoint(x: geo.size.width / 2, y: size / 2)
            let radius = size / 2 - 12
            ZStack {
                Arc()
                    .stroke(AngularGradient(colors: [Neka.orange, Neka.amber, Neka.sky, Neka.green, Neka.green],
                                            center: .center, startAngle: .degrees(180), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                if ratio != nil {
                    let angle = Angle.degrees(180 + 180 * position).radians
                    let tip = CGPoint(x: center.x + cos(angle) * (radius - 18), y: center.y + sin(angle) * (radius - 18))
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: tip)
                    }
                    .stroke(Neka.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: position)
                    Circle().fill(Neka.ink).frame(width: 12, height: 12).position(center)
                }
                Text("Slow").font(.system(size: 10, weight: .bold)).foregroundColor(Neka.inkTertiary)
                    .position(x: center.x - radius, y: center.y + 16)
                Text("Fast").font(.system(size: 10, weight: .bold)).foregroundColor(Neka.inkTertiary)
                    .position(x: center.x + radius, y: center.y + 16)
            }
        }
    }

    private struct Arc: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                     startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            return p
        }
    }
}

/// "How fast is your metabolism?" row that opens MetabolismView.
struct MetabolismLink: View {
    var body: some View {
        NavigationLink { MetabolismView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "flame.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Neka.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How fast is your metabolism?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("Your real burn, metabolic age, slow or fast")
                        .font(.system(size: 12))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(16)
            .nekaCard()
        }
        .buttonStyle(.dialedScale)
    }
}
