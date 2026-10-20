//
//  DialedAI.swift
//  Dialed
//
//  Apple Intelligence, on-device, via the Foundation Models framework
//  (iOS 26+). Nothing leaves the phone. Powers:
//
//    • Daily brief — a short, personal read on today for the Home screen
//    • Ask Dialed — chat about your own numbers ("am I on pace?")
//    • Meal estimate — "chipotle bowl, double chicken", or what Vision
//      sees in a meal photo → calories, protein, carbs and fat
//    • Trash talk — a message to send your challenge opponent
//
//  The app still targets iOS 17, so everything here is gated with
//  `canImport` + `#available`. Callers use the plain types below and get
//  nil (or a fallback) when the model isn't available.
//

import Foundation
#if canImport(Combine)
import Combine
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Plain result types (no framework dependency)

struct AIBrief: Codable, Equatable {
    var headline: String
    var message: String
    var actions: [String]
}

/// An order Apple Intelligence suggests at a restaurant Dialed doesn't
/// have a menu for.
struct AIRestaurantPick: Equatable, Identifiable {
    var title: String
    var items: [String]
    var calories: Int
    var proteinGrams: Int
    var carbsGrams: Int
    var fatGrams: Int
    var tips: [String]
    var id: String { title + items.joined() }
}

struct AIMealEstimate: Equatable {
    var name: String
    var calories: Int
    var proteinGrams: Int
    var carbsGrams: Int? = nil
    var fatGrams: Int? = nil
    var assumption: String
    /// Itemized: each food, its amount and numbers.
    var parts: [MealPart] = []
    /// Every number came from Dialed's food table (no model math).
    var fromTable = false
}

enum AIAvailability: Equatable {
    case available
    case unsupportedDevice
    case notEnabled
    case notReady

    var explanation: String {
        switch self {
        case .available:
            return "Apple Intelligence is on."
        case .unsupportedDevice:
            return "Needs Apple Intelligence: iPhone 15 Pro or newer on iOS 26."
        case .notEnabled:
            return "Turn on Apple Intelligence in Settings to use this."
        case .notReady:
            return "Apple Intelligence is still downloading. Try again soon."
        }
    }
}

// MARK: - Facade

@MainActor
enum DialedAI {

