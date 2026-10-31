// SubvoxLauncher — minimal compiled launcher for Subvox Local (Intel Mac).
//
// WHAT THIS IS
// -------------
// The replacement for the retired hand-built script .app
// (~/workspace/subvox-local-click, CFBundleExecutable = a 499-byte bash
// script). macOS Launch Services treated that script as a document to
// edit, so double-clicking it opened Script Editor instead of running
// the app, and Gatekeeper rejected it. A .app whose CFBundleExecutable
// is a script is broken by design.
//
// This file compiles with plain swiftc into a real Mach-O x86_64
// binary. When it is the bundle's CFBundleExecutable, double-clicking
// the .app runs machine code — no Terminal, no Script Editor, no
// interpreter — and macOS treats it as an app.
//
// WHAT IT DOES (in order)
// ------------------------
//   1. Finds its own bundle (or $SUBVOX_BUNDLE_PATH, for testing the
//      binary standalone on a Mac without rebuilding the .app).
//   2. If the full SwiftUI app binary is present as a sibling named
//      `SubvoxLocalUI` (Contents/MacOS/SubvoxLocalUI), launches it and
//      exits. That is the normal path: the launcher is only the entry
//      point, the SwiftUI app is the UI. It launches via Foundation's
//      Process, so no Terminal window is ever created.
//   3. Otherwise (fallback — the SwiftUI binary is missing, e.g. its
//      swiftc step failed), starts the bundled backend through
//      Contents/Resources/launcher.sh, which downloads the core models
//      on first launch and runs `subvox-local doctor`. Then it shows a
//      plain macOS alert saying the backend is ready but the full UI
//      binary is missing, with the exact rebuild command. It never
//      fails silently.
//   4. If neither the UI binary nor launcher.sh exists, it shows an
//      alert saying the .app is incomplete and how to rebuild it.
//
// WHAT IT DOES NOT DO
// -------------------
//   - It does not open a Terminal. It does not exec a shell script as
//     the app itself — it *invokes* launcher.sh from compiled code,
//     which is fine: Launch Services only cares that
//     CFBundleExecutable is a Mach-O binary.
//   - It does not download models itself; launcher.sh /
//     first_launch_downloader.py own that.
//   - It is not the product UI. There is no Duna HTML in this bundle;
//     the SwiftUI app in swift/ is the UI.
//
// BUILD (on a Mac with Xcode Command Line Tools):
//   ./build-launcher.sh            # -> build/SubvoxLauncher (Mach-O x86_64)
//
// STATUS: UNTESTED ON MAC. Written on a Linux VM (no swiftc here), so
// this has never been compiled. It uses Foundation only — no SwiftUI,
// no AppKit import — so the swiftc line needs no -framework flags.
// The first compile on a Mac is the test. If it fails, fix the Swift
// here; do NOT work around it by putting a script back as
// CFBundleExecutable.
//
// LAYOUT FOR THE FALLBACK .app (only if the SwiftUI binary is ever
// unusable — see README.md in this folder):
//   Contents/MacOS/SubvoxLocal      <- this launcher (CFBundleExecutable)
//   Contents/MacOS/SubvoxLocalUI    <- the full SwiftUI binary
//   Contents/Info.plist             <- CFBundleExecutable stays "SubvoxLocal"
//   Contents/Resources/launcher.sh  <- backend starter (unchanged)

import Foundation

// MARK: - Logging

/// Append one timestamped line to the launcher log. Best effort: a
/// logging failure must never stop the launch.
func log(_ message: String) {
    let fm = FileManager.default
    let logDir = NSHomeDirectory() + "/Library/Logs/SubvoxLocal"
    let logPath = logDir + "/launcher.log"
    do {
        try fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        defer { try? handle.close() }
        try handle.seekToEnd()
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] launcher: \(message)\n"
        if let data = line.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    } catch {
        // Nothing else we can do; launching matters more than logging.
    }
}

