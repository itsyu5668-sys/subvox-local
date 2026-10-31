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
    @Published var tab: SubvoxTab = .dictate
    @Published var settings = SubvoxSettings()

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
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadingModels: Bool = false

    let license = LicenseManager()
    let backend = BackendBridge()

    init() {
        loadSettings()
        onboardingDone = UserDefaults.standard.bool(forKey: "subvox.onboardingDone")
        if !onboardingDone { showOnboarding = true }
        license.refresh()
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