    static var availability: AIAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:           return .unsupportedDevice
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady:               return .notReady
                @unknown default:                  return .unsupportedDevice
                }
            }
        }
        #endif
        return .unsupportedDevice
    }

    static var isAvailable: Bool { availability == .available }

    /// Shared rules for every prompt: grounded, brief, safe.
    static let coachRules = """
    You are Dialed, a warm, witty personal health coach inside a fitness app. \
    The user is in a one-month weight-loss challenge against a friend. \
    Only use the numbers you are given — never invent data. Be specific and brief. \
    Never recommend eating under 1,500 calories a day, losing more than 2 lb a week, \
    skipping meals, or anything unsafe. You are not a doctor; for medical questions, \
    suggest talking to one.
    """

    // MARK: Daily brief

    static func brief(for snapshot: HealthSnapshot) async -> AIBrief? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: coachRules)
            let prompt = """
            Write today's brief for the user from these numbers. \
            Mention the challenge standing if there is one, and what matters most for the rest of today.

            \(snapshot.promptText)
            """
            do {
                let response = try await session.respond(to: prompt, generating: GeneratedBrief.self)
                let b = response.content
                return AIBrief(
                    headline: b.headline,
                    message: b.message,
                    actions: Array(b.actions.prefix(3))
                )
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: Meal estimate

    /// Estimate a meal from a description, and/or from what Vision found in
    /// a photo of it (`seen`, e.g. ["grilled chicken", "rice", "broccoli"]).
    ///
    /// The on-device model is small and poor at nutrition arithmetic, so it
    /// never does the math here. First Dialed's food table itemizes the
    /// description itself; only if something isn't in the table does the
    /// model list the ingredients and portions — then the table prices
    /// every one it knows, and the model's own numbers (sanity-checked) are
    /// used only for the rest.
    static func estimateMeal(_ description: String, seen: [String] = []) async -> AIMealEstimate? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !seen.isEmpty else { return nil }
        let combined = ([text] + seen).filter { !$0.isEmpty }.joined(separator: ", ")

        let local = MealMath.estimate(combined)
        if local.isComplete {
            return estimate(name: tidyName(text.isEmpty ? seen.joined(separator: ", ") : text), parts: local.parts,
                            assumption: "Itemized from Dialed's food table — adjust any portion below.", fromTable: true)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
            You break a meal into its ingredients with realistic single-serving amounts. \
            Use household units: cup, tbsp, tsp, oz, piece, slice, can, scoop. \
            Only list what the person ate — don't add sides or drinks they didn't mention. \
            A dish that's one thing stays one item: "5 pieces of a sushi roll" is sushi roll, 5 piece. \
            Example: "broccoli with olive oil and hot honey" → broccoli 1 cup; olive oil 1 tsp; hot honey 1 tsp. \
            Give honest per-ingredient calories: 1 cup broccoli is about 30, 1 tsp olive oil about 40, \
            1 cup cooked rice about 205, 4 oz chicken breast about 185, one piece of sushi roll about 45.
            """)
            var prompt = ""
            if !seen.isEmpty { prompt += "A photo of the meal shows: \(seen.joined(separator: ", ")). " }
            if !text.isEmpty { prompt += "The person says: \(text). " }
            prompt += "List the ingredients."
            if let response = try? await session.respond(to: prompt, generating: GeneratedMealBreakdown.self) {
                let m = response.content
                let parts = m.ingredients.prefix(12).compactMap { ing -> MealPart? in
                    let unit = MealMath.normalizedUnit(ing.unit) ?? ing.unit.lowercased()
                    let amount = ing.amount > 0 ? min(ing.amount, 50) : 1
                    if let food = NutritionTable.match(ing.food),
                       let part = MealMath.part(food, amount: amount, unit: MealMath.normalizedUnit(ing.unit)) {
                        return part
                    }
                    // Not in the table: the model's numbers, kept honest.
                    let protein = Double(max(0, min(150, ing.proteinGrams)))
                    let carbs = Double(max(0, min(250, ing.carbsGrams)))
                    let fat = Double(max(0, min(120, ing.fatGrams)))
                    let calories = MealMath.reconciled(calories: Double(max(0, min(1_500, ing.calories))),
                                                       protein: protein, carbs: carbs, fat: fat)
                    return MealPart(name: ing.food.capitalized, amount: MealMath.describe(amount, unit),
                                    grams: 0, calories: calories, protein: protein, carbs: carbs, fat: fat, fromTable: false)
                }
                if !parts.isEmpty {
                    let known = parts.filter(\.fromTable).count
                    let note = known == parts.count
                        ? "Portions by Apple Intelligence, numbers from Dialed's food table."
                        : "Portions by Apple Intelligence; \(known) of \(parts.count) items priced from Dialed's food table, the rest estimated."
                    return estimate(name: m.name, parts: parts,
                                    assumption: [note, m.assumption].filter { !$0.isEmpty }.joined(separator: " "),
                                    fromTable: known == parts.count)
                }
            }
        }
        #endif

        // No model (or it failed): whatever the table could itemize.
        guard !local.parts.isEmpty else { return nil }
        return estimate(name: tidyName(text), parts: local.parts,
                        assumption: "Couldn't price \(local.unknown.joined(separator: ", ")) — add it below or adjust the total.",
                        fromTable: true)
    }

    private static func estimate(name: String, parts: [MealPart], assumption: String, fromTable: Bool) -> AIMealEstimate {
        let total = { (key: KeyPath<MealPart, Double>) in Int(parts.reduce(0) { $0 + $1[keyPath: key] }.rounded()) }
        return AIMealEstimate(name: name, calories: total(\.calories), proteinGrams: total(\.protein),
                              carbsGrams: total(\.carbs), fatGrams: total(\.fat),
                              assumption: assumption, parts: parts, fromTable: fromTable)
    }

    /// "broccoli with olive oil, salt…" → "Broccoli with olive oil, salt…"
    private static func tidyName(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    // MARK: Eating out

    /// Up to three orders at `restaurant` that fit the calories and
    /// protein this meal has to work with.
    static func restaurantPicks(_ restaurant: String, calories: Int, protein: Int) async -> [AIRestaurantPick]? {
        let place = restaurant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
            You help someone on a weight-loss cut order at restaurants. Suggest real, \
            orderable items that this restaurant (or this kind of restaurant) commonly has, \
            with realistic calorie and macro estimates — be honest, not optimistic. \
            Favor lean protein, vegetables and sauces on the side. Never suggest skipping meals.
            """)
            let prompt = """
            Restaurant: \(place). This meal should be about \(calories) calories or less \
            with about \(protein) g of protein. Give three different orders: the best fit for \
            those numbers, a lighter one, and a more filling one.
            """
            do {
                let response = try await session.respond(to: prompt, generating: GeneratedRestaurantPicks.self)
                let picks = response.content.orders.prefix(3).map {
                    AIRestaurantPick(title: $0.title, items: $0.items,
                                     calories: max(0, min(3_000, $0.calories)), proteinGrams: max(0, min(250, $0.proteinGrams)),
                                     carbsGrams: max(0, min(400, $0.carbsGrams)), fatGrams: max(0, min(250, $0.fatGrams)),
                                     tips: Array($0.tips.prefix(3)))
                }
                return picks.isEmpty ? nil : Array(picks)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: Workout from text

    /// Read a typed gym log ("bench 185 for 8 then 7, squats felt heavy at
    /// 225, five sets of five") into exercises and sets. Used when the rule
    /// parser can't make sense of it.
    static func parseWorkout(_ text: String, known knownNames: [String] = []) async -> [WorkoutTextParser.ParsedExercise]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
            You turn a person's gym notes into a list of exercises with their sets. \
            Only include what they actually wrote — never invent exercises, weights or reps. \
            Weights are in pounds. Bodyweight exercises have weight 0. \
            List one entry per set: "3 sets of 10 at 100" is reps [10, 10, 10] and weights [100, 100, 100]; \
            "1 set of 10 for 135, 1 set of 8 for 155" is reps [10, 8] and weights [135, 155]. \
            When they describe a machine instead of naming it, use its gym name: pulling the two \
            sides together for the inner chest is "Pec deck fly", sitting and pushing a sled with the \
            legs is "Leg press", pulling a bar down to the chest is "Lat pulldown". \
            Keep variants distinct: incline bench press is not bench press. \
            Runs, walks and bike rides go in minutes and miles with no sets. \
            Use the names from this list when one fits: \(knownNames.prefix(60).joined(separator: ", ")).
            """)
            do {
                let response = try await session.respond(to: "Gym notes: \(trimmed)", generating: GeneratedWorkout.self)
                let out = response.content.exercises.compactMap { e -> WorkoutTextParser.ParsedExercise? in
                    let count = min(e.reps.count, 12)
                    let sets = (0..<count).compactMap { i -> WorkoutTextParser.ParsedSet? in
                        let reps = e.reps[i]
                        guard reps > 0, reps <= 100 else { return nil }
                        let w = i < e.weightsLbs.count ? e.weightsLbs[i] : (e.weightsLbs.last ?? 0)
                        return WorkoutTextParser.ParsedSet(weight: w > 0 ? min(w, 1_500) : nil, reps: reps)
                    }
                    let minutes = e.minutes > 0 ? e.minutes : nil
                    let miles = e.miles > 0 ? e.miles : nil
                    guard !e.name.isEmpty, !sets.isEmpty || minutes != nil || miles != nil else { return nil }
                    return WorkoutTextParser.ParsedExercise(name: e.name, sets: sets, minutes: minutes, miles: miles)
                }
                return out.isEmpty ? nil : out
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: Trash talk

    static func trashTalk(_ snapshot: HealthSnapshot, tone: TrashTalkTone) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
            You write short, funny text messages between two friends in a weight-loss \
            challenge. Keep it playful — never mean about bodies, weight or looks; \
            roast effort, snacks and excuses instead. One or two sentences, at most one emoji, \
            no hashtags, no quotation marks.
            """)
            let style: String
            switch tone {
            case .friendly: style = "friendly and teasing"
            case .savage:   style = "savage but good-natured"
            case .hype:     style = "hyped-up and motivating for both of you"
            }
            let prompt = """
            Write a \(style) text from the user to \(snapshot.friendName ?? "their friend") about the challenge.

            \(snapshot.promptText)
            """
            do {
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 1.0))
                return response.content.trimmingCharacters(in: CharacterSet(charactersIn: "\"“” \n"))
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}

