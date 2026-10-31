// CameraPreview.swift — live webcam preview with the 96x96 mouth crop.
//
// AVCaptureSession in an NSViewRepresentable. The mouth crop overlay is a
// 96x96 box centred on the lower face — a placeholder position until the
// MediaPipe FaceLandmarker landmarks arrive from the Python backend
// (src/subvox_local/face.py). The real crop is computed by the backend;
// this overlay only shows the user where to aim their mouth.
//
// UNTESTED ON INTEL MAC: AVCaptureSession, permission prompts, and the
// preview layer have never run on a real Mac in this build. Camera
// permission (NSCameraUsageDescription in Info.plist) is required.

import AVFoundation
import SwiftUI

// MARK: - Camera session (shared, owned by the app)

@MainActor
final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var isRunning = false
    @Published private(set) var authorization: AVAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?

    override init() {
        super.init()
        session.sessionPreset = .hd1280x720
    }

    /// Ask for camera access, then start the session. Call once.
    func requestAndStart() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.authorization = granted ? .authorized : .denied
                    if granted { self?.start() }
                }
            }
        default:
            errorMessage = "Camera access denied. Grant it in System Settings → Privacy & Security → Camera."
        }
    }

    private func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.configure()
                self.session.startRunning()
                Task { @MainActor in self.isRunning = true }
            } catch {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.inputs.isEmpty else { return }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw NSError(domain: "SubvoxLocal", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No camera found on this Mac."])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "SubvoxLocal", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not add the camera to the capture session."])
        }
        session.addInput(input)
    }
}

// MARK: - Preview view

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer as? AVCaptureVideoPreviewLayer {
            layer.session = session
            layer.frame = nsView.bounds
        }
    }
}

// MARK: - Mouth crop overlay
//
// The model reads aligned 96x96 mouth crops at 25 fps
// (see src/subvox_local/capture.py MODEL_FPS and face.py mouth_rois).
// This overlay draws the target crop box. Its position is an estimate
// (lower-centre of frame) until live MediaPipe landmarks are wired in;
// the backend, not this view, computes the real crop.

struct MouthCropOverlay: View {
    /// True while the user is holding the talk key.
    var listening: Bool
    /// Face detected by the backend tracker (nil = no face yet).
    var faceDetected: Bool

    var body: some View {
        GeometryReader { geo in
            // Estimate: mouth sits ~72% down the frame, centred horizontally.
            // Real position comes from MediaPipe landmarks (face.py) — TODO.
            let boxSize: CGFloat = 120
            let x = (geo.size.width - boxSize) / 2
            let y = geo.size.height * 0.72 - boxSize / 2
            ZStack {
                // Dim everything outside the crop: four rectangles around
                // the box (a mask-with-hole does not render reliably).
                Color.black.opacity(0.35)
                    .frame(width: geo.size.width, height: y)
                    .position(x: geo.size.width / 2, y: y / 2)
                Color.black.opacity(0.35)
                    .frame(width: geo.size.width, height: geo.size.height - (y + boxSize))
                    .position(x: geo.size.width / 2, y: y + boxSize + (geo.size.height - (y + boxSize)) / 2)
                Color.black.opacity(0.35)
                    .frame(width: x, height: boxSize)
                    .position(x: x / 2, y: y + boxSize / 2)
                Color.black.opacity(0.35)
                    .frame(width: geo.size.width - (x + boxSize), height: boxSize)
                    .position(x: x + boxSize + (geo.size.width - (x + boxSize)) / 2, y: y + boxSize / 2)
                // The 96x96 crop box (drawn larger for visibility; the
                // model crop itself is 96x96 pixels).
                RoundedRectangle(cornerRadius: 12)
                    .stroke(listening ? Color.dunaPaper : Color.dunaPaper.opacity(0.7),
                            lineWidth: listening ? 3 : 2)
                    .frame(width: boxSize, height: boxSize)
                    .position(x: x + boxSize / 2, y: y + boxSize / 2)
                Text(faceDetected ? "96 × 96 mouth crop" : "No face detected — move into frame")
                    .font(DunaFont.caption(12))
                    .foregroundStyle(Color.dunaPaper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .position(x: geo.size.width / 2, y: y + boxSize + 22)
            }
        }
    }
}
