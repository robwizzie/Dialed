//
//  VoiceCaptureSheet.swift
//  Dialed
//
//  Voice quick-add. Records via AVAudioEngine, streams to
//  SFSpeechRecognizer for live transcription, and parses the transcript
//  with VoiceParser to produce a ContextEvent. The user gets a chance
//  to see what was interpreted before saving.
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

@MainActor
struct VoiceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var recorder = VoiceRecorder()
    @State private var preview: ContextEvent?

    var body: some View {
        VStack(spacing: 18) {
            grabber

            Text("Voice capture")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 4)

            // Big circular mic
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: AppColors.Pillar.recovery.gradient.map { $0.opacity(0.35) },
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 140, height: 140)

                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(recorder.isRecording ? 1.06 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: recorder.isRecording)
            .onTapGesture { toggleRecording() }

            // Transcript
            VStack(alignment: .leading, spacing: 6) {
                Text(recorder.isRecording ? "Listening…" : "Tap the mic to speak")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                Text(recorder.transcript.isEmpty ? " " : recorder.transcript)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
            }

            // Interpreted preview
            if let preview {
                previewCard(for: preview)
            }

            // Error / permission
            if let error = recorder.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Spacer()

            saveButton
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(AppColors.nowBackground.ignoresSafeArea())
        .task { await recorder.prepare() }
        .onChange(of: recorder.transcript) { _, newValue in
            preview = VoiceParser.parse(newValue)
        }
        .onDisappear { recorder.stop() }
    }

    // MARK: - Subviews

    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.15))
            .frame(width: 38, height: 4)
            .padding(.top, 10)
    }

    private func previewCard(for event: ContextEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: kindIcon(event.kind))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: kindGradient(event.kind),
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(kindGradient(event.kind).first!.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Interpreted as")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                Text(interpretationCopy(for: event))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.6)
                )
        )
    }

    private var saveButton: some View {
        let canSave = preview != nil && !recorder.transcript.isEmpty
        return Button {
            save()
        } label: {
            Text("Save")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: AppColors.Pillar.recovery.gradient,
                            startPoint: .top, endPoint: .bottom
                        ))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
    }

    // MARK: - Actions

    private func toggleRecording() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        if recorder.isRecording {
            recorder.stop()
        } else {
            Task { await recorder.start() }
        }
    }

    private func save() {
        guard let event = preview else { return }
        recorder.stop()
        modelContext.insert(event)
        try? modelContext.save()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        dismiss()
    }

    // MARK: - Kind decoration

    private func kindIcon(_ kind: ContextEvent.Kind) -> String {
        switch kind {
        case .water:    return "drop.fill"
        case .caffeine: return "cup.and.saucer.fill"
        case .alcohol:  return "wineglass.fill"
        case .meal:     return "fork.knife"
        case .mood:     return "face.smiling.fill"
        case .energy:   return "bolt.fill"
        case .workout:  return "figure.strengthtraining.traditional"
        default:        return "square.and.pencil"
        }
    }

    private func kindGradient(_ kind: ContextEvent.Kind) -> [Color] {
        switch kind {
        case .water:                  return AppColors.Pillar.readiness.gradient
        case .caffeine, .meal:        return AppColors.Pillar.energy.gradient
        case .alcohol:                return AppColors.Pillar.strain.gradient
        case .mood, .energy:          return AppColors.Pillar.recovery.gradient
        case .workout:                return AppColors.Pillar.strain.gradient
        default:                      return AppColors.Pillar.recovery.gradient
        }
    }

    private func interpretationCopy(for event: ContextEvent) -> String {
        switch event.kind {
        case .water:    return "\(Int(event.value ?? 0)) oz water"
        case .caffeine: return "\(Int(event.value ?? 0)) mg caffeine"
        case .alcohol:  return "\(Int(event.value ?? 0)) drink(s)"
        case .meal:
            let cal = event.value.map { "\(Int($0)) kcal" }
            let prot = event.secondaryValue.map { "\(Int($0))g protein" }
            return [cal, prot].compactMap { $0 }.joined(separator: " · ").ifEmpty("Meal")
        case .mood:    return "Mood \(Int(event.value ?? 0))/5"
        case .energy:  return "Energy \(Int(event.value ?? 0))/5"
        case .workout:
            let mins = event.value.map { "\(Int($0)) min" } ?? ""
            let kind = event.subtype?.capitalized ?? "Workout"
            return [kind, mins].filter { !$0.isEmpty }.joined(separator: " · ")
        case .note:    return "Note: \(event.text ?? "")"
        default:       return event.text ?? "Note"
        }
    }
}

// MARK: - Recorder

/// Wraps the Speech/AVFoundation glue. Keeps the view declarative.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var transcript: String = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func prepare() async {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized:
            errorMessage = nil
        case .denied:
            errorMessage = "Speech recognition is denied. Enable it in Settings → Dialed."
        case .restricted:
            errorMessage = "Speech recognition is restricted on this device."
        case .notDetermined:
            errorMessage = nil
        @unknown default:
            errorMessage = nil
        }
    }

    func start() async {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        // Audio session
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't start the audio session."
            return
        }
        #endif

        // Tap the input node and feed the recognizer
        let input = audioEngine.inputNode
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start recording."
            return
        }

        transcript = ""
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