// MARK: - Ask Dialed chat

@MainActor
final class DialedAIChat: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isThinking = false

    /// Holds a LanguageModelSession on iOS 26 (typed loosely so this class
    /// stays available on iOS 17). The session keeps the conversation.
    private var session: AnyObject?
    private var snapshot: HealthSnapshot

    init(snapshot: HealthSnapshot) {
        self.snapshot = snapshot
    }

    func update(snapshot: HealthSnapshot) {
        self.snapshot = snapshot
        session = nil   // next question starts fresh with the new numbers
    }

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        messages.append(Message(role: .user, text: text))
        isThinking = true
        defer { isThinking = false }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), DialedAI.isAvailable {
            let s: LanguageModelSession
            if let existing = session as? LanguageModelSession {
                s = existing
            } else {
                s = LanguageModelSession(instructions: """
                \(DialedAI.coachRules) \
                Answer in at most four short sentences or a short list. \
                Here is the user's data for today:

                \(snapshot.promptText)
                """)
                session = s
            }
            do {
                let response = try await s.respond(to: text)
                messages.append(Message(role: .assistant, text: response.content))
            } catch {
                // Most likely the context window filled up — start over.
                session = nil
                messages.append(Message(role: .assistant, text: "I lost my train of thought — ask me that again?"))
            }
            return
        }
        #endif
        messages.append(Message(role: .assistant, text: DialedAI.availability.explanation))
    }
}

