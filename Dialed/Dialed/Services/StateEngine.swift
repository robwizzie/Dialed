//
//  StateEngine.swift
//  Dialed
//
//  Pure calculators for the four pillars that drive the new "Now" home
//  screen: Recovery, Readiness, Energy, Strain. Every pillar is a 0–100
//  score expressed against *your* PersonalBaseline rather than population
//  averages — the whole point of the redesign.
//
//  These functions are deliberately side-effect-free so they unit-test
//  cleanly. The view layer reads them; the orchestration layer (Phase 3
//  Plan service) writes the underlying samples.
//

import Foundation

enum StateEngine {

    // MARK: - Inputs

    /// Snapshot of "right now" — everything the calculators need bundled
    /// for one screen render. Decoupling input shape from SwiftData makes
    /// previewing trivial.
    struct LiveInputs {
        var now: Date
        var baseline: BaselineInputs?
        var lastSleep: SleepInputs?
        var latestBiometric: BiometricInputs?
        /// Today's accumulated load so far.
        var dayLoad: DayLoadInputs
        /// Last events that affect Energy (caffeine, meals, workout).
        var energyContext: EnergyContext

        init(
            now: Date = Date(),
            baseline: BaselineInputs? = nil,
            lastSleep: SleepInputs? = nil,
            latestBiometric: BiometricInputs? = nil,
            dayLoad: DayLoadInputs = .init(),
            energyContext: EnergyContext = .init()
        ) {
            self.now = now
            self.baseline = baseline
            self.lastSleep = lastSleep
            self.latestBiometric = latestBiometric
            self.dayLoad = dayLoad
            self.energyContext = energyContext
        }
    }

    struct BaselineInputs {
        var restingHRMean: Double?
        var restingHRStdDev: Double?
        var hrvMean: Double?
        var hrvStdDev: Double?
        var sleepDurationMinutesMean: Double?
        var sleepDurationMinutesStdDev: Double?

        /// Hydrates from the SwiftData model. Returns nil if the baseline has
        /// no usable rows yet (cold start).
        static func from(_ b: PersonalBaseline?) -> BaselineInputs? {
            guard let b = b else { return nil }
            return BaselineInputs(
                restingHRMean: b.restingHeartRateMean,
                restingHRStdDev: b.restingHeartRateStdDev,
                hrvMean: b.hrvMean,
                hrvStdDev: b.hrvStdDev,
                sleepDurationMinutesMean: b.sleepDurationMinutesMean,
                sleepDurationMinutesStdDev: b.sleepDurationMinutesStdDev
            )
        }
    }

    struct SleepInputs {
        var asleepMinutes: Int
        var deepMinutes: Int?
        var remMinutes: Int?
        var efficiency: Double?
        var endTime: Date
        var avgRestingHR: Double?
        var avgHRV: Double?

        static func from(_ s: SleepSession?) -> SleepInputs? {
            guard let s = s else { return nil }
            return SleepInputs(
                asleepMinutes: s.asleepMinutes,
                deepMinutes: s.deepMinutes,
                remMinutes: s.remMinutes,
                efficiency: s.efficiency,
                endTime: s.endTime,
                avgRestingHR: s.avgRestingHeartRate,
                avgHRV: s.avgHRV
            )
        }
    }

    struct BiometricInputs {
        var heartRate: Double?
        var restingHR: Double?
        var hrv: Double?
        var spO2: Double?
        var stressScore: Int?

        static func from(_ b: BiometricSnapshot?) -> BiometricInputs? {
            guard let b = b else { return nil }
            return BiometricInputs(
                heartRate: b.heartRate,
                restingHR: b.restingHeartRate,
                hrv: b.hrv,
                spO2: b.spO2,
                stressScore: b.stressScore
            )
        }
    }

    struct DayLoadInputs {
        var steps: Int = 0
        var activeCalories: Int = 0
        var exerciseMinutes: Int = 0
        var workoutDurationMinutes: Int = 0
        var workoutIntensity: Double? = nil  // 0–1, optional intensity hint
    }

    struct EnergyContext {
        /// Minutes since last caffeine intake.
        var minutesSinceCaffeine: Int? = nil
        /// Estimated caffeine mg currently in system (after half-life decay).
        var activeCaffeineMG: Double? = nil
        /// Minutes since last meal.
        var minutesSinceMeal: Int? = nil
        /// Minutes since last workout ended (post-workout dip + recovery).
        var minutesSinceWorkout: Int? = nil
        /// User's most recent self-reported energy (1–5), if any.
        var selfReported: Int? = nil
    }

    // MARK: - Outputs

