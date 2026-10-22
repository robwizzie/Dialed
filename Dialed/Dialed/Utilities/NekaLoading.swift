//
//  NekaLoading.swift
//  Dialed
//
//  One loading look for the whole app: content stands in as soft grey
//  bars (SwiftUI's placeholder redaction) with a light sweep across them,
//  then fades to the real thing. Use `.nekaLoading(isLoading)` on a card's
//  content while its first load runs, `NekaSkeletonCard` where there's no
//  content to redact yet, and `NekaLoadingPage` for a page's first load.
//  The sweep is one gradient per view and stops (and costs nothing) once
//  loading ends or with Reduce Motion on.
//

import SwiftUI

extension Neka {
    /// The bright band that sweeps across loading placeholders.
    static let shimmer = Color(light: Color.white.opacity(0.75), dark: Color.white.opacity(0.10))
    /// A placeholder bar or block.
    static let skeleton = Color(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.08))
}

// MARK: - Modifiers

extension View {
    /// Placeholder bars that shimmer while `loading`; the real content fades
    /// in after. Taps are off while loading.
    func nekaLoading(_ loading: Bool) -> some View {
        redacted(reason: loading ? .placeholder : [])
            .modifier(NekaShimmer(active: loading))
            .allowsHitTesting(!loading)
            .animation(.easeOut(duration: 0.3), value: loading)
    }

    /// Just the sweep, for views that draw their own placeholder shapes.
    func nekaShimmer(_ active: Bool = true) -> some View {
        modifier(NekaShimmer(active: active))
    }
}

/// A light band sweeping left to right, clipped to the content's shape.
struct NekaShimmer: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(colors: [.clear, Neka.shimmer, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.5)
                            .offset(x: phase * w * 1.5 - w * 0.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = 0
                        withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { phase = 1 }
                    }
                    .transition(.opacity)
                }
            }
    }
}

// MARK: - Skeleton pieces

/// A rounded block standing in for a line of text, a number or a chart.
struct NekaSkeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Neka.skeleton)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A whole card's placeholder: an icon, a title, a big value and a few
/// lines, shimmering. Sized roughly like the card it stands in for.
struct NekaSkeletonCard: View {
    var height: CGFloat = 150
    var lines: Int = 2
    var wash: Neka.Wash = .plain

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Neka.skeleton).frame(width: 32, height: 32)
                NekaSkeleton(width: 110, height: 12)
                Spacer(minLength: 0)
            }
            NekaSkeleton(width: 140, height: 26, radius: 8)
            ForEach(0..<max(0, lines), id: \.self) { i in
                NekaSkeleton(width: i == lines - 1 ? 160 : nil, height: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .nekaShimmer()
        .nekaCard(wash: wash)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// A page's first load: a stack of skeleton cards in place of the content,
/// so the layout doesn't jump around once data lands.
struct NekaLoadingPage: View {
    var cards: [CGFloat] = [190, 130, 130, 160]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(cards.enumerated()), id: \.offset) { i, height in
                NekaSkeletonCard(height: height, lines: height > 160 ? 3 : 2)
                    .opacity(1 - Double(i) * 0.12)
            }
        }
        .transition(.opacity)
    }
}

/// Small inline "Updating…" pill for a refresh that runs over data already
/// on screen, instead of a spinner that pushes the layout around.
struct NekaUpdatingPill: View {
    var text: String = "Updating"

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Neka.track))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            Text("Loaded value 1,234").font(.title).padding().nekaLoading(true).nekaCard()
            NekaLoadingPage()
        }
        .padding(16)
    }
    .nekaPageBackground()
}