// MARK: - Generable schemas (iOS 26)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedBrief {
    @Guide(description: "A punchy headline of 3 to 6 words about today")
    var headline: String

    @Guide(description: "Two short sentences of encouraging, specific coaching grounded in the numbers")
    var message: String

    @Guide(description: "Three short, concrete actions for the rest of today, each under 8 words")
    var actions: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedMealBreakdown {
    @Guide(description: "Short, tidy name for the meal")
    var name: String

    @Guide(description: "Each ingredient the person ate, with its amount")
    var ingredients: [GeneratedIngredient]

    @Guide(description: "One short sentence on the biggest portion assumption")
    var assumption: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedIngredient {
    @Guide(description: "The food, plainly named, e.g. broccoli, olive oil, chicken breast, sushi roll")
    var food: String

    @Guide(description: "How much, as a number")
    var amount: Double

    @Guide(description: "Unit: cup, tbsp, tsp, oz, piece, slice, can or scoop")
    var unit: String

    @Guide(description: "Calories for this amount of this ingredient only")
    var calories: Int

    @Guide(description: "Grams of protein for this amount")
    var proteinGrams: Int

    @Guide(description: "Grams of carbohydrate for this amount")
    var carbsGrams: Int

    @Guide(description: "Grams of fat for this amount")
    var fatGrams: Int
}

@available(iOS 26.0, *)
@Generable
struct GeneratedRestaurantPicks {
    @Guide(description: "Three different orders: best fit, lighter, more filling")
    var orders: [GeneratedRestaurantOrder]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedRestaurantOrder {
    @Guide(description: "Two to four words, e.g. Best fit, Lighter, More filling")
    var title: String

    @Guide(description: "The items to order, as they'd appear on the menu")
    var items: [String]

    @Guide(description: "Estimated total calories as a whole number")
    var calories: Int

    @Guide(description: "Estimated grams of protein as a whole number")
    var proteinGrams: Int

    @Guide(description: "Estimated grams of carbohydrate as a whole number")
    var carbsGrams: Int

    @Guide(description: "Estimated grams of fat as a whole number")
    var fatGrams: Int

    @Guide(description: "One or two short ordering tips, e.g. dressing on the side")
    var tips: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedWorkout {
    @Guide(description: "Every exercise the person wrote, in order")
    var exercises: [GeneratedExercise]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedExercise {
    @Guide(description: "The exercise's gym name, e.g. Bench press, Incline bench press, Pec deck fly, Lat pulldown")
    var name: String

    @Guide(description: "Weight in pounds for each set, one number per set; 0 for bodyweight")
    var weightsLbs: [Double]

    @Guide(description: "Reps for each set, one number per set")
    var reps: [Int]

    @Guide(description: "Minutes, for timed or cardio work; otherwise 0")
    var minutes: Double

    @Guide(description: "Miles, for walking, running or biking; otherwise 0")
    var miles: Double
}

#endif
