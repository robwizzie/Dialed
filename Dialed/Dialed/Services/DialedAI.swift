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
    static func estimateMeal(_ description: String, seen: [String] = []) async -> AIMealEstimate? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !seen.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
            You estimate nutrition for meals people describe in plain language or photograph. \
            Assume typical US restaurant or home portions unless sizes are given. \
            Be realistic, not optimistic — people underestimate calories. \
            When items come from a photo, treat them as one plate of food; ignore anything \
            that isn't food (tableware, the table, hands).
            """)
            var prompt = ""
            if !seen.isEmpty { prompt += "A photo of the meal shows: \(seen.joined(separator: ", ")). " }
            if !text.isEmpty { prompt += "The person says: \(text). " }
            prompt += "Estimate this meal."
            do {
                let response = try await session.respond(to: prompt, generating: GeneratedMeal.self)
                let m = response.content
                return AIMealEstimate(
                    name: m.name,
                    calories: max(0, min(4_000, m.calories)),
                    proteinGrams: max(0, min(300, m.proteinGrams)),
                    carbsGrams: max(0, min(600, m.carbsGrams)),
                    fatGrams: max(0, min(300, m.fatGrams)),
                    assumption: m.assumption
                )
            } catch {
                return nil
            }
        }
        #endif
        return nil
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
    static func parseWorkout(_ text: String) async -> [WorkoutTextParser.ParsedExercise]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            let session = LanguageModelSession(instructions: """
            You turn a person's quick gym notes into a list of exercises with their sets. \
            Only include what they actually wrote — never invent exercises, weights or reps. \
            Weights are in pounds. Bodyweight exercises have weight 0.
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
    @Guide(description: "The exercise name as written, e.g. bench press, squat, lat pulldown")
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

@available(iOS 26.0, *)
@Generable
struct GeneratedMeal {
    @Guide(description: "Short, tidy name for the meal")
    var name: String

    @Guide(description: "Estimated total calories as a whole number")
    var calories: Int

    @Guide(description: "Estimated grams of protein as a whole number")
    var proteinGrams: Int

    @Guide(description: "Estimated grams of carbohydrate as a whole number")
    var carbsGrams: Int

    @Guide(description: "Estimated grams of fat as a whole number")
    var fatGrams: Int

    @Guide(description: "One short sentence naming the biggest portion assumption")
    var assumption: String
}
#endif
