// BackendBridge.swift — Swift <-> Python bridge for Subvox Local.
//
// The Python backend does ALL lip reading. This file only launches it as a
// subprocess (`uv run python -m subvox_local <command>`) and parses its
// JSON output. It contains no model code and no network calls of its own,
// except the one-time model download (see ModelDownloader in ModelsView).
//
// Real CLI surface (src/subvox_local/app.py — do not invent commands):
//   doctor                          -> JSON map of model checks
//   setup-fast [--camera N] [--dry-run]
//   adapt-more [--camera N] [--steps 150] [--dry-run]
//   train-lm
//   import-text <path>
//   import-wispr
//   file <path> [--beam 10] [--cleanup auto|local|basic]
//
// UNTESTED ON INTEL MAC: never run. Process launching, JSON parsing, and
// the dictation session protocol below all need a real Intel Mac + Xcode.

import Foundation

// MARK: - Errors

enum BackendError: LocalizedError {
    case pythonNotFound
    case commandFailed(exitCode: Int32, stderr: String)
    case badOutput(String)
    case dictationServeMissing

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Could not find `uv` or `python3`. Run ./setup_macos.sh first."
        case .commandFailed(let code, let stderr):
            return "Backend exited with code \(code): \(stderr)"
        case .badOutput(let detail):
            return "Backend output was not parseable JSON: \(detail)"
        case .dictationServeMissing:
            return "Live dictation needs a Python JSON-lines mode that does not exist yet (see DictationSession note)."
        }
    }
}

// MARK: - Doctor report
//
// `doctor` prints one JSON object: label -> status string, e.g.
//   "vsr/model.pth": "ok, 1001.9 MB"   or   "MISSING — run: bash scripts/download-models.sh"
// plus "platform", "python", "torch", "mps_available", "cuda_available",
// "mlx_lm". On an Intel Mac, expect torch CPU, mps_available false,
// mlx_lm not importable — that is normal, not an error.

struct DoctorReport: Identifiable {
    let id = UUID()
    let raw: [String: String]
    let date = Date()

    var platform: String? { raw["platform"] }
    var pythonVersion: String? { raw["python"] }
    var torchVersion: String? { raw["torch"] }
    var mpsAvailable: String? { raw["mps_available"] }
    var cudaAvailable: String? { raw["cuda_available"] }
    var mlxStatus: String? { raw["mlx_lm"] }

    /// Model file labels only (excludes platform/python/torch keys).
    var modelChecks: [(label: String, status: String)] {
        raw.filter { !$0.key.hasPrefix("platform") && $0.key != "python"
            && $0.key != "torch" && $0.key != "mps_available"
            && $0.key != "cuda_available" && $0.key != "mlx_lm" }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var missingCount: Int {
        modelChecks.filter { $0.status.hasPrefix("MISSING") }.count
    }

    var allModelsPresent: Bool { missingCount == 0 }
}

// MARK: - Bridge

@MainActor
final class BackendBridge: ObservableObject {
    /// Repo root: the folder that contains setup_macos.sh. The .app bundle
    /// is expected to live next to the repo during development; a shipped
    /// .app must embed or locate the Python backend — see swift/README.md.
    var repoRoot: URL? {
        // During development: ~/workspace/subvox-local. The .app looks for
        // a `subvox-local` folder next to itself, then falls back to the
        // user's home workspace. Neither is guaranteed — doctor will fail
        // loudly if the backend is not found, which is the honest behavior.
        let fm = FileManager.default
        if let appURL = Bundle.main.bundleURL as URL? {
            let nextToApp = appURL.deletingLastPathComponent()
                .appendingPathComponent("subvox-local")
            if fm.fileExists(atPath: nextToApp.appendingPathComponent("setup_macos.sh").path) {
                return nextToApp
            }
        }
        let home = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("workspace/subvox-local")
        if fm.fileExists(atPath: home.appendingPathComponent("setup_macos.sh").path) {
            return home
        }
        return nil
    }

