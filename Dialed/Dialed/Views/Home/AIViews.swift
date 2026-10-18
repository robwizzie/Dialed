//
//  AIViews.swift
//  Dialed
//
//  Apple Intelligence surfaces: the Home brief card, Ask Dialed chat,
//  describe-your-meal logging, and the Challenge trash-talk card. All of
//  them degrade gracefully when the on-device model isn't available.
//

import SwiftUI
import SwiftData

// MARK: - Iridescent rim

/// Apple Intelligence-style glowing gradient rim. Spins while `active`.
struct IntelligenceRim: View {
    var cornerRadius: CGFloat = Neka.cardRadius
    var active: Bool = false
    @State private var angle: Double = 0

    var body: some View {
        let gradient = AngularGradient(colors: Neka.intelligence, center: .center, angle: .degrees(angle))
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(gradient, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(gradient, lineWidth: active ? 6 : 3)
                .blur(radius: active ? 10 : 6)
                .opacity(active ? 0.7 : 0.35)
        }
        .allowsHitTesting(false)
        .onAppear { spin() }
        .onChange(of: active) { _, _ in spin() }
    }

    private func spin() {
        if active {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                angle = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { angle = 0 }
        }
    }
}

// MARK: - Brief model

@MainActor
final class AIBriefModel: ObservableObject {
    @Published private(set) var brief: AIBrief?
    @Published private(set) var isGenerating = false
    @Published private(set) var generatedAt: Date?

    private static let briefKey = "ai.brief.v1"
    private static let dateKey = "ai.brief.date.v1"
    /// Regenerate after this long, so it tracks the day.
    private static let staleAfter: TimeInterval = 45 * 60

    init() {
        let defaults = UserDefaults.standard
        if let date = defaults.object(forKey: Self.dateKey) as? Date,
           Calendar.current.isDateInLogicalDay(date, of: Date()),
           let data = defaults.data(forKey: Self.briefKey),
           let cached = try? JSONDecoder().decode(AIBrief.self, from: data) {
            brief = cached
            generatedAt = date
        }
    }

    func refreshIfStale(_ snapshot: HealthSnapshot) async {
        guard let generatedAt else { return await generate(snapshot) }
        if Date().timeIntervalSince(generatedAt) > Self.staleAfter {
            await generate(snapshot)
        }
    }

    func generate(_ snapshot: HealthSnapshot) async {
        guard DialedAI.isAvailable, !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        guard let fresh = await DialedAI.brief(for: snapshot) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            brief = fresh
        }
        let now = Date()
        generatedAt = now
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: Self.briefKey)
            UserDefaults.standard.set(now, forKey: Self.dateKey)
        }
    }
}

// MARK: - Brief card

struct AIBriefCard: View {
    @ObservedObject var model: AIBriefModel
    let availability: AIAvailability
    var onRegenerate: () -> Void
    var onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: Neka.intelligence, startPoint: .leading, endPoint: .trailing))
                Text("Dialed Intelligence")
                    .font(Neka.label)
                    .foregroundColor(Neka.ink)
                Spacer()
                if availability == .available {
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Neka.inkSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Neka.track))
                    }
                    .disabled(model.isGenerating)
                    .accessibilityLabel("New brief")
                }
            }

            if availability != .available {
                Text(availability.explanation + " Your coach below still works without it.")
                    .font(.system(size: 13))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let brief = model.brief {
                Text(brief.headline)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(brief.message)
                    .font(.system(size: 14))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(brief.actions, id: \.self) { action in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Neka.lavender)
                                .padding(.top, 1)
                            Text(action)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Neka.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                // First generation — shimmering placeholder lines.
                VStack(alignment: .leading, spacing: 8) {
                    placeholder(width: 0.6, height: 18)
                    placeholder(width: 0.95, height: 12)
                    placeholder(width: 0.8, height: 12)
                }
                .redacted(reason: .placeholder)
            }

            Button(action: onAsk) {
                HStack {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    Text("Ask Dialed anything")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Neka.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.track))
            }
            .buttonStyle(.dialedScale)
        }
        .padding(16)
        .nekaCard(wash: .lavender)
        .overlay(IntelligenceRim(active: model.isGenerating))
    }

    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .fill(Neka.muted)
                .frame(width: geo.size.width * width, height: height)
        }
        .frame(height: height)
    }
}

