//
//  MotionTilt.swift
//  Dialed
//
//  Tilts a view a few degrees with the phone, so the Dialed mark sits like
//  a physical knob under glass — the same feel as iOS 26's Liquid Glass
//  highlights. Off with Reduce Motion, and the motion updates only run
//  while a tilting view is on screen.
//

import SwiftUI
import CoreMotion

@MainActor
final class DeviceTilt: ObservableObject {
    static let shared = DeviceTilt()

    /// -1…1 left/right and forward/back, smoothed.
    @Published private(set) var x: Double = 0
    @Published private(set) var y: Double = 0

    private let manager = CMMotionManager()
    private var users = 0
    private var rest: (pitch: Double, roll: Double)?

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let a = motion?.attitude else { return }
            // Tilt relative to however the phone was held when it started.
            let r = self.rest ?? (a.pitch, a.roll)
            self.rest = r
            let tx = max(-1, min(1, (a.roll - r.roll) / 0.5))
            let ty = max(-1, min(1, (a.pitch - r.pitch) / 0.5))
            self.x += (tx - self.x) * 0.2
            self.y += (ty - self.y) * 0.2
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        rest = nil
        x = 0
        y = 0
    }
}

private struct MotionTiltModifier: ViewModifier {
    var degrees: Double
    @ObservedObject private var tilt = DeviceTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(reduceMotion ? 0 : tilt.x * degrees), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -tilt.y * degrees), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .onAppear { if !reduceMotion { tilt.start() } }
            .onDisappear { if !reduceMotion { tilt.stop() } }
    }
}

extension View {
    /// Tilts with the phone by up to `degrees`.
    func motionTilt(_ degrees: Double = 10) -> some View {
        modifier(MotionTiltModifier(degrees: degrees))
    }
}
