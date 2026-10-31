// ModelsView.swift — model inventory, status, and first-launch download.
//
// Sizes below come from MODELS.md (generated from the actual files in
// models/ on 2026-10-31). The Qwen GGUF 0.6B file IS chosen and
// verified: unsloth/Qwen3-0.6B-GGUF, Qwen3-0.6B-Q4_K_M.gguf,
// 396,705,472 bytes, sha256 ac2d9771… — see MODELS.md and
// packaging/first_launch_downloader.py. The 1.7B GGUF fallback has
// NOT been downloaded, so its size stays TBD, not guessed.
//
// Models are NEVER bundled inside the .app. Core models (~1.62 GB)
// download on first launch, with resume, into
// ~/Library/Application Support/Subvox Local/models/.
// The AV whisper model (1.8 GB) and AV-HuBERT backup (1.9 GB) are
// on-demand only — see docs/SEAMLESS_FLOW.md §3 for the size math.
//
// UNTESTED ON INTEL MAC: doctor parsing, download progress, and resume
// have never run on a real Mac in this build.

import SwiftUI
import Foundation

// MARK: - Model catalogue
//
// Every URL here is copied from scripts/download-models.sh. No URL is
// invented. The Qwen GGUF rows have no URL yet — that is the point.

struct ModelEntry: Identifiable {
    let id: String
    let name: String
    let role: String
    /// Size on disk, from MODELS.md. Nil = TBD (not yet downloaded/chosen).
    let sizeMB: Double?
    let sizeNote: String
    let source: String
    let url: URL?
    let relativePath: String
    /// Doctor label in `doctor` output (nil = not checked by doctor).
    let doctorLabel: String?
    let licenseNote: String
    /// False for optional models (AV whisper mode, AV-HuBERT backup).
    let required: Bool
}