// MARK: - Ask Dialed

struct AskDialedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chat: DialedAIChat
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let friendName: String?

    init(snapshot: HealthSnapshot) {
        _chat = StateObject(wrappedValue: DialedAIChat(snapshot: snapshot))
        friendName = snapshot.friendName
    }

    private var suggestions: [String] {
        var list = [
            "Am I on pace for my goal?",
            "What should I eat for dinner?",
            "Plan a 20-minute workout for today",
            "How did I sleep?"
        ]
        if let friendName { list.insert("How am I doing vs. \(friendName)?", at: 0) }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if chat.messages.isEmpty { intro }
                            ForEach(chat.messages) { message in
                                bubble(message).id(message.id)
                            }
                            if chat.isThinking {
                                HStack(spacing: 8) {
                                    ProgressView().tint(Neka.lavender)
                                    Text("Thinking on-device…")
                                        .font(.system(size: 13))
                                        .foregroundColor(Neka.inkSecondary)
                                }
                                .id("thinking")
                            }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chat.messages.count) { _, _ in
                        if let id = chat.messages.last?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
                inputBar
            }
            .nekaPageBackground()
            .navigationTitle("Ask Dialed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Neka.ink)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: Neka.intelligence, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Your data, your questions.")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Neka.ink)
            }
            Text(DialedAI.isAvailable
                 ? "Runs entirely on your iPhone with Apple Intelligence. It sees today's numbers from your watch, scale and bottle — nothing is sent anywhere."
                 : DialedAI.availability.explanation)
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await chat.send(suggestion) }
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Neka.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Neka.surface))
                            .overlay(Capsule().stroke(Neka.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.dialedScale)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func bubble(_ message: DialedAIChat.Message) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 48) }
            Text(message.text)
                .font(.system(size: 15))
                .foregroundColor(isUser ? Neka.onInk : Neka.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isUser ? Neka.ink : Neka.surface)
                )
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your day…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .font(.system(size: 15))
                .foregroundColor(Neka.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Neka.surface))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Neka.onInk)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Neka.ink))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.isThinking)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Neka.paper.opacity(0.96))
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await chat.send(text) }
    }
}

// MARK: - Describe your meal

