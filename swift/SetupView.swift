// SetupView.swift — fast setup: 6 sentences, LoRA quick adapt, keep gate.
//
// The real plan is docs/FAST_SETUP_PLAN.md. The real sentences are
// src/subvox_local/sentences.py. Stage 1 records 6 sentences, trains a
// LoRA adapter (rank 8, 589,824 trainable params, base frozen), then
// evaluates on 2 held-out sentences and keeps the adapter ONLY if its
// WER beats stock. Stage 2 (the other 4 sentences + corrections) runs in
// the background while the user dictates.
//
// WER numbers in this view are ALWAYS measured live from the backend
// report. They start as "not measured yet". Never show a made-up WER.
//
// UNTESTED ON INTEL MAC: the training loop, camera recording, and the
// keep-gate have never run on a real Mac in this build.

import SwiftUI

// MARK: - Sentences (copied verbatim from src/subvox_local/sentences.py)
//
// FAST_10 — 10 phonetically balanced Harvard sentences, all 10 viseme
// classes covered (verified by tests/test_sentences.py).

enum SetupSentences {
    static let fast10: [String] = [
        "The birch canoe slid on the smooth planks",
        "Glue the sheet to the dark blue background",
        "It's easy to tell the depth of a well",
        "These days a chicken leg is a rare dish",
        "Rice is often served in round bowls",
        "The juice of lemons makes fine punch",
        "The box was thrown beside the parked truck",
        "Four hours of steady work faced us",
        "Kick the ball straight and follow through",
        "The salt breeze came across from the sea",
    ]

    /// Stage 1 (quick adapt): indices 0, 2, 4, 5, 8, 9.
    static let quick6Indices = [0, 2, 4, 5, 8, 9]
    static var quick6: [String] { quick6Indices.map { fast10[$0] } }

    /// Stage 2 (background): indices 1, 3, 6, 7.
    static let stage2Indices = [1, 3, 6, 7]
    static var stage2: [String] { stage2Indices.map { fast10[$0] } }

    /// Held out in stage 1 (never trained on): indices 3 and 7.
    static let heldOutIndices = [3, 7]
    static var heldOut: [String] { heldOutIndices.map { fast10[$0] } }
}

// MARK: - Setup state