/// Show a plain macOS dialog. Uses osascript so this file needs no
/// AppKit import and no -framework flag at compile time. The dialog
/// appears with no Terminal window.
func alert(title: String, message: String) {
    let escapedTitle = title
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let escapedMessage = message
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let script = "display alert \"\(escapedTitle)\" message \"\(escapedMessage)\""
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        log("osascript alert failed: \(error)")
    }
}

// MARK: - Entry point (top-level code; this file must be main.swift)

let fm = FileManager.default

// The bundle this binary lives in. Bundle.main works when the binary
// is Contents/MacOS/* inside a .app. The env override exists only so
// the binary can be smoke-tested standalone on a Mac without first
// assembling a .app around it.
let bundlePath: String
if let override = ProcessInfo.processInfo.environment["SUBVOX_BUNDLE_PATH"],
   !override.isEmpty {
    bundlePath = override
} else {
    bundlePath = Bundle.main.bundlePath
}
let macosDir = bundlePath + "/Contents/MacOS"
let resourcesDir = bundlePath + "/Contents/Resources"
let uiBinary = macosDir + "/SubvoxLocalUI"
let launcherScript = resourcesDir + "/launcher.sh"

log("started in bundle: \(bundlePath)")

// Path 1 (normal): the full SwiftUI app binary is present. Launch it
// as its own process and exit — the menu-bar app then owns the UI.
// Process (not exec) keeps this file free of unsafe C interop and
// still creates no Terminal window.
if fm.isExecutableFile(atPath: uiBinary) {
    log("launching SwiftUI app: \(uiBinary)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: uiBinary)
    process.arguments = []
    do {
        try process.run()
        log("SwiftUI app launched (pid \(process.processIdentifier)); launcher exiting")
        exit(0)
    } catch {
        log("failed to launch SwiftUI app: \(error)")
        alert(
            title: "Subvox Local could not start",
            message: "The app binary is present but would not launch: \(error). Rebuild with ./packaging/build_app.sh — see ~/Library/Logs/SubvoxLocal/launcher.log"
        )
        exit(1)
    }
}

// Path 2 (fallback): no SwiftUI binary. Start the backend through
// launcher.sh — it downloads the core models on first launch, then
// runs `subvox-local doctor`. Its own output goes to the same log dir.
if fm.fileExists(atPath: launcherScript) {
    log("no SubvoxLocalUI binary; starting backend via launcher.sh")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [launcherScript]
    let logPath = NSHomeDirectory() + "/Library/Logs/SubvoxLocal/launcher.log"
    if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
        try? handle.seekToEnd()
        process.standardOutput = handle
        process.standardError = handle
    }
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        log("failed to run launcher.sh: \(error)")
        alert(
            title: "Subvox Local could not start",
            message: "The backend starter would not run: \(error). See ~/Library/Logs/SubvoxLocal/launcher.log"
        )
        exit(1)
    }
    if process.terminationStatus == 0 {
        log("backend ready (doctor passed); no SwiftUI binary to open")
        alert(
            title: "Subvox Local backend is ready",
            message: "The backend started and the models are in place, but the full app window is missing (its Swift build did not produce a binary). Rebuild on the Mac with ./packaging/build_app.sh, then open the app again."
        )
        exit(0)
    } else {
        log("launcher.sh exited with status \(process.terminationStatus)")
        alert(
            title: "Subvox Local backend failed",
            message: "The backend starter exited with status \(process.terminationStatus). See ~/Library/Logs/SubvoxLocal/launcher.log, then re-run ./packaging/build_app.sh"
        )
        exit(1)
    }
}

// Path 3: nothing usable in this bundle.
log("incomplete bundle: no SubvoxLocalUI and no launcher.sh in \(bundlePath)")
alert(
    title: "Subvox Local is incomplete",
    message: "This copy is missing both the app and its backend starter. Delete it and rebuild on the Mac with ./packaging/build_app.sh then ./packaging/build_dmg.sh"
)
exit(1)
