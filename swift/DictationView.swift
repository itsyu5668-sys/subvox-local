// DictationView.swift — the main dictation workspace.
//
// Hold a key, silently mouth words at the webcam, text appears at your
// cursor in any app. Pipeline (all local):
//   Camera -> MediaPipe -> Auto-AVSR (PyTorch CPU) -> Qwen GGUF -> Paste
//
// Honest latency: this Mac is an Intel Core i5. Auto-AVSR runs on PyTorch
// CPU here, which is slower than the M4 GPU numbers in Lipflow's docs.
// This view shows NO latency numbers until they are measured on this Mac
// — every readout starts as "not measured yet".
//
// UNTESTED ON INTEL MAC: camera, hotkey, paste, and the live decode loop
// have never run. The decode loop needs the Python streaming entry point
// described in BackendBridge.swift (DictationSession).

import SwiftUI
import AppKit

// MARK: - Hotkey manager
//
// Two hotkeys, two mechanisms:
//  * Hold Space or H — local NSEvent monitor, works while the Subvox
//    window is focused. No special permission needed.
//  * Hold Right Option — global CGEventTap, works in any app. Needs
//    Input Monitoring permission (see OnboardingView) and Accessibility
//    for the paste step. UNTESTED: CGEventTap behaviour on this Mac is
//    unverified; if the tap fails, the app falls back to Space/H and says so.

@MainActor
final class HotkeyManager: ObservableObject {
    @Published private(set) var isHoldingTalkKey = false
    @Published private(set) var rightOptionAvailable = false
    @Published private(set) var rightOptionError: String?

    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?

    /// Start the local Space/H monitor. Always available.
    func startLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            // Space = 49, H = 4. Ignore repeats and events with modifiers
            // other than the key itself (so Cmd+Space / Spotlight still works).
            guard (event.keyCode == 49 || event.keyCode == 4),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            else { return event }
            Task { @MainActor in
                if event.type == .keyDown, !event.isARepeat, !self.isHoldingTalkKey {
                    self.isHoldingTalkKey = true
                    self.onHoldStart?()
                } else if event.type == .keyUp, self.isHoldingTalkKey {
                    self.isHoldingTalkKey = false
                    self.onHoldEnd?()
                }
            }
            // Swallow the key while dictating so it does not type spaces
            // into the paste target field.
            return nil
        }
    }

    /// Try to install the global Right Option tap. Fails gracefully.
    func startRightOptionTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                // Right Option = keyCode 61. The callback runs on a
                // background thread; state is forwarded on the main actor.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let type = event.type
                if keyCode == 61 {
                    Task { @MainActor in
                        HotkeyManager.shared?.handleRightOption(type: type)
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            rightOptionError = "Right Option tap could not be created. Grant Input Monitoring in System Settings, then restart. Space / H still work while this window is focused."
            rightOptionAvailable = false
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        rightOptionAvailable = true
    }

    private func handleRightOption(type: CGEventType) {
        if type == .keyDown, !isHoldingTalkKey {
            isHoldingTalkKey = true
            onHoldStart?()
        } else if type == .keyUp, isHoldingTalkKey {
            isHoldingTalkKey = false
            onHoldEnd?()
        }
    }

    func stop() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }

    // Weak-shared access for the C callback (the callback cannot capture
    // the @MainActor instance directly).
    static weak var shared: HotkeyManager?
}

// MARK: - Paste helper (paste at cursor in the focused app)

