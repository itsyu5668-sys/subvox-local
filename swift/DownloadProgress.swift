// DownloadProgress.swift — first-launch model download progress.
//
// The Python downloader (packaging/first_launch_downloader.py) writes
// ~/Library/Application Support/Subvox Local/download-progress.json
// once a second while it runs. This file only READS that JSON — it never
// starts a download itself, and it never touches the network.
//
// Fields in the JSON (see the downloader):
//   status: downloading | paused | cancelled | done | error
//   current_file, downloaded_bytes, total_bytes, percent,
//   overall_downloaded_bytes, overall_total_bytes, overall_percent,
//   bytes_per_sec, eta_seconds, overall_eta_seconds,
//   models_done, models_total
//
// The point of this file is the seamless-flow rule: the user should
// never stare at a spinner. The download runs in the background while
// they do Train First setup, and this view shows MB downloaded / total,
// speed, and time left — or nothing at all if the download is done.
//
// UNTESTED ON INTEL MAC: never compiled or run. The JSON shape is
// verified against the downloader on Linux (see docs/SEAMLESS_FLOW.md).

import SwiftUI
import Foundation

// MARK: - Progress JSON (matches the downloader, field for field)

struct DownloadProgressJSON: Codable {
    var status: String = "downloading"
    var currentFile: String = ""
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var percent: Double = 0
    var overallDownloadedBytes: Int64 = 0
    var overallTotalBytes: Int64 = 0
    var overallPercent: Double = 0
    var bytesPerSec: Double = 0
    var etaSeconds: Int?
    var overallEtaSeconds: Int?
    var modelsDone: Int = 0
    var modelsTotal: Int = 0
    /// "YYYY-MM-DDTHH:MM:SS" — when the downloader last wrote this file.
    /// The monitor treats a file older than 60s while status is
    /// "downloading" as stalled (see isStalled below).
    var updated: String = ""
    /// Plain-English failure reason, set only when status == "error".
    var errorMessage: String = ""

    enum CodingKeys: String, CodingKey {
        case status
        case currentFile = "current_file"
        case downloadedBytes = "downloaded_bytes"
        case totalBytes = "total_bytes"
        case percent
        case overallDownloadedBytes = "overall_downloaded_bytes"
        case overallTotalBytes = "overall_total_bytes"
        case overallPercent = "overall_percent"
        case bytesPerSec = "bytes_per_sec"
        case etaSeconds = "eta_seconds"
        case overallEtaSeconds = "overall_eta_seconds"
        case modelsDone = "models_done"
        case modelsTotal = "models_total"
        case updated
        case errorMessage = "error_message"
    }
}

// MARK: - Monitor (polls the JSON file once a second)

@MainActor
final class DownloadProgressMonitor: ObservableObject {
    @Published private(set) var progress: DownloadProgressJSON?
    @Published private(set) var lastError: String?
    /// True when the download looks stuck: status is "downloading"
    /// but the progress file has not changed for 60 seconds (no new
    /// bytes, no new write). Set by readOnce(); AppState observes it
    /// and auto-retries. Never a fake "downloading" forever.
    @Published private(set) var isStalled: Bool = false
    /// Called once when a stall is first detected. AppState sets this
    /// to its auto-retry (terminate the stuck downloader, start again).
    var onStalled: (() -> Void)?
    /// Called once when the downloader reports status "error".
    var onDownloadError: ((String) -> Void)?

    private var timer: Timer?
    private var lastSeenBytes: Int64 = -1
    private var lastBytesChange = Date()
    private var stallReported = false
    private var errorReportedFor: String = ""

    var progressFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubvoxLocal/download-progress.json")
    }

    var pauseFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubvoxLocal/download.pause")
    }

    var isPaused: Bool {
        FileManager.default.fileExists(atPath: pauseFileURL.path)
    }

    var isDone: Bool { progress?.status == "done" }
    var isDownloading: Bool { progress?.status == "downloading" }

    /// MB downloaded / MB total, for the whole core set.
    var downloadedMB: Double { Double(progress?.overallDownloadedBytes ?? 0) / 1_000_000 }
    var totalMB: Double { Double(progress?.overallTotalBytes ?? 0) / 1_000_000 }
    var overallPercent: Double { progress?.overallPercent ?? 0 }

    var speedMBps: Double { (progress?.bytesPerSec ?? 0) / 1_000_000 }

    /// Seconds left for the whole download, nil until the downloader
    /// has measured a rate. Never a fake number.
    var etaSeconds: Int? { progress?.overallEtaSeconds }

    var etaText: String {
        guard let eta = etaSeconds else { return "calculating time left…" }
        if eta < 60 { return "about \(eta) seconds left" }
        let minutes = eta / 60
        if minutes < 60 { return "about \(minutes) minute\(minutes == 1 ? "" : "s") left" }
        return "about \(minutes / 60) hour\(minutes / 60 == 1 ? "" : "s") \(minutes % 60) minutes left"
    }

    var statusText: String {
        if isStalled { return "Download looks stuck — no progress for over a minute. Check your wifi; the app will try again on its own." }
        switch progress?.status {
        case "done": return "Models downloaded."
        case "paused": return "Download paused."
        case "cancelled": return "Download cancelled. Tap Retry to resume — it picks up where it left off."
        case "error":
            let reason = progress?.errorMessage ?? ""
            return reason.isEmpty
                ? "Download hit an error. Check your internet and tap Retry — it resumes."
                : "Download hit an error: \(reason)"
        case "downloading": return "Downloading models in the background."
        default: return "Models have not started downloading yet."
        }
    }

    /// The last plain-English error from the downloader, if any.
    var errorDetail: String? {
        guard progress?.status == "error" else { return nil }
        let reason = progress?.errorMessage ?? ""
        return reason.isEmpty ? nil : reason
    }

    func startPolling() {
        stopPolling()
        readOnce()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readOnce() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func readOnce() {
        guard let data = try? Data(contentsOf: progressFileURL),
              let decoded = try? JSONDecoder().decode(DownloadProgressJSON.self, from: data)
        else { return }
        progress = decoded
        // Stall detection: the downloader writes this file once a
        // second while bytes are flowing. If the byte count has not
        // moved for 60 seconds while it still claims "downloading",
        // the download is stuck (wifi dropped, server stalled) — the
        // old code showed the same frozen percent forever.
        let bytes = decoded.overallDownloadedBytes
        if bytes != lastSeenBytes {
            lastSeenBytes = bytes
            lastBytesChange = Date()
            isStalled = false
            stallReported = false
        } else if decoded.status == "downloading",
                  Date().timeIntervalSince(lastBytesChange) > 60 {
            isStalled = true
            if !stallReported {
                stallReported = true
                onStalled?()
            }
        }
        if decoded.status == "error" {
            let reason = decoded.errorMessage
            if reason != errorReportedFor {
                errorReportedFor = reason
                lastError = reason
                onDownloadError?(reason)
            }
        } else if decoded.status == "done" {
            isStalled = false
        }
    }

    /// Pause: creates the pause file the downloader checks between
    /// chunks. The .part file stays, so resume picks up where it left off.
    func pause() {
        try? FileManager.default.createDirectory(
            at: pauseFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: pauseFileURL.path, contents: nil)
        readOnce()
    }

    /// Resume: deletes the pause file. The downloader checks it every
    /// 2 seconds while paused and continues on its own.
    func resume() {
        try? FileManager.default.removeItem(at: pauseFileURL)
        readOnce()
    }
}