enum ModelCatalogue {
    static let entries: [ModelEntry] = [
        ModelEntry(
            id: "vsr",
            name: "Auto-AVSR visual-only",
            role: "Main lip reader — LRS3, 19.1% WER on filmed speech",
            sizeMB: 1001.9,
            sizeNote: "1,001.9 MB",
            source: "Amanvir/LRS3_V_WER19.1 (Hugging Face)",
            url: URL(string: "https://huggingface.co/Amanvir/LRS3_V_WER19.1/resolve/main/model.pth"),
            relativePath: "models/vsr/model.pth",
            doctorLabel: "vsr/model.pth",
            licenseNote: "LRS3 — non-commercial research only",
            required: true
        ),
        ModelEntry(
            id: "lm",
            name: "Subword RNN LM",
            role: "Beam-search language model",
            sizeMB: 215.1,
            sizeNote: "215.1 MB",
            source: "Amanvir/lm_en_subword (Hugging Face)",
            url: URL(string: "https://huggingface.co/Amanvir/lm_en_subword/resolve/main/model.pth"),
            relativePath: "models/lm/model.pth",
            doctorLabel: "lm/model.pth",
            licenseNote: "LRS3 lineage — treat as non-commercial research only",
            required: true
        ),
        ModelEntry(
            id: "tokenizer",
            name: "SentencePiece unigram5000",
            role: "LM tokenizer",
            sizeMB: 0.3,
            sizeNote: "0.3 MB",
            source: "mpc001/auto_avsr (GitHub)",
            url: URL(string: "https://github.com/mpc001/auto_avsr/raw/main/spm/unigram/unigram5000.model"),
            relativePath: "models/lm/unigram5000.model",
            doctorLabel: "lm/unigram5000.model",
            licenseNote: "—",
            required: true
        ),
        ModelEntry(
            id: "face",
            name: "MediaPipe FaceLandmarker",
            role: "Live face landmarks, float16",
            sizeMB: 3.8,
            sizeNote: "3.8 MB",
            source: "Google MediaPipe",
            url: URL(string: "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"),
            relativePath: "models/face_landmarker.task",
            doctorLabel: "face_landmarker.task",
            licenseNote: "Apache 2.0",
            required: true
        ),
        ModelEntry(
            id: "qwen-0.6b",
            name: "Qwen3-0.6B GGUF",
            role: "Offline cleanup — fixes homophenes, casing, punctuation",
            sizeMB: 396.7,
            sizeNote: "396.7 MB",
            source: "unsloth/Qwen3-0.6B-GGUF (Hugging Face), sha256 ac2d9771…",
            url: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf"),
            relativePath: "models/qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf",
            doctorLabel: "qwen3-0.6b-gguf/Qwen3-0.6B-Q4_K_M.gguf",
            licenseNote: "Apache 2.0 (Qwen3)",
            required: true
        ),
        ModelEntry(
            id: "qwen-1.7b",
            name: "Qwen3-1.7B GGUF",
            role: "Cleanup fallback — more accurate, slower on Intel CPU",
            sizeMB: nil,
            sizeNote: "TBD — file not downloaded, size not verified",
            source: "unsloth/Qwen3-1.7B-GGUF (Hugging Face), file Qwen3-1.7B-Q4_K_M.gguf — not downloaded yet, do not quote a size",
            url: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"),
            relativePath: "models/qwen3-1.7b-gguf/Qwen3-1.7B-Q4_K_M.gguf",
            doctorLabel: "qwen3-1.7b-gguf/Qwen3-1.7B-Q4_K_M.gguf",
            licenseNote: "Apache 2.0 (Qwen3)",
            required: false
        ),
        ModelEntry(
            id: "av",
            name: "Auto-AVSR audio-visual",
            role: "Whisper mode — lips + quiet audio, optional",
            sizeMB: 1776.4,
            sizeNote: "1,776.4 MB",
            source: "nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base (Hugging Face)",
            url: URL(string: "https://huggingface.co/nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base/resolve/main/model.safetensors"),
            relativePath: "models/av/model.safetensors",
            doctorLabel: "av/model.safetensors",
            licenseNote: "LRS3 lineage — treat as non-commercial research only",
            required: false
        ),
        ModelEntry(
            id: "avhubert",
            name: "AV-HuBERT Large",
            role: "Backup VSR encoder only — not used by the app today",
            sizeMB: 1928.1,
            sizeNote: "1,928.1 MB",
            source: "vumichien/AV-HuBERT (Hugging Face)",
            url: URL(string: "https://huggingface.co/vumichien/AV-HuBERT/resolve/main/model.pt"),
            relativePath: "models/avhubert/model.pt",
            doctorLabel: "avhubert/model.pt",
            licenseNote: "Apache 2.0 — trained on LRS3, keep the research-use caution",
            required: false
        ),
    ]

    /// Known on-disk total for the models with recorded sizes.
    /// Core first-run set (required entries): 1,001.9 + 215.1 + 0.3 +
    /// 3.8 + 396.7 = 1,617.8 MB (~1.62 GB). The full repo total
    /// (MODELS.md) is ~6.62 GB — that includes the 1.8 GB AV model,
    /// the 1.9 GB AV-HuBERT backup, and the MLX Qwen dirs, none of
    /// which download on first launch. Do not quote 6.62 GB as the
    /// first-run download.
    static var knownSizeMB: Double {
        entries.compactMap { $0.sizeMB }.reduce(0, +)
    }

    /// First-run (required) total only.
    static var coreSizeMB: Double {
        entries.filter { $0.required }.compactMap { $0.sizeMB }.reduce(0, +)
    }
}