enum PasteHelper {
    /// Copy text to the clipboard, then send Cmd+V via CGEvent so it lands
    /// at the cursor in whatever app has focus. Needs Accessibility
    /// permission. UNTESTED on this Mac.
    static func pasteAtCursor(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return false }
        guard let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        else { return false }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        return true
    }

    /// Copy-only mode: text goes to the clipboard, user pastes manually.
    static func copyOnly(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Dictation view

struct DictationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var camera = CameraSession()
    @StateObject private var hotkeys = HotkeyManager()
    @StateObject private var session = DictationSession()

    @State private var pasteTargetText: String = ""
    @State private var selectedHypothesis: Int = 0
    @State private var showingFileTest = false

    // Measured-on-this-Mac numbers. Nil = not measured yet; the UI shows
    // "not measured yet" instead of inventing a number. Set these only
    // after running the Mac test steps in docs/FAST_SETUP_PLAN.md.
    @State private var measuredDecodeSeconds: Double?
    @State private var measuredCleanupSeconds: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LicenseBlockerBanner()

                header
                pipelineStrip
                HStack(alignment: .top, spacing: 24) {
                    cameraCard
                    transcriptCard
                }
                holdToTalkRow
                statusRow
            }
            .frame(maxWidth: DunaLayout.pageMaxWidth)
            .padding(32)
        }
        .background(Color.dunaLinen)
        .onAppear {
            camera.requestAndStart()
            HotkeyManager.shared = hotkeys
            hotkeys.startLocalMonitor()
            if appState.settings.hotkey == "right-option" {
                hotkeys.startRightOptionTap()
            }
            hotkeys.onHoldStart = { session.startListening() }
            hotkeys.onHoldEnd = {
                session.stopListening()
                // The backend keeps filming 0.4 s of trailing frames after
                // release (TAIL_SECONDS in capture.py) before decoding.
            }
            if appState.doctor == nil {
                Task { await appState.runDoctor() }
            }
        }
        .onDisappear {
            hotkeys.stop()
            camera.stop()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dictate")
                    .font(DunaFont.display(48))
                    .foregroundStyle(Color.dunaInk)
                Text("Hold a key. Mouth the words. Text appears at your cursor.")
                    .font(DunaFont.body(17))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
            Spacer()
            LocalOnlyBadge()
        }
    }

    // MARK: Pipeline strip

    private var pipelineStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(pipelineSteps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text(step.name)
                            .font(DunaFont.headline(13))
                            .foregroundStyle(Color.dunaInk)
                        Text(step.detail)
                            .font(DunaFont.caption(11))
                            .foregroundStyle(Color.dunaStone)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    if index < pipelineSteps.count - 1 {
                        Text("→")
                            .font(DunaFont.caption(13))
                            .foregroundStyle(Color.dunaStone)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.dunaPaper)
        .clipShape(RoundedRectangle(cornerRadius: DunaLayout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DunaLayout.cardRadius)
                .stroke(Color.dunaRing, lineWidth: 1)
        )
    }

    private var pipelineSteps: [(name: String, detail: String)] {
        [
            ("Camera", "1280×720"),
            ("MediaPipe", "FaceLandmarker"),
            ("Auto-AVSR", "PyTorch CPU"),
            ("Qwen GGUF", "cleanup"),
            ("Paste", "at cursor"),
        ]
    }

    // MARK: Camera card

    private var cameraCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Camera")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                ZStack {
                    RoundedRectangle(cornerRadius: DunaLayout.imageRadius)
                        .fill(Color.dunaSmoke)
                        .aspectRatio(16 / 9, contentMode: .fit)
                    if camera.isRunning {
                        CameraPreviewView(session: camera.session)
                            .clipShape(RoundedRectangle(cornerRadius: DunaLayout.imageRadius))
                        MouthCropOverlay(
                            listening: hotkeys.isHoldingTalkKey,
                            faceDetected: true // TODO: wire to MediaPipe landmarks from the backend
                        )
                    } else {
                        VStack(spacing: 8) {
                            Text("Camera not running")
                                .font(DunaFont.headline(15))
                                .foregroundStyle(Color.dunaPaper)
                            Text(camera.errorMessage ?? "Grant Camera permission to start.")
                                .font(DunaFont.body(13))
                                .foregroundStyle(Color.dunaPaper.opacity(0.7))
                                .multilineTextAlignment(.center)
                            Button("Start camera") { camera.requestAndStart() }
                                .buttonStyle(DunaSecondaryButtonStyle())
                        }
                        .padding()
                    }
                }
                Text("Aim your mouth at the box. The model reads 96×96 crops at 25 fps. No video is saved — only mouth crops during practice rounds.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Transcript card

    private var transcriptCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transcript")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)

                // Live transcript (cleaned).
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLEANED — READY TO PASTE")
                        .font(DunaFont.caption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.dunaStone)
                    Text(session.cleanedText.isEmpty ? "Nothing dictated yet." : session.cleanedText)
                        .font(DunaFont.body(17))
                        .foregroundStyle(session.cleanedText.isEmpty ? Color.dunaStone : Color.dunaInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.dunaMist)
                        .clipShape(RoundedRectangle(cornerRadius: DunaLayout.inputRadius))
                }

                // Raw VSR line.
                VStack(alignment: .leading, spacing: 6) {
                    Text("RAW VSR — BEFORE CLEANUP")
                        .font(DunaFont.caption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.dunaStone)
                    Text(session.rawText.isEmpty ? "—" : session.rawText)
                        .font(DunaFont.mono(13))
                        .foregroundStyle(Color.dunaGraphite)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Top-3 hypotheses, selectable.
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOP 3 — TAP TO PICK A DIFFERENT GUESS")
                        .font(DunaFont.caption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.dunaStone)
                    if session.hypotheses.isEmpty {
                        Text("No hypotheses yet. Dictate something first.")
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaStone)
                    } else {
                        ForEach(Array(session.hypotheses.enumerated()), id: \.offset) { index, hyp in
                            Button {
                                selectedHypothesis = index
                                session.selectHypothesis(hyp)
                                pasteTargetText = hyp
                            } label: {
                                HStack {
                                    Text("\(index + 1)")
                                        .font(DunaFont.mono(13))
                                        .foregroundStyle(Color.dunaStone)
                                    Text(hyp)
                                        .font(DunaFont.body(15))
                                        .foregroundStyle(Color.dunaInk)
                                    Spacer()
                                    if index == selectedHypothesis {
                                        Text("SELECTED")
                                            .font(DunaFont.caption(11))
                                            .tracking(1.0)
                                            .foregroundStyle(Color.dunaInk)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(index == selectedHypothesis ? Color.dunaBone : Color.dunaMist)
                                .clipShape(RoundedRectangle(cornerRadius: DunaLayout.inputRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Paste target field.
                VStack(alignment: .leading, spacing: 6) {
                    Text("PASTE TARGET — EDIT BEFORE PASTING")
                        .font(DunaFont.caption(11))
                        .tracking(1.2)
                        .foregroundStyle(Color.dunaStone)
                    TextField("Cleaned text appears here", text: $pasteTargetText)
                        .textFieldStyle(DunaTextFieldStyle())
                    HStack(spacing: 12) {
                        Button("Paste at cursor") {
                            let text = pasteTargetText.isEmpty ? session.cleanedText : pasteTargetText
                            guard !text.isEmpty else { return }
                            if appState.settings.pasteTarget == "clipboard" {
                                _ = PasteHelper.copyOnly(text)
                            } else {
                                _ = PasteHelper.pasteAtCursor(text)
                            }
                        }
                        .buttonStyle(DunaPrimaryButtonStyle())
                        .disabled(pasteTargetText.isEmpty && session.cleanedText.isEmpty)
                        Button("Copy only") {
                            let text = pasteTargetText.isEmpty ? session.cleanedText : pasteTargetText
                            guard !text.isEmpty else { return }
                            _ = PasteHelper.copyOnly(text)
                        }
                        .buttonStyle(DunaSecondaryButtonStyle())
                    }
                }

                // File test path (uses the real `file` CLI command).
                Button("Test a video file instead…") { showingFileTest = true }
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingFileTest) {
            FileTestSheet()
                .environmentObject(appState)
        }
    }

    // MARK: Hold-to-talk

    private var holdToTalkRow: some View {
        DunaCard {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    // Big hold button (pointer hold also works).
                    Button {
                        // Click = one quick dictation attempt; holding the
                        // key is the real flow. Kept as a button so the
                        // workspace is usable without the hotkey.
                        session.startListening()
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(hotkeys.isHoldingTalkKey ? Color.dunaPaper : Color.dunaInk)
                                .frame(width: 10, height: 10)
                            Text(hotkeys.isHoldingTalkKey ? "Listening — release to decode" : "Hold to talk")
                                .font(DunaFont.headline(17))
                        }
                    }
                    .buttonStyle(DunaPrimaryButtonStyle(large: true))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in session.startListening() }
                            .onEnded { _ in session.stopListening() }
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hold Space or H while this window is focused.")
                            .font(DunaFont.body(14))
                            .foregroundStyle(Color.dunaInk)
                        Text("Hold Right Option anywhere on the Mac — needs Input Monitoring permission.")
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaWarmAsh)
                        if let err = hotkeys.rightOptionError {
                            Text(err)
                                .font(DunaFont.body(13))
                                .foregroundStyle(Color.dunaWarmAsh)
                        }
                    }
                    Spacer()
                }
                if case .failed(let message) = session.state {
                    Text(message)
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Status / latency

    private var statusRow: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Status")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                HStack(spacing: 32) {
                    statusItem(
                        label: "BACKEND",
                        value: appState.doctor == nil ? "doctor not run yet"
                            : appState.doctor!.allModelsPresent ? "models ready" : "\(appState.doctor!.missingCount) model(s) missing"
                    )
                    statusItem(
                        label: "ENGINE",
                        value: "Auto-AVSR · PyTorch CPU · Intel Core i5"
                    )
                    statusItem(
                        label: "DECODE TIME",
                        value: measuredDecodeSeconds.map { String(format: "%.1f s", $0) } ?? "not measured yet"
                    )
                    statusItem(
                        label: "CLEANUP TIME",
                        value: measuredCleanupSeconds.map { String(format: "%.1f s", $0) } ?? "not measured yet"
                    )
                }
                Text("Intel CPU is slower than the M4 GPU numbers in Lipflow's docs. No latency is shown here until it is measured on this Mac — see the test steps in docs/FAST_SETUP_PLAN.md.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    private func statusItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DunaFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(Color.dunaStone)
            Text(value)
                .font(DunaFont.body(14))
                .foregroundStyle(Color.dunaInk)
        }
    }
}

