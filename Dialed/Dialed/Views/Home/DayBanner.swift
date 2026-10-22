//
//  DayBanner.swift
//  Dialed
//
//  The top of Home, every day. The card is the sky the day has earned,
//  in the light of the hour:
//
//    · Morning (4 AM–noon): last night's sleep score, the night in one
//      frosted row, and a line worth knowing.
//    · Afternoon and evening: your Dialed score so far, with how water,
//      protein, food and the mile are going.
//    · Night: the day's score and tonight's bedtime.
//    · A past day: that day's final Dialed score sets the weather, with
//      the night before and how the day went.
//
//  The score is also a dial in the sky (the sun, or tonight's moon, is
//  its knob). Below the score: the real weather and what to wear for it
//  (tomorrow's, at night). It always shows (no dismissing) and follows
//  the clock, so it changes through the day.
//

import SwiftUI

// MARK: - Model

/// Everything the banner shows, resolved up front so the view stays dumb.
struct DayBannerModel {
    struct Chip: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let value: String
        var action: (() -> Void)? = nil
    }

    struct Meter: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let progress: Double
        let text: String
    }

    var time: DaySky.Time
    var tier: SleepVisuals.MorningTier
    var eyebrow: String
    var eyebrowIcon: String
    var score: Int?
    var scoreLabel: String = ""
    var scoreCaption: String = ""
    var verdict: String = ""
    /// The night in one frosted row (morning, past days).
    var night: HealthInsights.Night?
    var nightCaption: String?
    /// The day's pieces as small meters (afternoon, evening).
    var meters: [Meter] = []
    /// Tonight's plan (night).
    var tonight: String?
    var weather: WeatherInfo?
    var line: (icon: String, text: String)?
    var chips: [Chip] = []
    /// Shown when there's no score to give.
    var emptyNote: String?
    var isLoading = false
}

/// The real weather row: now, the day ahead, and what to wear.
struct WeatherInfo {
    enum Kind { case forecast, offer, loading }

    var kind: Kind
    var title: String? = nil
    var symbol = "cloud.sun.fill"
    var temp = ""
    var condition = ""
    var detail = ""
    var outfit: Weather.Outfit?
    var onEnable: (() -> Void)? = nil

    static func offer(_ action: @escaping () -> Void) -> WeatherInfo {
        WeatherInfo(kind: .offer, onEnable: action)
    }

    static let loading = WeatherInfo(kind: .loading, temp: "58°", condition: "Partly cloudy",
                                     detail: "H 71° · L 52° · Up to 71° by 3 PM",
                                     outfit: Weather.Outfit(main: "Short sleeve & shorts", extras: ["Light layer"], emoji: "👕"))
}

// MARK: - View

struct HomeDayBanner: View {
    let model: DayBannerModel
    var onOpen: (() -> Void)? = nil

    @State private var shownScore: Double = 0
    @Environment(\.colorScheme) private var scheme

    /// Text sits right on the sky: deep ink on a daytime sky, white at night.
    private var ink: Color {
        scheme == .dark || model.time == .night ? .white : Color(hex: "16202E")
    }

