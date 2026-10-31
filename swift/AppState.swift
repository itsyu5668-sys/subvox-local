// AppState.swift — shared app state for Subvox Local.
//
// Single source of truth for the current tab, license/trial state,
// doctor results, settings, and onboarding progress. The Python backend
// is reached only through BackendBridge; this file holds no model logic.
//
// UNTESTED ON INTEL MAC: never compiled. See swift/README.md.

import SwiftUI

// MARK: - Navigation

enum SubvoxTab: String, CaseIterable, Identifiable {
    case dictate = "Dictate"
    case setup = "Setup"
    case models = "Models"
    case settings = "Settings"

    var id: String { rawValue }
}

// MARK: - Settings (persisted to ~/Library/Application Support/SubvoxLocal/settings.json
// by the Python backend — see src/subvox_local/paths.py SETTINGS. The Swift
// app reads/writes the same file so both sides agree.)

struct SubvoxSettings: Codable {
    /// Cleanup model choice: "qwen-0.6b" or "qwen-1.7b".
    var cleanupModel: String = "qwen-0.6b"
    /// Hotkey: "right-option" (global, needs Input Monitoring) or
    /// "space-h" (hold Space or H while the window is focused).
    var hotkey: String = "right-option"
    /// Paste target: "cursor" (paste at cursor in the focused app) or
    /// "clipboard" (copy only, user pastes manually).
    var pasteTarget: String = "cursor"
    /// Camera index (0 = default FaceTime camera).
    var cameraIndex: Int = 0
    /// Beam size for Auto-AVSR decoding (Python default 10).
    var beamSize: Int = 10
    /// Cleanup backend: "auto" | "local" | "basic" (see app.py `file` command).
    var cleanupBackend: String = "auto"
    /// User-added custom words for the cleanup prompt.
    var customWords: [String] = []
}

// MARK: - App state

@MainActor
final class AppState: ObservableObject {
    /// Train First: the first screen is Setup, not Dictate. Stock
    /// Auto-AVSR is not accurate on a new face — personal LoRA training
    /// is the accuracy fix, so dictation waits until training has run.
    @Published var tab: SubvoxTab = .setup
    @Published var settings = SubvoxSettings()

    /// Has Train First run at least once (setup-fast completed, kept or
    /// not — the decision is in the Setup view's WER report)? Persisted
    /// so Dictate can show a "train first" banner until it has.
    @Published var trainFirstDone: Bool = false

    /// Has the user finished first-launch onboarding?
    @Published var onboardingDone: Bool = false
    /// Show the onboarding sheet on top of the main window.
    @Published var showOnboarding: Bool = false
    /// Show the paywall sheet.
    @Published var showPaywall: Bool = false

    /// Latest `doctor` output, if it has run.
    @Published var doctor: DoctorReport?
    @Published var doctorRunning: Bool = false
    @Published var doctorError: String?

    /// Per-model download progress (0...1) during first-launch download.
    /// Kept for ModelsView rows; the live bar lives in downloadMonitor.
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingModels: Bool = false

    /// Live first-launch download monitor: polls
    /// download-progress.json once a second (MB / total, speed, ETA,
    /// pause / resume). See DownloadProgress.swift.
    let downloadMonitor = DownloadProgressMonitor()

    /// Has the background model download been started this launch?
    /// Guard so onboarding + Models do not start it twice.
    /// NOTE: this is only set AFTER the downloader process has actually
    /// launched. The old code set it first and then silently returned
    /// when the repo could not be found, leaving the button disabled
    /// forever with nothing downloading — the exact "nothing happens"
    /// Francis hit on first launch.
    @Published private(set) var backgroundDownloadStarted = false
    /// Plain-English download failure, shown in the UI (not only in a
    /// log file). Nil when there is no failure to report.
    @Published var downloadError: String?
    /// Auto-retries used after a stall (max 2, then the user retries).
    private var stallRetries = 0
    private var downloadProcess: Process?

    let license = LicenseManager()
    let backend = BackendBridge()