    /// Run `uv run python -m subvox_local <args...>` in the repo root.
    /// Returns (stdout, stderr, exitCode). Never blocks the main thread.
    func runBackend(_ args: [String]) async throws -> (stdout: String, stderr: String, code: Int32) {
        guard let root = repoRoot else { throw BackendError.pythonNotFound }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["uv", "run", "python", "-m", "subvox_local"] + args
                proc.currentDirectoryURL = root
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: BackendError.pythonNotFound)
                    return
                }
                proc.waitUntilExit()
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: (out, err, proc.terminationStatus))
            }
        }
    }

    /// `doctor` — check models, camera, platform. No inference.
    func doctor() async throws -> DoctorReport {
        let (out, err, code) = try await runBackend(["doctor"])
        guard code == 0 else {
            throw BackendError.commandFailed(exitCode: code, stderr: err)
        }
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            throw BackendError.badOutput(out)
        }
        return DoctorReport(raw: json)
    }

    /// `setup-fast --dry-run` — lists the 6 sentences, no camera, no training.
    func setupFastDryRun() async throws -> String {
        let (out, err, code) = try await runBackend(["setup-fast", "--dry-run"])
        guard code == 0 else {
            throw BackendError.commandFailed(exitCode: code, stderr: err)
        }
        return out
    }

    /// `train-lm` — train the personal LM on phrases.txt. Returns the JSON report.
    func trainLM() async throws -> String {
        let (out, err, code) = try await runBackend(["train-lm"])
        guard code == 0 else {
            throw BackendError.commandFailed(exitCode: code, stderr: err)
        }
        return out
    }

    /// `import-text <path>` — add a .txt file to phrases.txt.
    func importText(_ path: String) async throws -> String {
        let (out, err, code) = try await runBackend(["import-text", path])
        guard code == 0 else {
            throw BackendError.commandFailed(exitCode: code, stderr: err)
        }
        return out
    }

    /// `import-wispr` — import Wispr Flow history (macOS, local read-only).
    func importWispr() async throws -> String {
        let (out, err, code) = try await runBackend(["import-wispr"])
        guard code == 0 else {
            throw BackendError.commandFailed(exitCode: code, stderr: err)
        }
        return out
    }

    /// `file <path> --beam N --cleanup <backend>` — lip-read a video file.
    /// Used for testing on the Mac without holding the hotkey.
    func lipReadFile(_ path: String, beam: Int, cleanup: String) async throws -> String {
        let (out, err, code) = try await runBackend(
            ["file", path, "--beam", "\(beam)", "--cleanup", cleanup]
        )
        guard code == 0 else {
            throw BackendError.commandFailed(exitCode: code, stderr: err)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Live dictation session (NOT YET WIRED)
//
// The Python CLI today has no streaming dictation command: `dictation.py`
// exposes Dictation.dictate_once() (record -> decode -> cleanup -> paste)
// and the CLI `file` command, but nothing that emits JSON lines while a
// key is held. The Swift UI below is built for a session that does not
// exist yet on the Python side.
//
// Until the Python side gains a `dictation-serve` (or equivalent) entry
// point that prints one JSON object per event —
//   {"event":"hypothesis","text":"...","rank":1}
//   {"event":"cleaned","text":"..."}
//   {"event":"pasted","text":"..."}
// — live dictation in this app is a UI shell around the camera preview
// plus the `file` test path. Do NOT fake live transcripts. When the
// session starts and the backend is missing, it fails loudly with
// BackendError.dictationServeMissing instead of inventing output.

@MainActor
final class DictationSession: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case decoding
        case done(text: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Raw top-3 beam hypotheses, best first. Empty until the backend sends them.
    @Published var hypotheses: [String] = []
    /// The cleaned sentence chosen by Qwen GGUF (or basic rules fallback).
    @Published var cleanedText: String = ""
    /// Raw VSR line (best hypothesis, uppercase, before cleanup).
    @Published var rawText: String = ""

    private var process: Process?

    func startListening() {
        // Camera preview is driven by CameraPreview (AVCaptureSession).
        // Decoding starts here once the Python streaming entry point exists.
        state = .failed(BackendError.dictationServeMissing.localizedDescription)
    }

    func stopListening() {
        process?.terminate()
        process = nil
        if state == .listening { state = .idle }
    }

    /// User picked a different hypothesis than the cleaned winner.
    /// The pick is recorded as a correction for stage-2 adapt
    /// (see src/subvox_local/corrections.py on the Python side).
    func selectHypothesis(_ text: String) {
        cleanedText = text
    }
}