    /// Frosted rows and chips. A flat translucent fill rather than a blur
    /// material: the sky animates, and a material would re-blur it every
    /// frame (and every scroll frame).
    private var frost: Color {
        scheme == .dark ? Color(hex: "1E2125").opacity(0.62) : Color.white.opacity(0.62)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                eyebrow
                hero
                detail
            }
            .nekaLoading(model.isLoading)
            if let weather = model.weather { weatherRow(weather) }
            if let line = model.line { lineView(line).nekaLoading(model.isLoading) }
            if !model.chips.isEmpty { chips.nekaLoading(model.isLoading) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { DaySky(tier: model.tier, time: model.time, score: model.isLoading ? nil : model.score.map { Double($0) / 100 }) }
        .clipShape(RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .stroke(.white.opacity(scheme == .dark ? 0.08 : 0.5), lineWidth: 0.5)
        )
        .background(
            // Shadow on a plain shape, not the whole card, so it's cheap to draw.
            RoundedRectangle(cornerRadius: Neka.cardRadius, style: .continuous)
                .fill(Neka.surface)
                .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 16, y: 8)
        )
        .animation(.easeInOut(duration: 0.5), value: model.tier)
        .animation(.easeInOut(duration: 0.5), value: model.time)
        .onAppear { animateScore() }
        .onChange(of: model.score) { _, _ in animateScore() }
    }

    private func animateScore() {
        guard let score = model.score, !model.isLoading else { return }
        withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.15)) {
            shownScore = Double(score)
        }
    }

    // MARK: Pieces

    private var eyebrow: some View {
        Label(model.eyebrow, systemImage: model.eyebrowIcon)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundColor(ink.opacity(0.75))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }

    @ViewBuilder
    private var hero: some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            if let score = model.score {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(model.isLoading ? score : Int(shownScore.rounded()))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(ink)
                        .contentTransition(.numericText(value: shownScore))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.scoreLabel.uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                            .foregroundColor(ink)
                        Text(model.scoreCaption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ink.opacity(0.7))
                    }
                }
                Text(model.verdict)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 24)
            } else if let note = model.emptyNote {
                Text(note)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 90)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let onOpen {
            Button(action: onOpen) { content.contentShape(Rectangle()) }
                .buttonStyle(.dialedScale)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.score.map { "\(model.scoreCaption) \($0), \(model.scoreLabel). \(model.verdict)" } ?? (model.emptyNote ?? ""))
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let night = model.night {
            sleepRow(night)
        } else if !model.meters.isEmpty {
            metersRow
        } else if let tonight = model.tonight {
            HStack(spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.lavenderText)
                Text(tonight)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(frost, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// Hours, bed → wake and the stage mix on one frosted row.
    private func sleepRow(_ night: HealthInsights.Night) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.lavenderText)
                Text(Self.duration(night.asleepMinutes))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Neka.ink)
                Text("\(night.bedtime.formatted(date: .omitted, time: .shortened)) – \(night.wakeTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Neka.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let caption = model.nightCaption {
                    Text(caption)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Neka.inkTertiary)
                        .lineLimit(1)
                }
            }
            stageBar(night)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(frost, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Deep / REM / light / awake as one slim bar, drawn as one shape pass.
    @ViewBuilder
    private func stageBar(_ n: HealthInsights.Night) -> some View {
        let parts: [(Int, Color, String)] = [
            (n.deepMinutes ?? 0, Neka.lavender, "Deep"),
            (n.remMinutes ?? 0, Neka.sky, "REM"),
            (n.lightMinutes ?? 0, Neka.blue.opacity(0.45), "Light"),
            (n.awakeMinutes ?? 0, Neka.orange.opacity(0.7), "Awake")
        ]
        let total = parts.reduce(0) { $0 + $1.0 }
        if total > 0 {
            HStack(spacing: 10) {
                Canvas { ctx, size in
                    let shown = parts.filter { $0.0 > 0 }
                    let gaps = CGFloat(max(0, shown.count - 1)) * 2
                    var x: CGFloat = 0
                    for p in shown {
                        let w = max(3, (size.width - gaps) * CGFloat(p.0) / CGFloat(total))
                        ctx.fill(Path(roundedRect: CGRect(x: x, y: 0, width: w, height: size.height), cornerRadius: size.height / 2),
                                 with: .color(p.1))
                        x += w + 2
                    }
                }
                .frame(height: 4)
                ForEach(Array(parts.prefix(2).enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 3) {
                        Circle().fill(p.1).frame(width: 5, height: 5)
                        Text("\(p.2) \(Self.duration(p.0))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                            .fixedSize()
                    }
                }
            }
        }
    }

    /// Water · protein · food · mile as four small meters.
    private var metersRow: some View {
        HStack(spacing: 10) {
            ForEach(model.meters) { m in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: m.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(m.tint)
                        Text(m.text)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Neka.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    NekaProgressBar(progress: m.progress, tint: m.tint, height: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(frost, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func weatherRow(_ w: WeatherInfo) -> some View {
        switch w.kind {
        case .offer:
            HStack(spacing: 10) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Weather & what to wear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    Text("Uses your approximate location")
                        .font(.system(size: 11))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer(minLength: 0)
                if let action = w.onEnable {
                    Button(action: action) {
                        Text("Turn on")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.onInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Neka.ink))
                    }
                    .buttonStyle(.dialedScale)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(frost, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .forecast, .loading:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 22))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let title = w.title {
                                Text(title.uppercased())
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundColor(Neka.inkTertiary)
                            }
                            Text(w.temp)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(Neka.ink)
                                .monospacedDigit()
                            Text(w.condition)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Neka.inkSecondary)
                                .lineLimit(1)
                        }
                        Text(w.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Neka.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                }
                if let outfit = w.outfit {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(outfit.emoji)
                            .font(.system(size: 14))
                            .frame(width: 28)
                        (Text(outfit.main).font(.system(size: 13, weight: .semibold)).foregroundColor(Neka.ink)
                         + Text(outfit.extras.isEmpty ? "" : " · " + outfit.extras.joined(separator: " · "))
                            .font(.system(size: 12, weight: .medium)).foregroundColor(Neka.inkSecondary))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(frost, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .nekaLoading(w.kind == .loading)
            .accessibilityElement(children: .combine)
        }
    }

    private func lineView(_ line: (icon: String, text: String)) -> some View {
        Label(line.text, systemImage: line.icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Neka.ink)
            .labelStyle(.titleAndIcon)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(frost, in: Capsule())
    }

    /// Everything worth a glance, as one row of frosted chips.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.chips) { chip in
                    if let action = chip.action {
                        Button(action: action) { chipView(chip) }.buttonStyle(.dialedScale)
                    } else {
                        chipView(chip)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chipView(_ chip: DayBannerModel.Chip) -> some View {
        HStack(spacing: 8) {
            Image(systemName: chip.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(chip.tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(chip.tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(chip.title.uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(Neka.inkTertiary)
                    .lineLimit(1)
                Text(chip.value)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(frost, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Building the model

extension DayBannerModel {

    /// The Dialed score's word, in the banner's caps.
    static func label(dialed score: Int) -> String {
        switch score {
        case 85...:   return "Dialed in"
        case 70..<85: return "On track"
        case 50..<70: return "Halfway"
        default:      return "Off day"
        }
    }

    static func time(at now: Date, calendar: Calendar = .current) -> DaySky.Time {
        switch calendar.component(.hour, from: now) {
        case 4..<12:  return .morning
        case 12..<17: return .midday
        case 17..<21: return .evening
        default:      return .night
        }
    }

    struct TodayInputs {
        var night: HealthInsights.Night?
        var recentNights: [HealthInsights.Night]
        var readiness: Int?
        var weightReadings: [WeightReading]
        var mileStreak: Int
        var progress: WeightChallengeEngine.Progress?
        var friendName: String?
        var goalEvent: GoalEvent?
        var waterOz: Double
        var waterTarget: Double
        var protein: Double
        var proteinTarget: Double
        var calories: Double
        var calorieBudget: Double
        var miles: Double
        var mileGoal: Double
        var forecast: Weather.Forecast?
        var weatherStatus: WeatherService.Status
        var onEnableWeather: () -> Void
        var onWeighIn: () -> Void
    }

    /// Today, as of `now`: the sky changes with the hour, the weather with
    /// last night's sleep (your energy for the day).
    static func today(_ i: TodayInputs, now: Date = Date(), isLoading: Bool, calendar: Calendar = .current) -> DayBannerModel {
        let time = time(at: now, calendar: calendar)
        let sleepScore = i.night.map(HealthInsights.sleepScore)
        let tier = SleepVisuals.MorningTier(score: sleepScore ?? 72)
        let date = now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let dialed = DialedScore.compute(waterOz: i.waterOz, waterTargetOz: i.waterTarget, protein: i.protein,
                                         proteinTarget: i.proteinTarget, calories: i.calories,
                                         calorieTarget: i.calorieBudget, miles: i.miles)

        var m: DayBannerModel
        switch time {
        case .morning:
            m = DayBannerModel(time: .morning, tier: tier,
                               eyebrow: "Good morning · \(date)", eyebrowIcon: "sunrise.fill")
            if let night = i.night, let score = sleepScore {
                m.score = score
                m.scoreLabel = HealthInsights.label(for: score)
                m.scoreCaption = "sleep score"
                m.verdict = tier.verdict(weekDelta: weekDelta(score, i.recentNights))
                m.night = night
                m.line = funLine(i, score: score, calendar: calendar)
            } else {
                m.emptyNote = "No sleep from last night yet. Wear your watch to bed and tomorrow's sky shows how you slept."
            }
        case .midday, .evening:
            m = DayBannerModel(time: time, tier: tier,
                               eyebrow: "\(time == .midday ? "Good afternoon" : "Good evening") · \(date)",
                               eyebrowIcon: time == .midday ? "sun.max.fill" : "sun.horizon.fill")
            m.score = dialed
            m.scoreLabel = label(dialed: dialed)
            m.scoreCaption = "Dialed so far"
            m.verdict = paceVerdict(i, score: dialed, now: now, calendar: calendar)
            m.meters = meters(i)
        case .night:
            m = DayBannerModel(time: .night, tier: tier,
                               eyebrow: "Winding down · \(date)", eyebrowIcon: "moon.stars.fill")
            m.score = dialed
            m.scoreLabel = label(dialed: dialed)
            m.scoreCaption = "today's score"
            m.verdict = DayRecapContent.verdict(dialed)
            m.tonight = tonightLine(now: now, calendar: calendar)
            if m.tonight == nil { m.meters = meters(i) }
        }
        m.weather = weatherToday(i, night: time == .night, now: now, calendar: calendar)
        m.chips = todayChips(i, now: now, calendar: calendar)
        m.isLoading = isLoading
        if isLoading, m.score == nil, m.emptyNote != nil {
            // Placeholder shapes while last night is still coming in.
            m.emptyNote = nil
            m.score = 88
            m.scoreLabel = "Loading"
            m.scoreCaption = "sleep score"
            m.verdict = "Pulling last night together."
        }
        return m
    }

    /// A past day: its final Dialed score sets the weather, the sun sits as
    /// high as the score, and the night before rides along.
    static func past(_ day: DayRecapStore.Day?, date: Date, weather: Weather.Forecast? = nil,
                     calendar: Calendar = .current) -> DayBannerModel {
        let ready = day.map { $0.loaded.contains(.health) || $0.failed.contains(.health) } ?? false
        let score: Int? = day.map { d in
            DialedScore.compute(waterOz: d.waterOz, waterTargetOz: d.waterTarget, protein: d.protein,
                                proteinTarget: d.proteinTarget, calories: d.calories,
                                calorieTarget: d.calorieTarget + (d.earned?.earned ?? 0), miles: d.miles)
        }
        let shown = score ?? 72
        let label = DayNavigation.label(date)
        var m = DayBannerModel(time: .midday, tier: SleepVisuals.MorningTier(score: shown),
                               eyebrow: label == "Yesterday" ? "Yesterday · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))" : label,
                               eyebrowIcon: "calendar")
        m.score = shown
        m.scoreLabel = DayBannerModel.label(dialed: shown)
        m.scoreCaption = "Dialed score"
        m.verdict = ready ? DayRecapContent.verdict(shown) : "Pulling that day together."
        if let night = day?.night {
            m.night = night
            m.nightCaption = "Sleep \(HealthInsights.sleepScore(night))"
        }
        if let weather, let d = weather.day(date, calendar: calendar) {
            let c = Weather.condition(d.code)
            m.weather = WeatherInfo(kind: .forecast, title: "That day", symbol: c.symbol,
                                    temp: "\(Int(d.high.rounded()))°", condition: c.text,
                                    detail: "High \(Int(d.high.rounded()))° · low \(Int(d.low.rounded()))°"
                                        + (d.precipChance >= 30 ? " · \(d.precipChance)% rain" : ""))
        }
        m.chips = pastChips(day)
        m.isLoading = !ready
        return m
    }

    // MARK: Pieces

    /// Now and the rest of today, or tomorrow's once it's night.
    private static func weatherToday(_ i: TodayInputs, night: Bool, now: Date, calendar: Calendar) -> WeatherInfo? {
        guard let f = i.forecast else {
            switch i.weatherStatus {
            case .off:     return .offer(i.onEnableWeather)
            case .loading: return .loading
            default:       return nil
            }
        }
        if night {
            let morning = calendar.component(.hour, from: now) < 4 ? now : calendar.date(byAdding: .day, value: 1, to: now) ?? now
            guard let d = f.day(morning, calendar: calendar) else { return nil }
            let c = Weather.condition(d.code)
            let hours = Weather.outHours(f, on: calendar.startOfDay(for: morning), now: now, calendar: calendar)
            return WeatherInfo(kind: .forecast, title: "Tomorrow", symbol: c.symbol,
                               temp: "\(Int(d.high.rounded()))° / \(Int(d.low.rounded()))°", condition: c.text,
                               detail: Weather.outlook(hours, fahrenheit: f.fahrenheit, calendar: calendar)
                                   ?? (d.precipChance >= 30 ? "\(d.precipChance)% chance of rain" : "Lay it out tonight"),
                               outfit: Weather.outfit(for: hours, fahrenheit: f.fahrenheit, calendar: calendar))
        }
        let c = Weather.condition(f.nowCode ?? f.day(now, calendar: calendar)?.code ?? 0, isDay: f.nowIsDay)
        let hours = Weather.outHours(f, on: calendar.startOfDay(for: now), now: now, calendar: calendar)
        var detail: [String] = []
        if let d = f.day(now, calendar: calendar) { detail.append("H \(Int(d.high.rounded()))° · L \(Int(d.low.rounded()))°") }
        if let feels = f.nowFeels, let temp = f.nowTemp, abs(feels - temp) >= 4 { detail.append("feels \(Int(feels.rounded()))°") }
        if let outlook = Weather.outlook(hours, fahrenheit: f.fahrenheit, calendar: calendar) { detail.append(outlook) }
        return WeatherInfo(kind: .forecast, symbol: c.symbol,
                           temp: f.nowTemp.map { "\(Int($0.rounded()))°" } ?? "–", condition: c.text,
                           detail: detail.joined(separator: " · "),
                           outfit: Weather.outfit(for: hours, fahrenheit: f.fahrenheit, calendar: calendar))
    }

    private static func weekDelta(_ score: Int, _ recent: [HealthInsights.Night]) -> Int? {
        let others = recent.dropLast().suffix(7).map(HealthInsights.sleepScore)
        guard others.count >= 3 else { return nil }
        return score - others.reduce(0, +) / others.count
    }

    private static func meters(_ i: TodayInputs) -> [Meter] {
        func ratio(_ v: Double, _ t: Double) -> Double { t > 0 ? v / t : 0 }
        let over = i.calories > i.calorieBudget && i.calorieBudget > 0
        return [
            Meter(id: "water", icon: "drop.fill", tint: Neka.sky, progress: ratio(i.waterOz, i.waterTarget),
                  text: "\(Int(i.waterOz)) oz"),
            Meter(id: "protein", icon: "bolt.fill", tint: Neka.orange, progress: ratio(i.protein, i.proteinTarget),
                  text: "\(Int(i.protein)) g"),
            Meter(id: "food", icon: "fork.knife", tint: over ? Neka.rose : Neka.green, progress: ratio(i.calories, i.calorieBudget),
                  text: "\(Int(i.calories).formatted()) cal"),
            Meter(id: "mile", icon: "figure.walk", tint: Neka.lavender, progress: ratio(i.miles, max(0.1, i.mileGoal)),
                  text: String(format: "%.1f mi", i.miles))
        ]
    }

    /// On pace for the hour, or the one thing furthest behind.
    private static func paceVerdict(_ i: TodayInputs, score: Int, now: Date, calendar: Calendar) -> String {
        if score >= 85 { return "Dialed in already. Coast it home." }
        let c = calendar.dateComponents([.hour, .minute], from: now)
        let hours = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        let expected = min(1, max(0, (hours - 7) / 14))
        if Double(score) >= expected * 100 - 8 { return "Right on pace for the hour. Keep stacking it." }
        var gaps: [(Double, String)] = []
        if i.waterTarget > 0 {
            let left = Int(max(0, i.waterTarget - i.waterOz))
            if left > 0 { gaps.append((i.waterOz / i.waterTarget, "\(left) oz of water to go.")) }
        }
        if i.proteinTarget > 0 {
            let left = Int(max(0, i.proteinTarget - i.protein))
            if left > 0 { gaps.append((i.protein / i.proteinTarget, "\(left) g of protein to go.")) }
        }
        if i.miles < i.mileGoal { gaps.append((i.miles / max(0.1, i.mileGoal), "The mile's still waiting.")) }
        if let worst = gaps.min(by: { $0.0 < $1.0 }) { return "A little behind. \(worst.1)" }
        return "A little behind the hour. Plenty of day left."
    }

    /// "Bed by 10:30 PM for 7h 30m · up at 6:30 AM".
    private static func tonightLine(now: Date, calendar: Calendar) -> String? {
        let schedule = WakeSchedule.load()
        // After midnight, the morning ahead is today's.
        let base = calendar.component(.hour, from: now) < 4 ? now : calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let morning = calendar.startOfDay(for: base)
        guard let wake = schedule.minutes(on: morning) else { return "No alarm tomorrow. Sleep in." }
        guard let bed = schedule.bedtime(before: morning) else { return "Up at \(WakeSchedule.clock(wake))." }
        let bedText = bed.formatted(date: .omitted, time: .shortened)
        return bed > now
            ? "Bed by \(bedText) · up at \(WakeSchedule.clock(wake))"
            : "Past your \(bedText) bedtime. Lights out."
    }

    /// One upbeat line, from whatever's most notable this morning.
    private static func funLine(_ i: TodayInputs, score: Int, calendar: Calendar) -> (icon: String, text: String)? {
        if let night = i.night, calendar.isDateInToday(night.wakeDay) || calendar.isDateInToday(night.wakeTime),
           let planned = WakeSchedule.load().wake(on: night.wakeTime) {
            let late = Int(night.wakeTime.timeIntervalSince(planned) / 60)
            let plan = WakeSchedule.clock(WakeScheduleView.minutes(of: planned))
            if abs(late) <= 10 { return ("alarm.fill", "Up right on time for your \(plan) alarm. Consistency is the cheat code.") }
            if late > 30 { return ("alarm", "Up \(late) min after your \(plan) alarm. Lights out a little earlier tonight.") }
        }
        let week = i.recentNights.suffix(7).map(HealthInsights.sleepScore)
        if week.count >= 4, score >= (week.max() ?? 0) { return ("trophy.fill", "Best night of your week. Today's a good day to push.") }
        if score < 55 { return ("drop.fill", "Rough night. Extra water, a walk in daylight, and an early bedtime.") }
        if i.mileStreak >= 7 { return ("figure.walk", "A full week of miles in a row. Don't break the chain.") }
        if let progress = i.progress, progress.leader == .you, let friend = i.friendName {
            return ("crown.fill", "You're ahead of \(friend). Stay boring, stay winning.")
        }
        return nil
    }

    private static func todayChips(_ i: TodayInputs, now: Date, calendar: Calendar) -> [Chip] {
        var out: [Chip] = []
        if let readiness = i.readiness {
            out.append(Chip(id: "ready", icon: "bolt.heart.fill", tint: Neka.green, title: "Readiness",
                            value: "\(readiness) · \(readiness >= 75 ? "Push today" : readiness >= 55 ? "Steady day" : "Go easy")"))
        }
        if let w = weighIn(i.weightReadings, now: now, calendar: calendar) {
            out.append(Chip(id: "weight", icon: "scalemass.fill", tint: Neka.sky, title: "Overnight", value: w))
        } else {
            out.append(Chip(id: "weight", icon: "scalemass.fill", tint: Neka.sky, title: "Weigh-in",
                            value: "Step on the scale", action: i.onWeighIn))
        }
        out.append(Chip(id: "mile", icon: "figure.walk", tint: Neka.lavender, title: "Mile streak",
                        value: i.mileStreak > 0 ? "🔥 \(i.mileStreak) day\(i.mileStreak == 1 ? "" : "s")" : "Start one today"))
        let session = WorkoutPlanStore.session(on: now)
        out.append(Chip(id: "workout", icon: session.symbol, tint: Neka.orange, title: "Today",
                        value: session.minutes > 0 ? "\(session.title.components(separatedBy: " · ").first ?? session.title) · \(session.minutes) min" : session.title))
        if let progress = i.progress, let friend = i.friendName {
            let lead: String
            switch progress.leader {
            case .you:    lead = "Up on \(friend)"
            case .friend: lead = "\(friend) leads"
            default:      lead = "Neck and neck"
            }
            out.append(Chip(id: "challenge", icon: "flag.2.crossed.fill", tint: Neka.rose, title: "Challenge",
                            value: "\(lead) · \(progress.daysLeft)d left"))
        }
        if let goal = i.goalEvent, let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                                      to: calendar.startOfDay(for: goal.date)).day, days > 0 {
            out.append(Chip(id: "goal", icon: "sparkles", tint: Neka.amber, title: goal.name,
                            value: "\(days) day\(days == 1 ? "" : "s") to go"))
        }
        return out
    }

    private static func pastChips(_ day: DayRecapStore.Day?) -> [Chip] {
        guard let d = day else {
            return [Chip(id: "a", icon: "circle", tint: Neka.inkTertiary, title: "Loading", value: "Recovery 00"),
                    Chip(id: "b", icon: "circle", tint: Neka.inkTertiary, title: "Loading", value: "0.0 mi")]
        }
        var out: [Chip] = []
        if let p = d.pillars {
            if let r = p.recovery { out.append(Chip(id: "recovery", icon: "heart.fill", tint: Neka.green, title: "Recovery", value: "\(r)")) }
            if let r = p.readiness { out.append(Chip(id: "readiness", icon: "bolt.heart.fill", tint: Neka.sky, title: "Readiness", value: "\(r)")) }
            if let s = p.strain { out.append(Chip(id: "strain", icon: "flame.fill", tint: Neka.orange, title: "Strain", value: "\(s)")) }
        }
        let miles = d.miles ?? 0
        out.append(Chip(id: "mile", icon: "figure.walk", tint: Neka.lavender, title: "Mile",
                        value: miles >= MileADay.goal ? String(format: "✓ %.1f mi", miles) : String(format: "%.2f mi", miles)))
        if let w = d.weighIn ?? nil {
            out.append(Chip(id: "weight", icon: "scalemass.fill", tint: Neka.sky, title: "Weigh-in", value: String(format: "%.1f lb", w)))
        }
        if let title = d.workoutTitle {
            out.append(Chip(id: "workout", icon: "dumbbell.fill", tint: Neka.orange, title: "Workout", value: title))
        }
        if let q = d.quests {
            out.append(Chip(id: "quests", icon: "checklist.checked", tint: Neka.amber, title: "Quests", value: "\(q.done) of 3 · +\(q.xp) XP"))
        }
        return out
    }

    /// "−0.6 lb 🎉" when you've weighed in today and before.
    private static func weighIn(_ readings: [WeightReading], now: Date, calendar: Calendar) -> String? {
        let today = calendar.startOfDay(for: now)
        let sorted = readings.sorted { $0.date < $1.date }
        guard let latest = sorted.last, latest.date >= today else { return nil }
        guard let before = sorted.last(where: { $0.date < today }) else {
            return String(format: "%.1f lb", latest.pounds)
        }
        let change = latest.pounds - before.pounds
        if abs(change) < 0.05 { return String(format: "%.1f lb · same", latest.pounds) }
        return String(format: "%@%.1f lb%@", change < 0 ? "−" : "+", abs(change), change < 0 ? " 🎉" : "")
    }
}