// MARK: - Duna progress card (used in Onboarding + Models)

struct DownloadProgressCard: View {
    @ObservedObject var monitor: DownloadProgressMonitor
    /// Retry action (AppState.retryBackgroundDownload). If nil, the
    /// card shows the state but no Retry button.
    var onRetry: (() -> Void)?

    var body: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Model download")
                        .font(DunaFont.headline(17))
                        .foregroundStyle(Color.dunaInk)
                    Spacer()
                    Text(monitor.statusText)
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
                // Stuck / failed — big, plain, with a Retry button.
                // The old card only ever showed a frozen percent here.
                if monitor.isStalled || monitor.progress?.status == "error" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(monitor.isStalled
                             ? "This download looks stuck. It has not moved for over a minute — usually the wifi dropped or the server stalled. Your downloaded part is saved, so retrying picks up where it left off."
                             : "This download stopped with an error. Your downloaded part is saved, so retrying picks up where it left off.")
                            .font(DunaFont.body(14))
                            .foregroundStyle(Color.dunaInk)
                        if let detail = monitor.errorDetail {
                            Text(detail)
                                .font(DunaFont.mono(12))
                                .foregroundStyle(Color.dunaGraphite)
                        }
                        if let retry = onRetry {
                            Button("Retry download") { retry() }
                                .buttonStyle(DunaPrimaryButtonStyle())
                        }
                    }
                    .padding(12)
                    .background(Color.dunaBone)
                    .clipShape(RoundedRectangle(cornerRadius: DunaLayout.cardRadius))
                }
                if monitor.progress == nil {
                    Text("No download has started yet. It starts automatically on first launch — or tap Download below. It runs in the background while you set up.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaGraphite)
                } else {
                    // Progress bar.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.dunaMist).frame(height: 8)
                            RoundedRectangle(cornerRadius: 4).fill(Color.dunaInk)
                                .frame(width: geo.size.width * CGFloat(min(monitor.overallPercent, 100) / 100), height: 8)
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("\(String(format: "%.0f", monitor.downloadedMB)) MB of \(String(format: "%.0f", monitor.totalMB)) MB — \(Int(monitor.overallPercent))%")
                            .font(DunaFont.body(14))
                            .foregroundStyle(Color.dunaInk)
                        Spacer()
                        if monitor.isDownloading {
                            Text("\(String(format: "%.1f", monitor.speedMBps)) MB/s · \(monitor.etaText)")
                                .font(DunaFont.body(13))
                                .foregroundStyle(Color.dunaWarmAsh)
                        }
                    }
                    if let file = monitor.progress?.currentFile, !file.isEmpty, monitor.isDownloading {
                        Text("Now: \(file)")
                            .font(DunaFont.mono(12))
                            .foregroundStyle(Color.dunaStone)
                    }
                    Text("Models \(monitor.progress?.modelsDone ?? 0) of \(monitor.progress?.modelsTotal ?? 0) done. Keep setting up while this runs — the trial clock does not start until the models are ready and you dictate for the first time.")
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                    HStack {
                        if monitor.isPaused {
                            Button("Resume download") { monitor.resume() }
                                .buttonStyle(DunaPrimaryButtonStyle())
                        } else if monitor.isDownloading {
                            Button("Pause download") { monitor.pause() }
                                .buttonStyle(DunaSecondaryButtonStyle())
                        } else if monitor.progress?.status == "cancelled" {
                            if let retry = onRetry {
                                Button("Resume download") { retry() }
                                    .buttonStyle(DunaPrimaryButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .onAppear { monitor.startPolling() }
        .onDisappear { monitor.stopPolling() }
    }
}