struct AIMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var description = ""
    @State private var name = ""
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var assumption: String?
    @State private var isEstimating = false
    @State private var estimateFailed = false

    private let aiAvailable = DialedAI.isAvailable

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What did you eat?")
                            .font(Neka.label)
                            .foregroundColor(Neka.ink)
                        TextField("e.g. Chipotle bowl, double chicken, no rice, guac", text: $description, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.system(size: 16))
                            .foregroundColor(Neka.ink)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Neka.surface))
                        if aiAvailable {
                            Button {
                                Task { await estimate() }
                            } label: {
                                HStack {
                                    if isEstimating {
                                        ProgressView().tint(Neka.onInk)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(isEstimating ? "Estimating on-device…" : "Estimate with Apple Intelligence")
                                }
                            }
                            .buttonStyle(.nekaPrimary)
                            .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isEstimating)
                            .overlay(IntelligenceRim(cornerRadius: 18, active: isEstimating))
                        } else {
                            Text(DialedAI.availability.explanation + " Enter the numbers below instead.")
                                .font(.system(size: 12))
                                .foregroundColor(Neka.inkSecondary)
                        }
                        if estimateFailed {
                            Text("Couldn't estimate that one — try adding portion sizes, or enter numbers below.")
                                .font(.system(size: 12))
                                .foregroundColor(Neka.rose)
                        }
                    }
                    .padding(16)
                    .nekaCard()

                    VStack(alignment: .leading, spacing: 12) {
                        if !name.isEmpty {
                            Text(name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Neka.ink)
                        }
                        numberRow("Calories", value: $calories, unit: "kcal", tint: Neka.green)
                        numberRow("Protein", value: $protein, unit: "g", tint: Neka.orange)
                        if let assumption {
                            Label(assumption, systemImage: "info.circle")
                                .font(.system(size: 12))
                                .foregroundColor(Neka.inkSecondary)
                        }
                    }
                    .padding(16)
                    .nekaCard()

                    Button("Log meal") { save() }
                        .buttonStyle(.nekaPrimary)
                        .disabled(calories <= 0)
                        .opacity(calories <= 0 ? 0.5 : 1)
                }
                .padding(16)
            }
            .nekaPageBackground()
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Neka.ink)
                }
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String, tint: Color) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Neka.ink)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Neka.ink)
                .frame(width: 100)
            Text(unit)
                .font(.system(size: 13))
                .foregroundColor(Neka.inkSecondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private func estimate() async {
        isEstimating = true
        estimateFailed = false
        defer { isEstimating = false }
        guard let result = await DialedAI.estimateMeal(description) else {
            estimateFailed = true
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            name = result.name
            calories = Double(result.calories)
            protein = Double(result.proteinGrams)
            assumption = result.assumption
        }
    }

    private func save() {
        let title = name.isEmpty ? description.trimmingCharacters(in: .whitespacesAndNewlines) : name
        let event = ContextEvent.meal(calories: calories, protein: protein, items: title.isEmpty ? [] : [title])
        if !title.isEmpty { event.text = title }
        modelContext.insert(event)
        try? modelContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }
}

// MARK: - Trash talk

struct TrashTalkCard: View {
    let snapshot: HealthSnapshot

    @State private var tone: TrashTalkTone = .friendly
    @State private var message: String = ""
    @State private var isGenerating = false
    @State private var variant = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                    .foregroundStyle(LinearGradient(colors: Neka.intelligence, startPoint: .leading, endPoint: .trailing))
                Text("Talk some trash")
                    .font(Neka.title)
                    .foregroundColor(Neka.ink)
                Spacer()
                if DialedAI.isAvailable {
                    Text("Apple Intelligence")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Neka.inkSecondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(TrashTalkTone.allCases) { option in
                    Button {
                        tone = option
                        Task { await generate() }
                    } label: {
                        Text("\(option.emoji) \(option.label)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tone == option ? Neka.onInk : Neka.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(tone == option ? Neka.ink : Neka.track))
                    }
                    .buttonStyle(.dialedScale)
                }
            }

            Text(message.isEmpty ? " " : message)
                .font(.system(size: 15))
                .foregroundColor(Neka.ink)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.surface))
                .overlay {
                    if isGenerating {
                        IntelligenceRim(cornerRadius: 16, active: true)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: message)

            HStack(spacing: 10) {
                Button {
                    variant += 1
                    Task { await generate() }
                } label: {
                    Label("Another", systemImage: "shuffle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.track))
                }
                .buttonStyle(.dialedScale)
                .disabled(isGenerating)

                ShareLink(item: message) {
                    Label("Send to \(snapshot.friendName ?? "friend")", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Neka.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Neka.ink))
                }
                .disabled(message.isEmpty || isGenerating)
            }
        }
        .padding(16)
        .nekaCard()
        .task { if message.isEmpty { await generate() } }
    }

    private func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        if let text = await DialedAI.trashTalk(snapshot, tone: tone), !text.isEmpty {
            message = text
        } else {
            message = DialedAIFallback.trashTalk(snapshot, tone: tone, variant: variant)
        }
    }
}
