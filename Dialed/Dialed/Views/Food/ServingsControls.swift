//
//  ServingsControls.swift
//  Dialed
//
//  The pieces both food editors share for "how much did you have":
//
//    · LiveNumberField: a number that rolls to its new value the moment it
//      changes (servings, portions, ± buttons) and becomes a text field
//      when tapped. A value-bound TextField can't animate and redraws late
//      when its value changes underneath it, which made scaling feel slow.
//    · ServingsPicker: − / amount / + with quick ½× … 2× chips.
//

import SwiftUI

// MARK: - Live number

struct LiveNumberField: View {
    @Binding var value: Double?
    var placeholder = "0"
    var font: Font = .system(size: 17, weight: .semibold, design: .rounded)
    var color: Color = Neka.ink
    var alignment: Alignment = .trailing

    @FocusState private var focused: Bool
    @State private var text = ""
    /// What the field was filled with on focus; unchanged text isn't an edit.
    @State private var prefilled = ""
    /// A soft highlight when the value changes from elsewhere.
    @State private var flash = false

    init(value: Binding<Double?>, placeholder: String = "—", font: Font = .system(size: 17, weight: .semibold, design: .rounded),
         color: Color = Neka.ink, alignment: Alignment = .trailing) {
        _value = value
        self.placeholder = placeholder
        self.font = font
        self.color = color
        self.alignment = alignment
    }

    init(value: Binding<Double>, placeholder: String = "0", font: Font = .system(size: 17, weight: .semibold, design: .rounded),
         color: Color = Neka.ink, alignment: Alignment = .trailing) {
        _value = Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0 ?? 0 })
        self.placeholder = placeholder
        self.font = font
        self.color = color
        self.alignment = alignment
    }

    private var shown: String {
        value.map { Int($0.rounded()).formatted() } ?? placeholder
    }

    var body: some View {
        ZStack(alignment: alignment) {
            // Always in the tree so focus (and the keyboard) is instant.
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .font(font)
                .foregroundColor(color)
                .focused($focused)
                .opacity(focused ? 1 : 0)
                .onChange(of: text) { _, t in
                    guard focused, t != prefilled else { return }
                    let digits = t.filter(\.isNumber)
                    value = digits.isEmpty ? nil : Double(digits)
                }
            if !focused {
                Text(shown)
                    .font(font)
                    .foregroundColor(value == nil ? Neka.inkTertiary : color)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value ?? 0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Neka.green.opacity(flash ? 0.18 : 0))
                    )
                    .padding(.horizontal, -6)
                    .padding(.vertical, -2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, isFocused in
            guard isFocused else { return }
            prefilled = value.map { String(Int($0.rounded())) } ?? ""
            text = prefilled
        }
        .onChange(of: value) { _, _ in
            guard !focused else { return }
            flash = true
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { flash = false }
        }
        .accessibilityRepresentation {
            TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0)))
        }
    }
}

// MARK: - Servings

struct ServingsPicker: View {
    let servings: Double
    var onChange: (Double) -> Void

    static let quick: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                stepButton("minus", to: servings - 0.25)
                    .disabled(servings <= 0.25)
                Spacer()
                VStack(spacing: 0) {
                    Text(Self.number(servings))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(Neka.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: servings))
                    Text(servings == 1 ? "serving" : "servings")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Neka.inkSecondary)
                }
                Spacer()
                stepButton("plus", to: servings + 0.25)
                    .disabled(servings >= 20)
            }
            HStack(spacing: 6) {
                ForEach(Self.quick, id: \.self) { s in
                    let on = abs(servings - s) < 0.001
                    Button { onChange(s) } label: {
                        Text(Self.number(s) + "×")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(on ? Neka.onInk : Neka.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(on ? Neka.ink : Neka.track))
                    }
                    .buttonStyle(.dialedScale)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(servings + 0.25)
            case .decrement: onChange(servings - 0.25)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ icon: String, to value: Double) -> some View {
        Button { onChange(value) } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Neka.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Neka.track))
        }
        .buttonStyle(.dialedScale)
        .accessibilityLabel(icon == "plus" ? "More" : "Less")
    }

    /// Quarter steps, 0.25…20.
    static func clamp(_ s: Double) -> Double { min(20, max(0.25, (s * 4).rounded() / 4)) }

    static func number(_ s: Double) -> String {
        s.formatted(.number.precision(.fractionLength(0...2)))
    }
}