    /// Score with provenance — every number on the home screen can answer
    /// "why?" by inspecting `contributions`.
    struct ScoreBreakdown: Equatable {
        var score: Int            // 0–100
        var grade: Grade
        var contributions: [Contribution]
        /// Confidence 0–1. Drops when baselines are thin or data is missing.
        var confidence: Double

        struct Contribution: Equatable {
            var label: String
            var points: Double    // signed; positive = boosting the score
            var note: String?
        }

        enum Grade: String, Equatable {
            case excellent  // 85+
            case good       // 70–84
            case fair       // 55–69
            case low        // 40–54
            case poor       // <40

            init(score: Int) {
                switch score {
                case 85...:  self = .excellent
                case 70...:  self = .good
                case 55...:  self = .fair
                case 40...:  self = .low
                default:     self = .poor
                }
            }

            var displayLabel: String {
                switch self {
                case .excellent: return "Excellent"
                case .good:      return "Good"
                case .fair:      return "Fair"
                case .low:       return "Low"
                case .poor:      return "Poor"
                }
            }
        }
    }

    // MARK: - Recovery

    /// How recovered your body is right now. Driven by sleep + last night's
    /// HRV/RHR relative to baseline. Range 0–100.
    static func recovery(_ inputs: LiveInputs) -> ScoreBreakdown {
        var points: [ScoreBreakdown.Contribution] = []
        var raw: Double = 50  // neutral midpoint with no data

        // Sleep duration vs baseline (weight: up to ±25)
        if let sleep = inputs.lastSleep {
            let hours = Double(sleep.asleepMinutes) / 60.0
            let target: Double = inputs.baseline?.sleepDurationMinutesMean.map { $0 / 60.0 } ?? 7.5
            let delta = hours - target

            let pts: Double
            switch delta {
            case 0...:        pts = min(25, delta * 8 + 18)        // at target → +18, +1h → +26 capped
            case -0.5..<0:    pts = 15
            case -1..<(-0.5): pts = 5
            case -2..<(-1):   pts = -10
            default:          pts = -25
            }
            raw += pts
            points.append(.init(label: "Sleep duration", points: pts,
                                note: String(format: "%.1fh vs %.1fh target", hours, target)))
        }

        // Sleep efficiency (weight: up to ±10)
        if let eff = inputs.lastSleep?.efficiency {
            let pts: Double
            switch eff {
            case 0.90...:  pts = 10
            case 0.85..<0.90: pts = 6
            case 0.75..<0.85: pts = 0
            case 0.65..<0.75: pts = -5
            default:       pts = -10
            }
            raw += pts
            points.append(.init(label: "Sleep efficiency", points: pts,
                                note: String(format: "%.0f%%", eff * 100)))
        }

        // HRV vs baseline (weight: up to ±20)
        if let hrv = inputs.lastSleep?.avgHRV ?? inputs.latestBiometric?.hrv,
           let mean = inputs.baseline?.hrvMean,
           let sd = inputs.baseline?.hrvStdDev, sd > 0 {
            let z = (hrv - mean) / sd
            let pts = max(-20, min(20, z * 10))  // ±2σ → ±20
            raw += pts
            points.append(.init(label: "HRV vs baseline", points: pts,
                                note: String(format: "z=%+0.1f", z)))
        }

        // Resting HR vs baseline (lower is better → invert sign, weight ±15)
        if let rhr = inputs.lastSleep?.avgRestingHR ?? inputs.latestBiometric?.restingHR,
           let mean = inputs.baseline?.restingHRMean,
           let sd = inputs.baseline?.restingHRStdDev, sd > 0 {
            let z = (rhr - mean) / sd
            let pts = max(-15, min(15, -z * 7.5))  // elevated RHR hurts
            raw += pts
            points.append(.init(label: "Resting HR vs baseline", points: pts,
                                note: String(format: "z=%+0.1f", z)))
        }

        let score = clamp(Int(raw.rounded()))
        let confidence = baselineConfidence(inputs.baseline) * sleepConfidence(inputs.lastSleep)
        return ScoreBreakdown(
            score: score,
            grade: .init(score: score),
            contributions: points,
            confidence: confidence
        )
    }

    // MARK: - Readiness

