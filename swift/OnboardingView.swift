// OnboardingView.swift — first-launch onboarding.
//
// Order: permissions → model download → fast setup → trial.
// The sheet is shown until the user finishes or dismisses it; nothing
// is forced — the user can skip the download and the setup and come back
// from Models / Setup later.
//
// UNTESTED ON INTEL MAC: permission prompts, download progress, and the
// sheet flow have never run on a real Mac in this build.

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var step = 0
    @State private var cameraGranted = false
    @State private var inputMonitoringNoteShown = false

    private let steps = ["Welcome", "Permissions", "Models", "Setup", "Trial"]

    var body: some View {
        VStack(spacing: 0) {
            // Sunset watercolor hero band — the only color moment.
            ZStack(alignment: .bottomLeading) {
                SunsetWatercolor()
                    .frame(height: 140)
                VStack(alignment: .leading, spacing: 6) {
                    SubvoxWordmark(size: 22)
                    Text("Silent dictation, on your Mac.")
                        .font(DunaFont.title(26))
                        .foregroundStyle(Color.dunaInk)
                }
                .padding(28)
            }

            // Step dots.
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= step ? Color.dunaInk : Color.dunaMist)
                        .frame(width: 8, height: 8)
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(index < step ? Color.dunaInk : Color.dunaMist)
                            .frame(width: 24, height: 2)
                    }
                }
                Spacer()
                Text("Step \(step + 1) of \(steps.count) — \(steps[step])")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0: welcomeStep
                    case 1: permissionsStep
                    case 2: modelsStep
                    case 3: setupStep
                    case 4: trialStep
                    default: welcomeStep
                    }
                }
                .padding(28)
            }

            // Footer nav.
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(DunaSecondaryButtonStyle())
                }
                Spacer()
                Button("Skip for now") {
                    appState.finishOnboarding()
                }
                .buttonStyle(DunaSecondaryButtonStyle())
                if step < steps.count - 1 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(DunaPrimaryButtonStyle())
                } else {
                    // Train First: the first screen after onboarding is
                    // Setup, not Dictate — stock Auto-AVSR is not accurate
                    // on a new face until the personal LoRA has trained.
                    Button("Start training") {
                        appState.finishOnboarding()
                        appState.tab = .setup
                    }
                    .buttonStyle(DunaPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 640, height: 620)
        .background(Color.dunaLinen)
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hold a key. Mouth the words. Text appears at your cursor.")
                .font(DunaFont.body(17))
                .foregroundStyle(Color.dunaInk)
            Text("Subvox Local reads your lips with your webcam — no microphone, no sound, no cloud. Everything runs on this Mac: the camera, the lip reader, and the cleanup model.")
                .font(DunaFont.body(15))
                .foregroundStyle(Color.dunaGraphite)
            Text("This Mac is an Intel Core i5. The lip reader runs on PyTorch CPU here, which is slower than the Apple Silicon GPU numbers you may have seen. Nothing in this app quotes a speed that has not been measured on this Mac.")
                .font(DunaFont.body(14))
                .foregroundStyle(Color.dunaWarmAsh)
            LocalOnlyBadge()
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Three permissions")
                .font(DunaFont.headline(17))
                .foregroundStyle(Color.dunaInk)
            permissionRow(
                title: "Camera",
                detail: "To see your mouth. Requested now — macOS shows its own prompt.",
                granted: cameraGranted,
                actionLabel: "Grant camera access"
            ) {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    Task { @MainActor in cameraGranted = granted }
                }
            }
            permissionRow(
                title: "Input Monitoring",
                detail: "So Right Option works as the hold-to-talk key in any app. macOS cannot prompt for this from inside the app — open System Settings → Privacy & Security → Input Monitoring and add Subvox Local.",
                granted: false,
                actionLabel: "Open System Settings"
            ) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
            permissionRow(
                title: "Accessibility",
                detail: "So the app can paste at your cursor in other apps. Open System Settings → Privacy & Security → Accessibility and add Subvox Local.",
                granted: false,
                actionLabel: "Open System Settings"
            ) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            Text("Input Monitoring and Accessibility cannot be checked from inside the app — macOS does not report their status to the app. The app tells you if the hotkey or paste fails, and Space / H plus Copy-only always work as fallbacks.")
                .font(DunaFont.body(13))
                .foregroundStyle(Color.dunaWarmAsh)
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DunaFont.headline(15))
                    .foregroundStyle(Color.dunaInk)
                Text(detail)
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaGraphite)
            }
            Spacer()
            Button(granted ? "Granted" : actionLabel, action: action)
                .buttonStyle(DunaSecondaryButtonStyle())
                .disabled(granted)
        }
        .padding(16)
        .background(Color.dunaPaper)
        .clipShape(RoundedRectangle(cornerRadius: DunaLayout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DunaLayout.cardRadius)
                .stroke(Color.dunaRing, lineWidth: 1)
        )
    }

    private var modelsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download the models — in the background")
                .font(DunaFont.headline(17))
                .foregroundStyle(Color.dunaInk)
            Text("Models are not inside the app — they download once, with resume, while you set up. You do not wait for them: tap Continue and do the Train First setup on the next step while this runs. Recording your sentences works while downloading; training waits until the lip reader has landed.")
                .font(DunaFont.body(15))
                .foregroundStyle(Color.dunaGraphite)
            // Live progress: MB downloaded / total, speed, time left.
            // Retry is wired in: if the download stalls or fails, the
            // card shows why and offers Retry instead of a frozen bar.
            DownloadProgressCard(monitor: appState.downloadMonitor,
                                 onRetry: { appState.retryBackgroundDownload() })
            // Core set only — what downloads, and what does not.
            ForEach(ModelCatalogue.entries.filter { $0.required }) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(DunaFont.headline(14))
                            .foregroundStyle(Color.dunaInk)
                        Text(entry.sizeNote)
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaWarmAsh)
                    }
                    Spacer()
                    if let progress = appState.downloadProgress[entry.id] {
                        Text(progress >= 1.0 ? "Downloaded" : "\(Int(progress * 100))%")
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaInk)
                    } else {
                        Text("Not started")
                            .font(DunaFont.body(13))
                            .foregroundStyle(Color.dunaStone)
                    }
                }
            }
            Text("Core set, about 1.62 GB total: lip reader 1,001.9 MB, language model 215.1 MB, tokenizer 0.3 MB, face tracker 3.8 MB, Qwen cleanup (GGUF) 396.7 MB. The 1.8 GB whisper model and 1.9 GB backup encoder do NOT download now — only if you turn on whisper mode later. Per-model progress also appears in Models.")
                .font(DunaFont.body(13))
                .foregroundStyle(Color.dunaWarmAsh)
            if let error = appState.downloadError {
                Text(error)
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaInk)
            }
            Button(appState.backgroundDownloadStarted ? "Download running in background" : (appState.downloadError == nil ? "Start download in background" : "Retry download")) {
                appState.retryBackgroundDownload()
            }
            .buttonStyle(DunaPrimaryButtonStyle())
            .disabled(appState.backgroundDownloadStarted)
        }
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teach it your mouth — train first")
                .font(DunaFont.headline(17))
                .foregroundStyle(Color.dunaInk)
            Text("Mouth 10 short sentences, 3 takes each. A small adapter learns your lip shapes and is kept only if it reads you better than the stock model. Recording takes a few minutes; training takes 10+ minutes on this Intel i5 CPU — the app shows the measured time, never an estimate. You can do this now or later from Setup, but dictation waits until it has run.")
                .font(DunaFont.body(15))
                .foregroundStyle(Color.dunaGraphite)
            ForEach(SetupSentences.fast10, id: \.self) { sentence in
                Text("•  \(sentence)  —  3 takes")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaGraphite)
            }
            Button("Go to Setup") {
                appState.finishOnboarding()
                appState.tab = .setup
            }
            .buttonStyle(DunaPrimaryButtonStyle())
        }
    }

    private var trialStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("7 days free, then $\(Pricing.monthlyUSD)/month")
                .font(DunaFont.headline(17))
                .foregroundStyle(Color.dunaInk)
            Text("Your free trial is \(Pricing.trialDays) days, full dictation, no card. The clock starts only once the models are ready and you dictate for the first time — not while they download. After that it is $\(Pricing.monthlyUSD)/month, billed monthly via Stripe, activated with a license key. A $\(Pricing.lifetimeUSD) one-time option exists as a secondary upsell, not the main plan. No audio is ever sent — activation is an offline key file.")
                .font(DunaFont.body(15))
                .foregroundStyle(Color.dunaGraphite)
            LicenseBlockerBanner()
            Button("Start my 7-day free trial") {
                appState.license.startTrial()
            }
            .buttonStyle(DunaPrimaryButtonStyle(large: true))
        }
    }
}
