//
//  WrappedView.swift
//  Dialed
//
//  Dialed Wrapped as stories: full-screen cards with progress bars across
//  the top, tap right for next and left for back, press and hold to pause,
//  and each card auto-advances. Every card can be shared as an image.
//

import SwiftUI
import SwiftData

struct WrappedView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [WrappedBuilder.Card] = []
    @State private var loaded = false
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var shareImage: UIImage?

    private let perCard: Double = 6

    var body: some View {
        ZStack {
            if cards.indices.contains(index) {
                WrappedCardFace(card: cards[index], animate: true)
                    .id(cards[index].id)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .ignoresSafeArea()
                tapZones
                chrome
            } else if loaded {
                emptyState
            } else {
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .statusBarHidden()
        .task { await load() }
        .task(id: "\(index)-\(cards.count)") { await advance() }
        .onChange(of: index) { _, _ in renderShare() }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(cards.indices, id: \.self) { i in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(.white)
                                .frame(width: geo.size.width * (i < index ? 1 : i == index ? progress : 0))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            HStack {
                Text("Dialed Wrapped")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.black.opacity(0.2)))
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            Spacer()
            if let shareImage {
                ShareLink(item: Image(uiImage: shareImage),
                          preview: SharePreview(cards[index].title, image: Image(uiImage: shareImage))) {
                    Label("Share this card", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white))
                }
                .padding(.bottom, 28)
            }
        }
    }

    /// Left third goes back, the rest goes forward; holding pauses.
    private var tapZones: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                zone { step(-1) }
                    .frame(width: geo.size.width / 3)
                zone { step(1) }
            }
        }
        .padding(.top, 70)
        .padding(.bottom, 90)
    }

    private func zone(_ action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.25, perform: {}, onPressingChanged: { paused = $0 })
    }

    private var emptyState: some View {
        ZStack {
            LinearGradient(colors: [Neka.lavender, Neka.blue], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Nothing to wrap yet")
                    .font(Neka.display(28, weight: .bold))
                Text("Start a challenge and log a few weigh-ins. Your story builds itself.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 8)
            }
            .foregroundColor(.white)
            .padding(32)
        }
    }

    // MARK: - Flow

    private func step(_ delta: Int) {
        let next = index + delta
        if next >= cards.count { dismiss(); return }
        withAnimation(.easeInOut(duration: 0.25)) {
            index = max(0, next)
            progress = 0
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    /// Fill the current bar over `perCard` seconds, then move on.
    private func advance() async {
        progress = 0
        let tick = 0.05
        while progress < 1 {
            try? await Task.sleep(for: .seconds(tick))
            if Task.isCancelled { return }
            if !paused { progress = min(1, progress + tick / perCard) }
        }
        if index < cards.count - 1 { step(1) }
    }

    private func load() async {
        if let inputs = await WrappedLoader.inputs(context: context) {
            cards = WrappedBuilder.build(inputs)
        }
        loaded = true
        renderShare()
    }

    private func renderShare() {
        guard cards.indices.contains(index) else { shareImage = nil; return }
        let renderer = ImageRenderer(content: WrappedCardFace(card: cards[index], animate: false)
            .frame(width: 360, height: 640))
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

// MARK: - One card

struct WrappedCardFace: View {
    let card: WrappedBuilder.Card
    /// Off for share images (rendered once, no motion).
    var animate: Bool

    @State private var shown: Bool

    init(card: WrappedBuilder.Card, animate: Bool) {
        self.card = card
        self.animate = animate
        // Share images render without onAppear, so start fully shown.
        _shown = State(initialValue: !animate)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: Self.colors(card.kind), startPoint: .topLeading, endPoint: .bottomTrailing)
            // A big soft disc for depth.
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 420, height: 420)
                .offset(x: 160, y: -420)
            VStack(alignment: .leading, spacing: 14) {
                Text(card.eyebrow)
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.6)
                    .foregroundColor(.white.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.value)
                        .font(Neka.display(card.value.count > 7 ? 64 : 96, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if !card.unit.isEmpty {
                        Text(card.unit)
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .scaleEffect(shown ? 1 : 0.7, anchor: .bottomLeading)
                .opacity(shown ? 1 : 0)
                Text(card.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(card.detail.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 12)
                            .animation(animate ? .easeOut(duration: 0.4).delay(0.35 + Double(i) * 0.12) : nil, value: shown)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text("Dialed")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 18)
            }
            .padding(28)
            .padding(.bottom, 90)
        }
        .onAppear {
            guard animate else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { shown = true }
        }
    }

    static func colors(_ kind: WrappedBuilder.Card.Kind) -> [Color] {
        switch kind {
        case .intro:    return [Color(hex: "1B1B2F"), Neka.lavender]
        case .lost:     return [Neka.green, Color(hex: "1F7A4D")]
        case .miles:    return [Neka.sky, Neka.blue]
        case .lifting:  return [Neka.orange, Neka.rose]
        case .prs:      return [Neka.amber, Neka.orange]
        case .bestWeek: return [Color(hex: "2DB892"), Neka.sky]
        case .habit:    return [Neka.lavender, Neka.blue]
        case .passed:   return [Neka.rose, Neka.lavender]
        case .fun:      return [Neka.amber, Neka.rose]
        case .final:    return [Color(hex: "111111"), Neka.green]
        }
    }
}