    /// Forward-looking: how prepared you are to take on today's load.
    /// Recovery × adherence × inverse-of-acute-strain. Range 0–100.
    static func readiness(
        _ inputs: LiveInputs,
        recoveryScore: Int,
        weeklyAdherence: Double = 1.0,   // 0–1, fraction of plan you've been hitting
        recentStrain: Int = 0            // 0–100; high recent strain pulls readiness down
    ) -> ScoreBreakdown {
        // Recovery is the primary driver (60%), adherence trims (20%),
        // recent strain trims (20%).
        let recoveryComponent = Double(recoveryScore) * 0.6
        let adherenceComponent = clamp01(weeklyAdherence) * 100 * 0.2
        let strainPenalty = (Double(recentStrain) / 100.0) * 20.0
        let raw = recoveryComponent + adherenceComponent - strainPenalty + 10  // small offset so a single bad night doesn't crater

        let score = clamp(Int(raw.rounded()))
        let contributions: [ScoreBreakdown.Contribution] = [
            .init(label: "Recovery", points: recoveryComponent, note: "\(recoveryScore)/100"),
            .init(label: "Weekly adherence", points: adherenceComponent,
                  note: String(format: "%.0f%%", weeklyAdherence * 100)),
            .init(label: "Recent strain", points: -strainPenalty, note: "\(recentStrain)/100")
        ]

        return ScoreBreakdown(
            score: score,
            grade: .init(score: score),
            contributions: contributions,
            confidence: 0.8
        )
    }

    // MARK: - Energy

    /// Estimated energy *right now*. A combination of:
    ///   - circadian curve (time-of-day baseline)
    ///   - recovery floor (you can't be high-energy if poorly recovered)
    ///   - caffeine boost (with half-life)
    ///   - post-meal trough then bump
    ///   - post-workout depletion → recovery curve
    /// Range 0–100. Refreshes whenever the view recomputes.
    static func energy(_ inputs: LiveInputs, recoveryScore: Int) -> ScoreBreakdown {
        var contributions: [ScoreBreakdown.Contribution] = []
        let now = inputs.now

        // 1. Circadian baseline (0–60 contribution)
        let circadian = circadianCurve(at: now)  // 0–1
        let circadianPoints = circadian * 60.0
        contributions.append(.init(
            label: "Circadian rhythm",
            points: circadianPoints,
            note: circadianBand(at: now)
        ))

        // 2. Recovery floor (0–20 contribution)
        let recoveryPoints = Double(recoveryScore) * 0.2
        contributions.append(.init(
            label: "Recovery floor",
            points: recoveryPoints,
            note: "\(recoveryScore)/100 recovery"
        ))

        // 3. Caffeine (0–15 contribution, decays)
        var caffeinePoints: Double = 0
        if let active = inputs.energyContext.activeCaffeineMG, active > 0 {
            // ~ 0.075 points per active mg, capped at 15. So 200mg active ≈ 15 pts.
            caffeinePoints = min(15, active * 0.075)
            contributions.append(.init(label: "Caffeine on board",
                                       points: caffeinePoints,
                                       note: "\(Int(active))mg active"))
        }

        // 4. Meal effect (post-meal dip 30–60min, then bump 60–180min)
        var mealPoints: Double = 0
        if let minutesSince = inputs.energyContext.minutesSinceMeal {
            switch minutesSince {
            case 30..<60:   mealPoints = -8     // post-meal slump
            case 60..<180:  mealPoints = 5      // nutrition kicking in
            case 180..<300: mealPoints = -3     // hunger creeping in
            case 300...:    mealPoints = -8     // properly hungry
            default:        mealPoints = 0
            }
            contributions.append(.init(label: "Last meal", points: mealPoints,
                                       note: "\(minutesSince)m ago"))
        }

        // 5. Post-workout dip (0..30min: dip; 30..120min: recover; 120+: normal)
        var workoutPoints: Double = 0
        if let minutesSince = inputs.energyContext.minutesSinceWorkout {
            switch minutesSince {
            case 0..<30:    workoutPoints = -10
            case 30..<90:   workoutPoints = -4
            case 90..<150:  workoutPoints = 3   // endorphin lift
            default:        workoutPoints = 0
            }
            contributions.append(.init(label: "Workout aftereffects",
                                       points: workoutPoints,
                                       note: "\(minutesSince)m since"))
        }

        let raw = circadianPoints + recoveryPoints + caffeinePoints + mealPoints + workoutPoints
        var score = clamp(Int(raw.rounded()))

        // Self-reported energy overrides up to ±15 if recent.
        if let self_ = inputs.energyContext.selfReported {
            // 1–5 → ±20 nudge from computed
            let nudge = (Double(self_) - 3.0) * 10.0
            score = clamp(Int((Double(score) + nudge).rounded()))
            contributions.append(.init(label: "Self-report", points: nudge,
                                       note: "\(self_)/5"))
        }

        return ScoreBreakdown(
            score: score,
            grade: .init(score: score),
            contributions: contributions,
            confidence: 0.7
        )
    }

    // MARK: - Strain

