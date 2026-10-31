// SettingsView.swift — Subvox Local settings.
//
// Model paths, cleanup model choice (0.6B / 1.7B), hotkey, paste target,
// corrections. Settings are stored in
// ~/Library/Application Support/SubvoxLocal/settings.json — the same file
// the Python backend reads (src/subvox_local/paths.py SETTINGS), so both
// sides agree.
//
// UNTESTED ON INTEL MAC: never compiled or run.

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newCustomWord: String = ""
    @State private var savedMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                cleanupCard
                hotkeyCard
                pasteCard
                decodingCard
                pathsCard
                correctionsCard
                personalLMCard
                dangerCard
            }
            .frame(maxWidth: DunaLayout.pageMaxWidth)
            .padding(32)
        }
        .background(Color.dunaLinen)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(DunaFont.display(48))
                .foregroundStyle(Color.dunaInk)
            Text("Models, keys, and paste behaviour. Saved to ~/Library/Application Support/SubvoxLocal/settings.json.")
                .font(DunaFont.body(17))
                .foregroundStyle(Color.dunaWarmAsh)
        }
    }

    // MARK: Cleanup model

    private var cleanupCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cleanup model")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("After Auto-AVSR reads your lips, a small local model picks the sentence you meant from the top-3 guesses. Bigger is more accurate and slower on Intel CPU.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                Picker("Cleanup model", selection: $appState.settings.cleanupModel) {
                    Text("Qwen3-0.6B GGUF — fast (default)").tag("qwen-0.6b")
                    Text("Qwen3-1.7B GGUF — more accurate, slower").tag("qwen-1.7b")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.settings.cleanupModel) { _ in save() }
                Picker("Cleanup backend", selection: $appState.settings.cleanupBackend) {
                    Text("Auto — local model if available, else rules").tag("auto")
                    Text("Local — Qwen GGUF only").tag("local")
                    Text("Basic — offline rules only").tag("basic")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)
                .onChange(of: appState.settings.cleanupBackend) { _ in save() }
                Text("GGUF sizes are still TBD (see Models). The repo still ships MLX Qwen weights, which do not run on this Intel Mac.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    // MARK: Hotkey

    private var hotkeyCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hold-to-talk key")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Picker("Hotkey", selection: $appState.settings.hotkey) {
                    Text("Right Option — works in any app").tag("right-option")
                    Text("Space / H — works while this window is focused").tag("space-h")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.settings.hotkey) { _ in save() }
                Text("Right Option needs Input Monitoring permission (System Settings → Privacy & Security → Input Monitoring). Pasting at the cursor needs Accessibility. Both are requested during onboarding.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    // MARK: Paste target

    private var pasteCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste target")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Picker("Paste target", selection: $appState.settings.pasteTarget) {
                    Text("Paste at cursor — into the focused app").tag("cursor")
                    Text("Copy only — I paste manually").tag("clipboard")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.settings.pasteTarget) { _ in save() }
                Text("Paste at cursor copies the text and sends Cmd+V. Copy only puts it on the clipboard and does nothing else.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    // MARK: Decoding

    private var decodingCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Decoding")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                HStack(spacing: 16) {
                    Text("Beam size")
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaInk)
                    Stepper("\(appState.settings.beamSize)", value: $appState.settings.beamSize, in: 1...20)
                        .onChange(of: appState.settings.beamSize) { _ in save() }
                    Text("Python default is 10.")
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
                HStack(spacing: 16) {
                    Text("Camera index")
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaInk)
                    Stepper("\(appState.settings.cameraIndex)", value: $appState.settings.cameraIndex, in: 0...4)
                        .onChange(of: appState.settings.cameraIndex) { _ in save() }
                    Text("0 is the default FaceTime camera.")
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
            }
        }
    }

    // MARK: Paths

    private var pathsCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where things live")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                pathRow(label: "Your data", path: "~/Library/Application Support/SubvoxLocal")
                pathRow(label: "Models", path: "<repo>/models  (next to setup_macos.sh)")
                pathRow(label: "Practice clips", path: "~/Library/Application Support/SubvoxLocal/clips/fast_setup")
                pathRow(label: "Your phrases", path: "~/Library/Application Support/SubvoxLocal/phrases.txt")
                pathRow(label: "Personal LoRA", path: "~/Library/Application Support/SubvoxLocal/models/vsr_face_lora.pt")
                pathRow(label: "Personal LM", path: "~/Library/Application Support/SubvoxLocal/models/lm_phrasing.pth")
                pathRow(label: "License", path: "~/Library/Application Support/SubvoxLocal/license.json")
                Button("Open your data folder") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("SubvoxLocal")
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(DunaSecondaryButtonStyle())
            }
        }
    }

    private func pathRow(label: String, path: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(DunaFont.headline(14))
                .foregroundStyle(Color.dunaInk)
                .frame(width: 140, alignment: .leading)
            Text(path)
                .font(DunaFont.mono(12))
                .foregroundStyle(Color.dunaGraphite)
        }
    }

    // MARK: Corrections

    private var correctionsCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom words")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("Names, jargon, and words you use a lot. They go into the cleanup prompt so the model picks them over look-alikes. Stored in settings.json; corrections clips are saved by the Python side in corrections.jsonl.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                if appState.settings.customWords.isEmpty {
                    Text("No custom words yet.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaStone)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(appState.settings.customWords, id: \.self) { word in
                            HStack(spacing: 6) {
                                Text(word)
                                    .font(DunaFont.body(14))
                                    .foregroundStyle(Color.dunaInk)
                                Button("×") {
                                    appState.settings.customWords.removeAll { $0 == word }
                                    save()
                                }
                                .font(DunaFont.body(14))
                                .foregroundStyle(Color.dunaWarmAsh)
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.dunaBone)
                            .clipShape(Capsule())
                        }
                    }
                }
                HStack(spacing: 12) {
                    TextField("Add a word…", text: $newCustomWord)
                        .textFieldStyle(DunaTextFieldStyle())
                        .onSubmit { addWord() }
                    Button("Add") { addWord() }
                        .buttonStyle(DunaSecondaryButtonStyle())
                        .disabled(newCustomWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addWord() {
        let word = newCustomWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !appState.settings.customWords.contains(word) else { return }
        appState.settings.customWords.append(word)
        newCustomWord = ""
        save()
    }

    // MARK: Personal LM

    private var personalLMCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Personal language model")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("The biggest accuracy win per minute: train the LM on your own writing so it expects your phrasing and names. Import a text file, then train. Runs in the background.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                HStack(spacing: 12) {
                    Button("Import a text file…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.plainText]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            Task {
                                do {
                                    _ = try await appState.backend.importText(url.path)
                                    savedMessage = "Imported \(url.lastPathComponent) into phrases.txt."
                                } catch {
                                    savedMessage = error.localizedDescription
                                }
                            }
                        }
                    }
                    .buttonStyle(DunaSecondaryButtonStyle())
                    Button("Import Wispr Flow history") {
                        Task {
                            do {
                                _ = try await appState.backend.importWispr()
                                savedMessage = "Wispr history imported — next: train the personal LM."
                            } catch {
                                savedMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(DunaSecondaryButtonStyle())
                    Button("Train personal LM") {
                        Task {
                            do {
                                _ = try await appState.backend.trainLM()
                                savedMessage = "Personal LM trained."
                            } catch {
                                savedMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(DunaPrimaryButtonStyle())
                }
                if let savedMessage {
                    Text(savedMessage)
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
                Text("Runs: subvox-local import-text <file> · subvox-local import-wispr · subvox-local train-lm.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    // MARK: Danger zone

    private var dangerCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reset")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("Deletes your personal LoRA, personal LM, clips, and phrases from ~/Library/Application Support/SubvoxLocal. Downloaded models are kept. This cannot be undone.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                Button("Delete my personal data") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("SubvoxLocal")
                    try? FileManager.default.removeItem(at: url)
                    appState.settings = SubvoxSettings()
                    savedMessage = "Personal data deleted."
                }
                .buttonStyle(DunaSecondaryButtonStyle())
            }
        }
    }

    private func save() {
        appState.saveSettings()
        savedMessage = "Saved."
    }
}

// MARK: - Simple flow layout for word chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        for size in sizes {
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        width = max(width, rowWidth)
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
