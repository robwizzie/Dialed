//
//  HomePatternCard.swift
//  Dialed
//
//  One habit from your last five weeks, on Home: "Weekends average 600
//  more calories". Rotates through your strongest few, one a day, and
//  stays hidden until there's something real to say.
//

import SwiftUI
import SwiftData

struct HomePatternCard: View {
    /// Opens the weekly review, where every pattern is listed.
    var onOpenReview: (() -> Void)?

    @Environment(\.modelContext) private var context
    @State private var patterns: [PatternFinder.Pattern] = []

    /// Today's pick among the top three.
    private var pattern: PatternFinder.Pattern? {
        guard !patterns.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return patterns[day % min(3, patterns.count)]
    }

    var body: some View {
        // A VStack (not a Group) so `.task` still runs while it's empty.
        VStack(spacing: 0) {
            if let p = pattern {
                Button { onOpenReview?() } label: { PatternRow(pattern: p, label: "YOUR PATTERN", showsChevron: onOpenReview != nil) }
                    .buttonStyle(.dialedScale)
                    .disabled(onOpenReview == nil)
                    .transition(.opacity)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let found = await PatternLoader.patterns(context: context)
        withAnimation(.easeOut(duration: 0.25)) { patterns = found }
    }
}

/// A pattern as a card: icon, title, the numbers behind it.
struct PatternRow: View {
    let pattern: PatternFinder.Pattern
    var label: String?
    var showsChevron = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pattern.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(pattern.isGood ? Neka.greenText : Neka.orangeText)
                .frame(width: 40, height: 40)
                .background(Circle().fill(pattern.isGood ? Neka.greenSoft : Neka.orangeSoft))
            VStack(alignment: .leading, spacing: 3) {
                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Neka.inkTertiary)
                }
                Text(pattern.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Neka.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pattern.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Neka.inkTertiary)
                    .padding(.top, 12)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nekaCard()
    }
}