    /// How much load you've accumulated today. Higher = more taxed.
    /// Drives Readiness penalty and tomorrow's Recovery target.
    /// Range 0–100; capped at 100.
    static func strain(_ inputs: LiveInputs) -> ScoreBreakdown {
        let load = inputs.dayLoad
        var raw: Double = 0
        var contributions: [ScoreBreakdown.Contribution] = []

        // Steps contribution (10k steps ≈ 25 pts)
        let stepPts = min(30, Double(load.steps) / 10_000.0 * 25.0)
        raw += stepPts
        contributions.append(.init(label: "Steps", points: stepPts,
                                   note: "\(load.steps) steps"))

        // Active calories (500 kcal ≈ 25 pts)
        let calPts = min(30, Double(load.activeCalories) / 500.0 * 25.0)
        raw += calPts
        contributions.append(.init(label: "Active calories", points: calPts,
                                   note: "\(load.activeCalories) kcal"))

        // Workout duration weighted by intensity (60m moderate ≈ 30 pts)
        let intensity = load.workoutIntensity ?? 0.6
        let workoutPts = min(40, Double(load.workoutDurationMinutes) * intensity * 0.5)
        raw += workoutPts
        if load.workoutDurationMinutes > 0 {
            contributions.append(.init(label: "Workout", points: workoutPts,
                                       note: "\(load.workoutDurationMinutes)m × \(Int(intensity * 100))%"))
        }

        let score = clamp(Int(raw.rounded()))
        return ScoreBreakdown(
            score: score,
            grade: .init(score: score),
            contributions: contributions,
            confidence: 0.9
        )
    }

    // MARK: - Circadian helpers

    /// Returns 0…1 representing typical alertness curve for a given hour.
    /// Peak ~10am and ~5pm, troughs ~3am and ~2pm post-lunch dip.
    static func circadianCurve(at date: Date, calendar: Calendar = .current) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let h = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0

        // Composite of two cosine waves to capture morning peak + post-lunch dip + late-afternoon peak
        let primary = -cos((h - 10.0) * (.pi / 8.0))      // peak at 10
        let secondary = -cos((h - 17.0) * (.pi / 4.0))    // peak at 17, secondary
        let combined = (primary * 0.65 + secondary * 0.35)

        // Hard floor for nighttime hours (22 → 5)
        let nighttimeFactor: Double
        switch h {
        case 22...:          nighttimeFactor = max(0, 1 - (h - 22) * 0.5)
        case 0..<5:          nighttimeFactor = 0.2 + (h / 5.0) * 0.3
        default:             nighttimeFactor = 1.0
        }

        // Normalize from [-1, 1] → [0, 1] and apply nighttime damping
        let normalized = (combined + 1) / 2
        return clamp01(normalized * nighttimeFactor)
    }

    static func circadianBand(at date: Date, calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: date)
        switch h {
        case 0..<5:    return "Deep night"
        case 5..<8:    return "Cortisol rising"
        case 8..<11:   return "Morning peak"
        case 11..<14:  return "Late morning"
        case 14..<16:  return "Post-lunch dip"
        case 16..<19:  return "Afternoon peak"
        case 19..<22:  return "Winding down"
        default:       return "Wind down"
        }
    }

    // MARK: - Caffeine half-life

    /// Estimate active caffeine mg given a dose at `dosedAt` and current `now`,
    /// using a 5-hour half-life (population average).
    static func activeCaffeine(doseMG: Double, dosedAt: Date, now: Date = Date()) -> Double {
        let minutes = max(0, now.timeIntervalSince(dosedAt) / 60.0)
        let halfLifeMin: Double = 5 * 60
        let factor = pow(0.5, minutes / halfLifeMin)
        return doseMG * factor
    }

    // MARK: - Confidence helpers

    private static func baselineConfidence(_ b: BaselineInputs?) -> Double {
        guard let b = b else { return 0.3 }
        var bits: Double = 0
        if b.hrvMean != nil { bits += 0.3 }
        if b.restingHRMean != nil { bits += 0.3 }
        if b.sleepDurationMinutesMean != nil { bits += 0.4 }
        return min(1.0, bits + 0.1)
    }

    private static func sleepConfidence(_ s: SleepInputs?) -> Double {
        guard let s = s else { return 0.4 }
        var bits = 0.5
        if s.deepMinutes != nil { bits += 0.15 }
        if s.remMinutes != nil { bits += 0.15 }
        if s.efficiency != nil { bits += 0.1 }
        if s.avgHRV != nil { bits += 0.1 }
        return min(1.0, bits)
    }

    // MARK: - Math utils

    @inline(__always) private static func clamp(_ v: Int, low: Int = 0, high: Int = 100) -> Int {
        min(high, max(low, v))
    }

    @inline(__always) private static func clamp01(_ v: Double) -> Double {
        min(1.0, max(0.0, v))
    }
}