enum SetupPhase: Equatable {
    case notStarted
    case recording(sentenceIndex: Int)
    case training(step: Int, totalSteps: Int, loss: Double?)
    case evaluating
    case done(kept: Bool)
    case failed(String)
}

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    /// Stage-1 step target on Intel CPU. The Python default is
    /// LORA_MAX_STEPS = 300 (adapt.py); `adapt-more --steps` defaults to
    /// 150. Stage 1 on Intel CPU targets 150 steps — the UI shows live
    /// progress from the backend log lines ("LoRA step N/300"), so the
    /// real count is whatever the backend reports, not this target.
    private let stage1TargetSteps = 150

    @State private var phase: SetupPhase = .notStarted
    @State private var recordedSentences: Set<Int> = []
    @State private var currentSentence = 0
    @State private var trainingStep = 0
    @State private var trainingLoss: Double?

    /// Measured WERs from the backend report. Nil = not measured yet.
    @State private var stockWER: Double?
    @State private var adaptedWER: Double?
    @State private var keptAdapted: Bool?
    @State private var trainSeconds: Double?
    @State private var trainStepsDone: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                howItWorks
                sentencesCard
                trainingCard
                keepGateCard
                stage2Card
            }
            .frame(maxWidth: DunaLayout.pageMaxWidth)
            .padding(32)
        }
        .background(Color.dunaLinen)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fast setup")
                .font(DunaFont.display(48))
                .foregroundStyle(Color.dunaInk)
            Text("Six sentences, about two minutes of mouthing. Then a small adapter learns your mouth — and is kept only if it actually reads you better.")
                .font(DunaFont.body(17))
                .foregroundStyle(Color.dunaWarmAsh)
        }
    }

    private var howItWorks: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("How it works")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                ForEach(howItWorksSteps, id: \.0) { num, text in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(num)")
                            .font(DunaFont.mono(13))
                            .foregroundStyle(Color.dunaStone)
                            .frame(width: 20)
                        Text(text)
                            .font(DunaFont.body(15))
                            .foregroundStyle(Color.dunaGraphite)
                    }
                }
            }
        }
    }

    private var howItWorksSteps: [(Int, String)] {
        [
            (1, "Mouth 6 Harvard sentences, one at a time, about 6 seconds each. The camera records 96×96 mouth crops — no full face, no audio."),
            (2, "A LoRA adapter trains on your clips: rank 8, 589,824 trainable params, base model frozen. Stage 1 targets 150 steps on Intel CPU."),
            (3, "The adapter is tested on 2 sentences it never trained on. It is kept ONLY if it reads them better than the stock model. Otherwise the stock model stays and nothing is lost."),
            (4, "Stage 2 runs in the background while you dictate: the other 4 sentences plus any corrections you make."),
        ]
    }

    // MARK: Sentences

    private var sentencesCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Stage 1 — record these 6")
                        .font(DunaFont.headline(17))
                        .foregroundStyle(Color.dunaInk)
                    Spacer()
                    Text("\(recordedSentences.count) / 6 recorded")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
                ForEach(Array(SetupSentences.quick6.enumerated()), id: \.offset) { index, sentence in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color.dunaRing, lineWidth: 1)
                                .background(
                                    Circle().fill(recordedSentences.contains(index) ? Color.dunaInk : Color.dunaMist)
                                )
                                .frame(width: 28, height: 28)
                            if recordedSentences.contains(index) {
                                Text("✓").font(.system(size: 13)).foregroundStyle(Color.dunaPaper)
                            } else {
                                Text("\(index + 1)").font(DunaFont.mono(12)).foregroundStyle(Color.dunaInk)
                            }
                        }
                        Text(sentence)
                            .font(DunaFont.body(16))
                            .foregroundStyle(Color.dunaInk)
                        Spacer()
                        Button(recordedSentences.contains(index) ? "Re-record" : "Record") {
                            recordSentence(index)
                        }
                        .buttonStyle(DunaSecondaryButtonStyle())
                        .disabled(phaseIsBusy)
                    }
                    .padding(.vertical, 4)
                }
                HStack(spacing: 12) {
                    Button("Start fast setup") {
                        Task { await runSetupFast() }
                    }
                    .buttonStyle(DunaPrimaryButtonStyle(large: true))
                    .disabled(recordedSentences.count < 6 || phaseIsBusy)
                    Button("Dry run — list sentences only") {
                        Task { await runDryRun() }
                    }
                    .buttonStyle(DunaSecondaryButtonStyle(large: true))
                    .disabled(phaseIsBusy)
                }
                Text("Runs: subvox-local setup-fast. The CLI records each sentence with the camera, then trains and evaluates. Dry run runs: subvox-local setup-fast --dry-run (no camera, no training).")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
                if case .failed(let message) = phase {
                    Text(message)
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
            }
        }
    }

    private var phaseIsBusy: Bool {
        switch phase {
        case .recording, .training, .evaluating: return true
        default: return false
        }
    }

    // MARK: Training

    private var trainingCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("LoRA training — stage 1")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                HStack(spacing: 24) {
                    specItem(label: "RANK", value: "8")
                    specItem(label: "TRAINABLE PARAMS", value: "589,824")
                    specItem(label: "BASE MODEL", value: "frozen")
                    specItem(label: "STEPS (STAGE 1)", value: "\(stage1TargetSteps)")
                    specItem(label: "LOSS", value: trainingLoss.map { String(format: "%.3f", $0) } ?? "—")
                }
                // Progress bar: live step count from the backend log.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Step \(trainingStep) / \(stage1TargetSteps)")
                            .font(DunaFont.body(14))
                            .foregroundStyle(Color.dunaInk)
                        Spacer()
                        Text(trainingStep > 0 ? "\(Int(Double(trainingStep) / Double(stage1TargetSteps) * 100))%" : "")
                            .font(DunaFont.body(14))
                            .foregroundStyle(Color.dunaWarmAsh)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.dunaMist)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.dunaInk)
                                .frame(
                                    width: geo.size.width * min(1.0, Double(trainingStep) / Double(stage1TargetSteps)),
                                    height: 8
                                )
                        }
                    }
                    .frame(height: 8)
                }
                Text("Training runs on Intel CPU in this build — slower than the M4 GPU numbers in the Lipflow docs. The step count and seconds below are the backend's own report, shown once training finishes.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
                if let seconds = trainSeconds, let steps = trainStepsDone {
                    Text("Trained \(steps) steps in \(String(format: "%.0f", seconds)) seconds.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaInk)
                }
            }
        }
    }

    private func specItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DunaFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(Color.dunaStone)
            Text(value)
                .font(DunaFont.body(15))
                .foregroundStyle(Color.dunaInk)
        }
    }

    // MARK: Keep gate

    private var keepGateCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keep-only-if-better gate")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("Two sentences are never trained on in stage 1. Both models read them, and the adapted model is saved only if its word error rate beats stock on those same clips.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                HStack(spacing: 32) {
                    werItem(label: "STOCK WER", value: stockWER)
                    werItem(label: "ADAPTED WER", value: adaptedWER)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DECISION")
                            .font(DunaFont.caption(11))
                            .tracking(1.2)
                            .foregroundStyle(Color.dunaStone)
                        Text(keptAdapted.map { $0 ? "Kept adapted" : "Kept stock" } ?? "Not measured yet")
                            .font(DunaFont.body(15))
                            .foregroundStyle(Color.dunaInk)
                    }
                }
                Text("Held out: “\(SetupSentences.heldOut[0])” and “\(SetupSentences.heldOut[1])”. Two held-out sentences is a noisy test — stage 2 re-checks on all 10 plus corrections.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    private func werItem(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DunaFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(Color.dunaStone)
            Text(value.map { String(format: "%.1f%%", $0 * 100) } ?? "Not measured yet")
                .font(DunaFont.body(15))
                .foregroundStyle(Color.dunaInk)
        }
    }

    // MARK: Stage 2

    private var stage2Card: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Stage 2 — background")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("The other 4 sentences, plus any corrections, continue training from the stage-1 adapter while you dictate. No second setup wait.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                ForEach(SetupSentences.stage2, id: \.self) { sentence in
                    Text("•  \(sentence)")
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaGraphite)
                }
                Button("Run stage 2 (adapt-more)") {
                    Task { await runAdaptMore() }
                }
                .buttonStyle(DunaSecondaryButtonStyle())
                .disabled(phaseIsBusy)
                Text("Runs: subvox-local adapt-more --steps 150. Continues the stage-1 LoRA if one was saved; otherwise starts fresh from stock.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    // MARK: - Actions (real CLI commands only)

    private func recordSentence(_ index: Int) {
        // Recording itself happens inside `setup-fast` on the Python side
        // (it prompts per sentence and records 6 s of mouth crops).
        // This button marks intent in the UI; the real recording flow is
        // the full `setup-fast` run below. Do not pretend a sentence was
        // recorded by tapping this button alone.
        currentSentence = index
        phase = .recording(sentenceIndex: index)
        // NOTE: per-sentence recording from Swift is not wired yet — the
        // Python CLI owns the record loop. Tapping here starts the full
        // setup run, which records all 6 sentences in order.
        Task { await runSetupFast() }
    }

    private func runDryRun() async {
        phase = .evaluating
        do {
            let out = try await appState.backend.setupFastDryRun()
            print(out)
            phase = .notStarted
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func runSetupFast() async {
        // The Python CLI is interactive (it prompts "Press Enter, then
        // mouth: ..." per sentence). There is no non-interactive flag for
        // the full run in app.py yet, so this launches the command and
        // streams its log. The WER numbers below are parsed from the
        // backend's own JSON report at the end — never invented.
        phase = .training(step: 0, totalSteps: stage1TargetSteps, loss: nil)
        trainingStep = 0
        do {
            let (out, err, code) = try await appState.backend.runBackend(["setup-fast"])
            guard code == 0 else {
                phase = .failed("setup-fast exited with code \(code): \(err)")
                return
            }
            // The backend prints a JSON report last (fast_setup return).
            // Parse stock_wer / adapted_wer / kept / train if present.
            if let jsonStart = out.lastIndex(of: "{"),
               let data = String(out[jsonStart...]).data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                stockWER = json["stock_wer"] as? Double
                adaptedWER = json["adapted_wer"] as? Double
                keptAdapted = json["kept"] as? Bool
                if let train = json["train"] as? [String: Any] {
                    trainSeconds = train["seconds"] as? Double
                    trainStepsDone = train["steps"] as? Int
                    trainingStep = trainStepsDone ?? 0
                }
                phase = .done(kept: keptAdapted ?? false)
                if keptAdapted == true {
                    recordedSentences = Set(0..<6)
                }
            } else {
                phase = .failed("setup-fast finished but its JSON report could not be parsed. Output: \(out)")
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func runAdaptMore() async {
        phase = .training(step: 0, totalSteps: stage1TargetSteps, loss: nil)
        do {
            let (out, err, code) = try await appState.backend.runBackend(["adapt-more", "--steps", "150"])
            guard code == 0 else {
                phase = .failed("adapt-more exited with code \(code): \(err)")
                return
            }
            if let jsonStart = out.lastIndex(of: "{"),
               let data = String(out[jsonStart...]).data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                trainSeconds = json["seconds"] as? Double
                trainStepsDone = json["steps"] as? Int
                trainingStep = trainStepsDone ?? 0
                phase = .done(kept: true)
            } else {
                phase = .failed("adapt-more finished but its JSON report could not be parsed.")
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