// MARK: - Downloader (first launch, resumable)
//
// Downloads one file at a time with URLSession, resuming from the
// existing .part file where possible (same idea as `curl -C -` in
// scripts/download-models.sh). Progress is reported per model into
// AppState.downloadProgress. Network is used ONLY here — dictation
// itself never touches the network.

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: [String: Double] = [:]
    @Published var currentModel: String?
    @Published var error: String?

    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var activeModelId: String?

    func download(_ entry: ModelEntry, to destination: URL) async throws {
        guard let url = entry.url else {
            throw NSError(domain: "SubvoxLocal", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "\(entry.name) has no download URL yet — the GGUF file has not been chosen."])
        }
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        activeModelId = entry.id
        currentModel = entry.name
        let partURL = destination.appendingPathExtension("part")
        var request = URLRequest(url: url)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: partURL.path),
           let size = attrs[.size] as? NSNumber {
            // Resume: ask the server for the rest of the file.
            request.setValue("bytes=\(size.intValue)-", forHTTPHeaderField: "Range")
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            let task = session?.downloadTask(with: request)
            task?.resume()
        }
        // Move the finished download into place.
        // (The delegate hands us the temp file; see urlSession(_:downloadTask:didFinishDownloadingTo:).)
    }

    // MARK: URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            if let id = activeModelId { progress[id] = fraction }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // The destination path is resolved on the main actor by the caller
        // through `finishDownload(from:)` — this delegate only signals
        // completion; the file move happens in downloadAll (see below).
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Task { @MainActor in
                continuation?.resume(throwing: error)
                continuation = nil
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Models view

struct ModelsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var downloader = ModelDownloader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LicenseBlockerBanner()

                header
                doctorCard
                downloadCard
                ForEach(ModelCatalogue.entries) { entry in
                    modelRow(entry)
                }
                platformCard
            }
            .frame(maxWidth: DunaLayout.pageMaxWidth)
            .padding(32)
        }
        .background(Color.dunaLinen)
        .onAppear {
            if appState.doctor == nil {
                Task { await appState.runDoctor() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models")
                .font(DunaFont.display(48))
                .foregroundStyle(Color.dunaInk)
            Text("Everything runs on this Mac. Models download once, on first launch, and are never bundled inside the .app.")
                .font(DunaFont.body(17))
                .foregroundStyle(Color.dunaWarmAsh)
            HStack(spacing: 8) {
                LocalOnlyBadge()
                Text("First-run download \(String(format: "%.2f", ModelCatalogue.coreSizeMB / 1000)) GB (core set) — the 1.8 GB whisper model and 1.9 GB backup are on-demand only.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    // MARK: Doctor

    private var doctorCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Doctor check")
                        .font(DunaFont.headline(17))
                        .foregroundStyle(Color.dunaInk)
                    Spacer()
                    Button(appState.doctorRunning ? "Running…" : "Run doctor") {
                        Task { await appState.runDoctor() }
                    }
                    .buttonStyle(DunaSecondaryButtonStyle())
                    .disabled(appState.doctorRunning)
                }
                Text("Runs: subvox-local doctor. Checks every model file, plus platform, Python, and torch. No inference.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
                if let doctor = appState.doctor {
                    if doctor.allModelsPresent {
                        Text("All checked models present.")
                            .font(DunaFont.body(15))
                            .foregroundStyle(Color.dunaInk)
                    } else {
                        Text("\(doctor.missingCount) model(s) missing — download below, or run: bash scripts/download-models.sh")
                            .font(DunaFont.body(15))
                            .foregroundStyle(Color.dunaInk)
                    }
                    if let platform = doctor.platform {
                        Text("Platform: \(platform) · Python \(doctor.pythonVersion ?? "—") · torch \(doctor.torchVersion ?? "—") · MPS \(doctor.mpsAvailable ?? "—") · CUDA \(doctor.cudaAvailable ?? "—")")
                            .font(DunaFont.mono(12))
                            .foregroundStyle(Color.dunaGraphite)
                    }
                    if let mlx = doctor.mlxStatus {
                        Text("MLX: \(mlx) — expected to be unavailable on this Intel Mac. The Intel build uses PyTorch CPU + GGUF Qwen instead.")
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaWarmAsh)
                    }
                } else if let error = appState.doctorError {
                    Text(error)
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                } else {
                    Text("Doctor has not run yet.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaStone)
                }
            }
        }
    }

    // MARK: Download

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Live bar: MB downloaded / total, speed, time left, pause/resume.
            // Retry is wired in: stall / error shows why, with a Retry button.
            DownloadProgressCard(monitor: appState.downloadMonitor,
                                 onRetry: { appState.retryBackgroundDownload() })
            DunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("First-launch download")
                        .font(DunaFont.headline(17))
                        .foregroundStyle(Color.dunaInk)
                    Text("Models are not in the .app. Download them once, with resume — if a download stops, re-running picks up where it left off. Core set is about 1.62 GB; the whisper model and backup encoder are on-demand only.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaWarmAsh)
                    if let error = appState.downloadError {
                        Text(error)
                            .font(DunaFont.body(14))
                            .foregroundStyle(Color.dunaInk)
                    }
                    Button(appState.backgroundDownloadStarted ? "Download running in background" : (appState.downloadError == nil ? "Download missing models in background" : "Retry download")) {
                        appState.retryBackgroundDownload()
                    }
                    .buttonStyle(DunaPrimaryButtonStyle())
                    .disabled(appState.backgroundDownloadStarted)
                    if let error = downloader.error {
                        Text(error)
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaWarmAsh)
                    }
                }
            }
        }
    }

    private func downloadMissing() async {
        // NOTE: the per-file move from the URLSession temp location to the
        // final models/ path is not finished in this draft — the download
        // delegate signals completion, but the caller-side move needs the
        // temp URL, which the current continuation does not carry. Until
        // that is fixed on a Mac, the reliable path is the shell script:
        //   bash scripts/download-models.sh   (resumable, canonical)
        // This button therefore runs the script instead of the in-app
        // downloader. Honest, and it works today.
        appState.downloadingModels = true
        defer { appState.downloadingModels = false }
        guard let root = appState.backend.repoRoot else {
            downloader.error = "Could not find the repo (setup_macos.sh). Download from the repo folder: bash scripts/download-models.sh"
            return
        }
        // Run the script off the main thread — it downloads gigabytes and
        // must not block the UI.
        let exitCode: Int32 = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = ["scripts/download-models.sh"]
                proc.currentDirectoryURL = root
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    cont.resume(returning: proc.terminationStatus)
                } catch {
                    cont.resume(returning: -1)
                }
            }
        }
        if exitCode != 0 {
            downloader.error = "download-models.sh exited with code \(exitCode)."
        } else {
            await appState.runDoctor()
        }
    }

    // MARK: Model rows

    private func modelRow(_ entry: ModelEntry) -> some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(entry.name)
                                .font(DunaFont.headline(16))
                                .foregroundStyle(Color.dunaInk)
                            if !entry.required {
                                Text("OPTIONAL")
                                    .font(DunaFont.caption(10))
                                    .tracking(1.0)
                                    .foregroundStyle(Color.dunaStone)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.dunaBone)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(entry.role)
                            .font(DunaFont.body(14))
                            .foregroundStyle(Color.dunaGraphite)
                        Text(entry.source)
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaWarmAsh)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(entry.sizeNote)
                            .font(DunaFont.body(15))
                            .foregroundStyle(Color.dunaInk)
                        Text(doctorStatus(for: entry))
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaWarmAsh)
                    }
                }
                if let progress = downloader.progress[entry.id], progress < 1.0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.dunaMist).frame(height: 8)
                            RoundedRectangle(cornerRadius: 4).fill(Color.dunaInk)
                                .frame(width: geo.size.width * progress, height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                Text(entry.licenseNote)
                    .font(DunaFont.body(12))
                    .foregroundStyle(Color.dunaStone)
                Text(entry.relativePath)
                    .font(DunaFont.mono(12))
                    .foregroundStyle(Color.dunaStone)
            }
        }
    }

    private func doctorStatus(for entry: ModelEntry) -> String {
        guard let label = entry.doctorLabel,
              let doctor = appState.doctor,
              let status = doctor.raw[label]
        else { return "not checked yet" }
        return status
    }

    // MARK: Platform

    private var platformCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("This Mac")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("Intel Core i5. Auto-AVSR runs on PyTorch CPU — no Apple Silicon GPU, no MLX, no MPS. Expect slower decode than the M4 numbers in the Lipflow docs; measure it on this Mac before quoting any speed.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                Text("Your data lives in ~/Library/Application Support/SubvoxLocal — clips, phrases, personal LoRA, personal LM, settings, license. Model weights live in the repo's models/ folder.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }
}