// MARK: - File test sheet (real `file` CLI command)

struct FileTestSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var videoPath: String = ""
    @State private var result: String?
    @State private var running = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Lip-read a video file")
                .font(DunaFont.title(24))
                .foregroundStyle(Color.dunaInk)
            Text("Runs: subvox-local file <path> --beam <n> --cleanup <backend>. No camera needed. Good for testing on the Mac.")
                .font(DunaFont.body(14))
                .foregroundStyle(Color.dunaWarmAsh)
            HStack(spacing: 12) {
                TextField("/path/to/talk.mp4", text: $videoPath)
                    .textFieldStyle(DunaTextFieldStyle())
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        videoPath = url.path
                    }
                }
                .buttonStyle(DunaSecondaryButtonStyle())
            }
            if let result {
                Text(result)
                    .font(DunaFont.body(15))
                    .foregroundStyle(Color.dunaInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dunaMist)
                    .clipShape(RoundedRectangle(cornerRadius: DunaLayout.inputRadius))
            }
            if let error {
                Text(error)
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(DunaSecondaryButtonStyle())
                Button(running ? "Running…" : "Lip-read file") {
                    Task {
                        running = true
                        error = nil
                        result = nil
                        do {
                            result = try await appState.backend.lipReadFile(
                                videoPath,
                                beam: appState.settings.beamSize,
                                cleanup: appState.settings.cleanupBackend
                            )
                        } catch {
                            self.error = error.localizedDescription
                        }
                        running = false
                    }
                }
                .buttonStyle(DunaPrimaryButtonStyle())
                .disabled(videoPath.isEmpty || running)
            }
        }
        .padding(32)
        .frame(width: 560)
        .background(Color.dunaLinen)
    }
}
