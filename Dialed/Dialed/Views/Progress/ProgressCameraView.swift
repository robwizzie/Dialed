//
//  ProgressCameraView.swift
//  Dialed
//
//  Full-screen camera for progress photos. A custom AVFoundation capture
//  (not UIImagePickerController) so the live preview, the ghost of last
//  week's photo and the alignment guides all share one 3:4 frame — the
//  sensor's portrait aspect — and line up exactly with the saved photo.
//  Self-timer for solo shots, front/back flip, review before keeping.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera model

final class ProgressCameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum Status { case idle, running, unauthorized, unavailable }

    @Published var status: Status = .idle
    @Published var position: AVCaptureDevice.Position = .back
    @Published var captured: UIImage?
    @Published var isCapturing = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "dialed.progress-camera")
    private var input: AVCaptureDeviceInput?

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configureAndRun() } else { self.status = .unauthorized }
                }
            }
        default:
            status = .unauthorized
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func flip() {
        position = position == .back ? .front : .back
        configureAndRun()
    }

    private func configureAndRun() {
        let position = self.position
        queue.async {
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.photo) { self.session.sessionPreset = .photo }
            if let old = self.input { self.session.removeInput(old) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status = .unavailable }
                return
            }
            self.session.addInput(input)
            self.input = input
            if !self.session.outputs.contains(self.output), self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    func capture() {
        guard status == .running, !isCapturing else { return }
        isCapturing = true
        let mirror = position == .front
        queue.async {
            if let connection = self.output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    // Match the (mirrored) front preview so the ghost lines up.
                    connection.isVideoMirrored = mirror
                }
            }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        DispatchQueue.main.async {
            self.isCapturing = false
            if let image { self.captured = image }
        }
    }
}

// MARK: - Preview layer

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.setNeedsLayout()
    }
}

// MARK: - Alignment guides

/// Center line, thirds and head / feet marks so every week is framed the same.
struct PoseGuides: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0))
                    p.addLine(to: CGPoint(x: w / 2, y: h))
                    for f in [1.0 / 3.0, 2.0 / 3.0] {
                        p.move(to: CGPoint(x: 0, y: h * f))
                        p.addLine(to: CGPoint(x: w, y: h * f))
                    }
                }
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

                Path { p in
                    for f in [0.08, 0.94] {
                        p.move(to: CGPoint(x: w * 0.2, y: h * f))
                        p.addLine(to: CGPoint(x: w * 0.8, y: h * f))
                    }
                }
                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)

                Text("HEAD")
                    .position(x: w * 0.12, y: h * 0.08)
                Text("FEET")
                    .position(x: w * 0.12, y: h * 0.94)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white.opacity(0.75))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Capture screen

struct ProgressCameraView: View {
    /// Last photo, shown at ~35% over the live preview.
    let ghost: UIImage?
    var onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ProgressCameraModel()
    @AppStorage("progressPhotos.timer") private var timerSeconds = 3
    @AppStorage("progressPhotos.showGhost") private var showGhost = true
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                topBar
                viewfinder
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            Spacer()
            if ghost != nil && camera.captured == nil {
                Button { showGhost.toggle() } label: {
                    Image(systemName: showGhost ? "person.2.fill" : "person.2")
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(showGhost ? 0.3 : 0.15)))
                }
                .accessibilityLabel(showGhost ? "Hide last week's ghost" : "Show last week's ghost")
            }
            if camera.captured == nil {
                Menu {
                    Picker("Timer", selection: $timerSeconds) {
                        Text("No timer").tag(0)
                        Text("3 seconds").tag(3)
                        Text("10 seconds").tag(10)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(timerSeconds == 0 ? "Off" : "\(timerSeconds)s")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                }
                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .accessibilityLabel("Switch camera")
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.white)
        .padding(.top, 8)
    }

    private var viewfinder: some View {
        Color.black
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { frameContent }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var frameContent: some View {
        ZStack {
            if let shot = camera.captured {
                Image(uiImage: shot)
                    .resizable()
                    .scaledToFill()
            } else {
                switch camera.status {
                case .running, .idle:
                    CameraPreview(session: camera.session)
                    if showGhost, let ghost {
                        Image(uiImage: ghost)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.35)
                            .allowsHitTesting(false)
                    }
                    PoseGuides()
                case .unauthorized:
                    message("Camera access is off", "Turn it on in Settings → Dialed → Camera, or choose a photo from your library instead.")
                case .unavailable:
                    message("No camera available", "Choose a photo from your library instead.")
                }
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(radius: 8)
                        .transition(.scale.combined(with: .opacity))
                        .id(countdown)
                }
            }
        }
    }

    private func message(_ title: String, _ body: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.system(size: 30))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(body)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
        }
        .foregroundColor(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let shot = camera.captured {
            HStack(spacing: 12) {
                Button { camera.captured = nil } label: {
                    Text("Retake")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
                Button {
                    onCapture(shot)
                    dismiss()
                } label: {
                    Text("Use photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white))
                }
            }
            .foregroundColor(.white)
        } else {
            VStack(spacing: 10) {
                Text("Same spot, same light, same pose — Sunday mornings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Button(action: shutter) {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 74, height: 74)
                        Circle().fill(countdown == nil ? Color.white : Neka.rose).frame(width: 60, height: 60)
                    }
                }
                .disabled(camera.status != .running || camera.isCapturing)
                .accessibilityLabel(countdown == nil ? "Take photo" : "Cancel timer")
            }
        }
    }

    private func shutter() {
        if countdown != nil {
            countdownTask?.cancel()
            countdown = nil
            return
        }
        guard timerSeconds > 0 else {
            camera.capture()
            return
        }
        countdownTask = Task { @MainActor in
            for n in stride(from: timerSeconds, to: 0, by: -1) {
                withAnimation(.easeOut(duration: 0.2)) { countdown = n }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            countdown = nil
            camera.capture()
        }
    }
}
