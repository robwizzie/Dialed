//
//  WeeklyReportView.swift
//  Dialed
//
//  The Sunday summary: who took the week, every category side by side
//  with the winner marked, the side bet's result, where the race stands
//  and one nudge for next week. Step back through earlier weeks, send it
//  to your friend's page, or share it as an image or a text.
//

import SwiftUI
import SwiftData

struct WeeklyReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var live = ChallengeSync.shared

    @State private var weekOffset = 0
    @State private var report: WeeklyHeadToHeadReport.Report?
    @State private var loading = true
    @State private var shareImage: UIImage?
    @State private var sent: String?
    @State private var sending = false

    private var calendar: Calendar { Calendar.current }
    private var weekDate: Date { calendar.date(byAdding: .day, value: 7 * weekOffset, to: Date()) ?? Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekPicker
                    if let report {
                        // Stepping weeks: the last report stands in, redacted, until the new one lands.
                        WeeklyReportCard(report: report)
                            .nekaLoading(loading)
                        actions(report)
                            .disabled(loading)
                    } else if loading {
                        NekaLoadingPage(cards: [420, 90])
                    } else {
                        Text("No challenge yet. Set one up and your weekly report lands here every Sunday.")
                            .font(.system(size: 14))
                            .foregroundColor(Neka.inkSecondary)
                            .padding(.top, 40)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .nekaPageBackground()
            .navigationTitle("Weekly report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: weekOffset) { await load() }
        }
    }

    // MARK: - Week picker

    private var weekPicker: some View {
        let start = SideBets.weekStart(weekDate, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return HStack {
            Button { weekOffset -= 1 } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Neka.track))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? "THIS WEEK" : weekOffset == -1 ? "LAST WEEK" : "\(-weekOffset) WEEKS AGO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Neka.inkTertiary)
                Text("\(start.formatted(f)) – \(end.formatted(f))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
            Spacer()
            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Neka.track))
            }
            .disabled(weekOffset >= 0)
            .opacity(weekOffset >= 0 ? 0.35 : 1)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(Neka.ink)
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func actions(_ report: WeeklyHeadToHeadReport.Report) -> some View {
        VStack(spacing: 10) {
            if live.isLive {
                Button {
                    Task {
                        sending = true
                        let ok = await live.postReport(report)
                        sending = false
                        withAnimation { sent = ok ? "On \(report.friendName)'s page" : "The challenge server needs updating to take reports" }
                    }
                } label: {
                    HStack {
                        if sending { ProgressView() } else { Image(systemName: "paperplane.fill") }
                        Text(sent ?? "Send to \(report.friendName)'s page")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
                .disabled(sending)
            }
            HStack(spacing: 10) {
                if let shareImage {
                    ShareLink(item: Image(uiImage: shareImage),
                              preview: SharePreview(report.headline, image: Image(uiImage: shareImage))) {
                        Label("Share card", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                ShareLink(item: WeeklyHeadToHeadReport.text(report)) {
                    Label("Text it", systemImage: "message.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 14, weight: .semibold))
            .tint(Neka.ink)
            Text("Lands every Sunday at 7 PM. Your share card is an image; nothing else leaves your phone unless you send it.")
                .font(.system(size: 11))
                .foregroundColor(Neka.inkTertiary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true
        sent = nil
        let built = await WeeklyReportService.build(weekOf: weekDate, context: context)
        withAnimation(.easeOut(duration: 0.25)) {
            report = built
            loading = false
        }
        if let built {
            let renderer = ImageRenderer(content: WeeklyReportCard(report: built).frame(width: 380).padding(14)
                .background(Neka.paper))
            renderer.scale = 3
            shareImage = renderer.uiImage
        }
    }
}

// MARK: - The card

/// The report itself; also rendered as the share image.
struct WeeklyReportCard: View {
    let report: WeeklyHeadToHeadReport.Report

    private var heroColors: [Color] {
        switch report.weekWinner {
        case "you":    return [Neka.green, Color(hex: "9BE2AE")]
        case "friend": return [Neka.orange, Neka.amber]
        default:       return [Neka.lavender, Neka.sky]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero
            VStack(spacing: 0) {
                HStack {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("YOU")
                        .frame(width: 92, alignment: .trailing)
                    Text(report.friendName.uppercased())
                        .lineLimit(1)
                        .frame(width: 92, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Neka.inkTertiary)
                .padding(.bottom, 6)
                ForEach(report.rows) { row in
                    rowView(row)
                    if row.id != report.rows.last?.id { Divider().overlay(Neka.hairline) }
                }
            }
            .padding(14)
            .nekaCard()

            if let bet = report.betLine {
                Label(bet, systemImage: "dice.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [Neka.amberSoft, Neka.orangeSoft], startPoint: .leading, endPoint: .trailing)))
            }
            VStack(alignment: .leading, spacing: 6) {
                if let standing = report.standing {
                    Label(standing, systemImage: "flag.2.crossed.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                }
                Label(report.nudge, systemImage: "arrow.forward.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nekaCard()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WEEK \(report.weekNumber) · YOU VS \(report.friendName.uppercased())")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.85))
            Text(report.headline)
                .font(Neka.display(26, weight: .bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(report.subline)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: heroColors, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: report.weekWinner == "you" ? "trophy.fill" : report.weekWinner == "friend" ? "flame.fill" : "equal.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .padding(16)
        }
    }

    private func rowView(_ row: WeeklyHeadToHeadReport.Row) -> some View {
        HStack(spacing: 8) {
            Label(row.title, systemImage: row.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Neka.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            value(row.you, wins: row.winner == "you")
            value(row.friend ?? "—", wins: row.winner == "friend")
        }
        .padding(.vertical, 9)
    }

    private func value(_ text: String, wins: Bool) -> some View {
        HStack(spacing: 4) {
            if wins {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Neka.amber)
            }
            Text(text)
                .font(.system(size: 14, weight: wins ? .bold : .regular))
                .monospacedDigit()
                .foregroundColor(wins ? Neka.ink : Neka.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 92, alignment: .trailing)
    }
}