    // MARK: Background model download
    //
    // Runs first_launch_downloader.py in the background (core set only,
    // ~1.62 GB, resumable, SHA-verified) and starts the progress
    // monitor polling. The user goes straight to Train First setup
    // while the download runs, so the perceived wait is zero. The
    // trial clock does NOT start here; it starts on first dictation,
    // after the models are ready (see LicenseManager.startTrial).
    //
    // WHERE THE SCRIPT LIVES (in order — the old code only tried the
    // repo path, which does not exist on a real user's Mac):
    //   1. Inside the .app bundle: Contents/Resources/first_launch_downloader.py
    //      (build_app.sh copies it there). This is the shipped path.
    //   2. Next to the repo: <repo>/packaging/first_launch_downloader.py
    //      (development — running from a checkout).
    //   3. ~/workspace/subvox-local/packaging/… (development fallback).
    func downloaderScriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "first_launch_downloader",
                                         withExtension: "py") {
            return bundled
        }
        if let root = backend.repoRoot {
            let packaged = root.appendingPathComponent("packaging/first_launch_downloader.py")
            if FileManager.default.fileExists(atPath: packaged.path) { return packaged }
        }
        return nil
    }

    /// Application Support folder for this app (models, progress JSON,
    /// pause/cancel files all live here).
    var appSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubvoxLocal")
    }

    /// Are the core models already on disk? Used to decide whether a
    /// download is needed at all (and whether to auto-start one).
    func coreModelsPresent() -> Bool {
        let models = appSupportURL.appendingPathComponent("models")
        for f in ["vsr/model.pth", "vsr/model.json", "lm/model.pth",
                  "lm/model.json", "lm/unigram5000.model", "face_landmarker.task"] {
            let url = models.appendingPathComponent(f)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber, size.intValue > 0
            else { return false }
        }
        return true
    }

    func beginBackgroundDownload() {
        guard !backgroundDownloadStarted else { return }
        downloadError = nil
        guard let script = downloaderScriptURL() else {
            // Loud, plain failure — never a silent no-op. The user can
            // Retry after reinstalling, and the diagnosis script tells
            // them exactly what is missing.
            downloadError = "Could not find the model downloader inside the app. Reinstall Subvox Local from the .dmg, then open it again."
            downloadingModels = false
            return
        }
        downloadingModels = true
        downloadMonitor.startPolling()
        // Stall auto-retry: if the monitor sees no bytes for 60s, kill
        // the stuck downloader and start it again (max 2 times). After
        // that the card shows Retry and waits for the user.
        downloadMonitor.onStalled = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.retryAfterStall() }
        }
        downloadMonitor.onDownloadError = { [weak self] reason in
            guard let self else { return }
            Task { @MainActor in
                self.downloadError = reason.isEmpty ? nil : reason
                self.downloadingModels = false
                self.backgroundDownloadStarted = false
            }
        }
        let modelsDir = appSupportURL.appendingPathComponent("models")
        let progressFile = appSupportURL.appendingPathComponent("download-progress.json")
        let logFile = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/SubvoxLocal/first-launch.log")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Clear any stale cancel flag from a previous launch; a stale
        // pause flag is left alone (the user paused on purpose).
        try? FileManager.default.removeItem(at: appSupportURL.appendingPathComponent("download.cancel"))
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [script.path,
                          "--models-dir", modelsDir.path,
                          "--progress-file", progressFile.path,
                          "--include-qwen-gguf"]
        if let logHandle = try? FileHandle(forWritingTo: logFile) {
            try? logHandle.seekToEnd()
            proc.standardError = logHandle
            proc.standardOutput = logHandle
        }
        do {
            try proc.run()
        } catch {
            downloadError = "Could not start the model download (\(error.localizedDescription)). Check that Python 3 is installed, then tap Retry."
            downloadingModels = false
            downloadMonitor.stopPolling()
            return
        }
        // Only now — the process really launched — mark it started.
        downloadProcess = proc
        backgroundDownloadStarted = true
        DispatchQueue.global(qos: .utility).async {
            proc.waitUntilExit()
            Task { @MainActor in
                self.downloadProcess = nil
                self.downloadingModels = false
                self.downloadMonitor.readOnce()
                if proc.terminationStatus == 0 {
                    self.backgroundDownloadStarted = false
                    self.stallRetries = 0
                    Task { await self.runDoctor() }
                } else if proc.terminationStatus != 2 {
                    // Exit 2 = user cancelled. Anything else is a
                    // failure: keep the Retry path open (reset the
                    // started flag) and surface the reason in the UI.
                    // The downloader already wrote status "error" +
                    // error_message into the progress JSON.
                    self.backgroundDownloadStarted = false
                    if self.downloadError == nil {
                        self.downloadError = "The model download stopped (exit code \(proc.terminationStatus)). Tap Retry — it picks up where it left off."
                    }
                }
            }
        }
    }

    /// Retry after a stall or a failure. Clears the started flag so
    /// beginBackgroundDownload() can run again, and removes the pause
    /// file only when the retry follows a stall (a user pause stays).
    func retryBackgroundDownload() {
        downloadProcess?.terminate()
        downloadProcess = nil
        backgroundDownloadStarted = false
        downloadingModels = false
        downloadError = nil
        beginBackgroundDownload()
    }

    private func retryAfterStall() {
        guard stallRetries < 2 else { return }
        stallRetries += 1
        downloadProcess?.terminate()
        downloadProcess = nil
        backgroundDownloadStarted = false
        downloadingModels = false
        downloadError = "Download stalled, so the app is trying again (attempt \(stallRetries) of 2). Check your wifi."
        beginBackgroundDownload()
    }

    /// First launch: if the core models are missing, start the
    /// download immediately and show the Models tab, so the user sees
    /// a big visible progress window the moment the app opens — instead
    /// of having to find a button on onboarding step 3. Called from
    /// ContentView.onAppear. Safe to call repeatedly; it no-ops once
    /// the download has started or the models are present.
    func autoStartDownloadIfNeeded() {
        guard !coreModelsPresent() else { return }
        if downloadMonitor.progress?.status == "done" { return }
        tab = .models
        beginBackgroundDownload()
    }

    init() {
        loadSettings()
        onboardingDone = UserDefaults.standard.bool(forKey: "subvox.onboardingDone")
        trainFirstDone = UserDefaults.standard.bool(forKey: "subvox.trainFirstDone")
        if !onboardingDone { showOnboarding = true }
        license.refresh()
    }

    /// Mark Train First as run (called by SetupView when setup-fast
    /// finishes — kept or not, the training ran and the WER report exists).
    func finishTrainFirst() {
        trainFirstDone = true
        UserDefaults.standard.set(true, forKey: "subvox.trainFirstDone")
    }

    // MARK: Settings persistence

    private var settingsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubvoxLocal/settings.json")
    }

    func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(SubvoxSettings.self, from: data)
        else { return }
        settings = decoded
    }

    func saveSettings() {
        let url = settingsURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Doctor

    func runDoctor() async {
        doctorRunning = true
        doctorError = nil
        do {
            doctor = try await backend.doctor()
        } catch {
            doctorError = error.localizedDescription
        }
        doctorRunning = false
    }

    func finishOnboarding() {
        onboardingDone = true
        UserDefaults.standard.set(true, forKey: "subvox.onboardingDone")
        showOnboarding = false
    }
}
