//
//  BarcodeScannerView.swift
//  Dialed
//
//  Point the camera at a barcode, look the product up in Open Food Facts,
//  pick how much you had (servings or grams), then hand a pre-filled
//  draft back to Add food, which shows the same review screen as every
//  other way of adding food. Devices without the live scanner can type
//  the number instead.
//

import SwiftUI
import VisionKit
import Vision

struct BarcodeScanView: View {
    /// Called with the draft to review.
    var onDraft: (FoodDraft) -> Void

    @State private var phase: Phase = .scanning
    @State private var typedCode = ""
    @State private var useGrams = false
    @State private var servings: Double = 1
    @State private var grams: Double = 100

    enum Phase: Equatable {
        case scanning
        case looking(String)
        case found(FoodFactsProduct)
        case failed(String)
    }

    private var scannerReady: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        Group {
            switch phase {
            case .scanning:
                scanning
            case .looking(let code):
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Looking up \(code)…")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .found(let product):
                confirm(product)
            case .failed(let message):
                failed(message)
            }
        }
    }

    // MARK: - Scanning

    @ViewBuilder
    private var scanning: some View {
        VStack(spacing: 14) {
            if scannerReady {
                DataScannerRepresentable { code in lookup(code) }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Neka.hairline, lineWidth: 1)
                    )
                Text("Hold the barcode inside the frame.")
                    .font(.system(size: 12))
                    .foregroundColor(Neka.inkSecondary)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 40))
                        .foregroundColor(Neka.inkTertiary)
                    Text("The camera scanner isn't available here (it needs camera access on a recent iPhone). Type the number under the barcode instead.")
                        .font(.system(size: 13))
                        .foregroundColor(Neka.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .nekaCard()
                Spacer()
            }
            manualEntry
        }
        .padding(16)
    }

    private var manualEntry: some View {
        HStack(spacing: 10) {
            TextField("Barcode number", text: $typedCode)
                .keyboardType(.numberPad)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Capsule().fill(Neka.surface))
                .overlay(Capsule().stroke(Neka.hairline, lineWidth: 1))
            Button("Look up") { lookup(typedCode) }
                .buttonStyle(.nekaPrimary)
                .disabled(typedCode.filter(\.isNumber).count < 6)
        }
    }

    // MARK: - Confirm

    private func confirm(_ product: FoodFactsProduct) -> some View {
        let portion: FoodFactsPortion = useGrams ? .grams(grams) : .servings(servings)
        let n = product.nutrients(for: portion)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Neka.ink)
                    if let serving = product.servingSize {
                        Text("Serving: \(serving)")
                            .font(.system(size: 12))
                            .foregroundColor(Neka.inkSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if product.supportsServings && product.supportsGrams {
                        Picker("Amount", selection: $useGrams) {
                            Text("Servings").tag(false)
                            Text("Grams").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    if useGrams {
                        Stepper(value: $grams, in: 5...2_000, step: 5) {
                            Text("\(Int(grams)) g")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    } else {
                        Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                            Text("\(servings.formatted(.number.precision(.fractionLength(0...2)))) serving\(servings == 1 ? "" : "s")")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                }
                .padding(14)
                .nekaCard()

                HStack(spacing: 10) {
                    stat("Calories", n?.calories, unit: "calories", tint: Neka.orangeSoft)
                    stat("Protein", n?.protein, unit: "g", tint: Neka.greenSoft)
                }
                HStack(spacing: 10) {
                    stat("Carbs", n?.carbs, unit: "g", tint: Neka.skySoft)
                    stat("Fat", n?.fat, unit: "g", tint: Neka.lavenderSoft)
                }

                Button {
                    guard let n else { return }
                    onDraft(draft(product, n, portion: portion))
                } label: {
                    Text("Review & log").frame(maxWidth: .infinity)
                }
                .buttonStyle(.nekaPrimary)
                .disabled(n == nil)

                Button("Scan another") { phase = .scanning }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Neka.inkSecondary)
                    .frame(maxWidth: .infinity)

                Text("Nutrition from Open Food Facts (openfoodfacts.org), a community database — double-check against the label.")
                    .font(.system(size: 11))
                    .foregroundColor(Neka.inkTertiary)
            }
            .padding(16)
        }
    }

    private func stat(_ title: String, _ value: Double?, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Neka.inkSecondary)
            Text(value.map { "\(Int($0.rounded())) \(unit)" } ?? "—")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Neka.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 34))
                .foregroundColor(Neka.inkTertiary)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(Neka.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { phase = .scanning }
                .buttonStyle(.nekaPrimary)
            Button("Add by hand") {
                onDraft(FoodDraft())
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Neka.inkSecondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func lookup(_ code: String) {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty, phase == .scanning else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        phase = .looking(digits)
        Task {
            do {
                let product = try await OpenFoodFacts.lookup(digits)
                useGrams = !product.supportsServings
                servings = 1
                grams = product.servingGrams ?? 100
                phase = .found(product)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func draft(_ product: FoodFactsProduct, _ n: FoodFactsNutrients, portion: FoodFactsPortion) -> FoodDraft {
        var d = FoodDraft()
        let amount: String
        switch portion {
        case .servings(let s):
            // Kept as servings, so the review and the food log can rescale it.
            amount = ""
            d.servings = s
        case .grams(let g):    amount = " (\(Int(g)) g)"
        }
        d.name = product.displayName + amount
        d.calories = (n.calories ?? 0).rounded()
        d.protein = (n.protein ?? 0).rounded()
        d.carbs = n.carbs.map { $0.rounded() }
        d.fat = n.fat.map { $0.rounded() }
        return d
    }
}

// MARK: - VisionKit scanner

/// Live barcode scanner; reports the first code it recognizes. (Also used
/// by the wake-up alarm's barcode mission, which adds QR codes.)
struct DataScannerRepresentable: UIViewControllerRepresentable {
    var symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128]
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var reported = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            guard !reported else { return }
            for item in items {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, !code.isEmpty {
                    reported = true
                    onCode(code)
                    return
                }
            }
        }
    }
}
