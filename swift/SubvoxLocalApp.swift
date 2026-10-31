// SubvoxLocalApp.swift — Subvox Local, native SwiftUI macOS app.
//
// Menu-bar app (LSUIElement = true, no Dock icon) + main window.
// Duna style throughout (see DunaTheme.swift).
// The Python backend does all lip reading; this app is the window,
// the camera preview, the hotkey, and the paywall. See BackendBridge.swift.
//
// Status: SOURCE ONLY, UNTESTED ON INTEL MAC. This was written on a
// Linux VM with no Xcode and no Swift toolchain for macOS. It has never
// been compiled. See swift/README.md for the build steps on Francis's
// Intel Mac.
//
// Requires: macOS 14+, Swift 5.9+, Xcode 15+.
//   - MenuBarExtra: macOS 13+
//   - Layout protocol (FlowLayout in SettingsView): macOS 13+
//   - @Observable / SwiftData: not used; ObservableObject throughout.

import SwiftUI

@main
struct SubvoxLocalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // MARK: Menu bar
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // Asterisk mark in the menu bar (text, not an image asset,
            // so no asset catalog is needed for v0.1).
            Text("✳")
                .font(.system(size: 15, weight: .medium))
        }
        .menuBarExtraStyle(.window)

        // MARK: Main window
        Window("Subvox Local", id: "main") {
            ContentView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1100, height: 800)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Menu bar popover

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SubvoxWordmark(size: 16)
                Spacer()
                LocalOnlyBadge()
            }
            Divider()
            licenseLine
            Divider()
            Button("Open main window") {
                openWindow(id: "main")
            }
            Button("Dictate") {
                openWindow(id: "main")
                appState.tab = .dictate
            }
            Button("Set up / fast adapt…") {
                openWindow(id: "main")
                appState.tab = .setup
            }
            Button("Train personal LM") {
                Task {
                    do {
                        _ = try await appState.backend.trainLM()
                    } catch {
                        // Menu bar has no place to show the error; the
                        // main window's Settings tab shows the result.
                    }
                }
            }
            Button("Copy last dictation") {
                // TODO: wire to the last dictated text once the live
                // dictation session exists (see BackendBridge.swift).
            }
            Divider()
            Button("Quit Subvox Local") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Color.dunaLinen)
    }

    private var licenseLine: some View {
        Group {
            switch appState.license.state {
            case .notStarted:
                Text("Trial not started — 7 days free when you start.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            case .trial(let daysLeft):
                Text("Trial: \(daysLeft) day\(daysLeft == 1 ? "" : "s") left.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaInk)
            case .expired:
                Text("Trial ended — dictation is locked until you activate a license.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaInk)
            case .licensed(let kind):
                Text("Licensed (\(kind)).")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaInk)
            }
        }
    }
}

// MARK: - Main window content

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            DunaNavBar(tab: $appState.tab)
            Group {
                switch appState.tab {
                case .dictate:
                    DictationView()
                case .setup:
                    SetupView()
                case .models:
                    ModelsView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.dunaLinen)
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showPaywall) {
            PaywallView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Duna nav bar
//
// Asterisk mark + SUBVOX wordmark on the left, tab links in the middle,
// trial / license state on the right. No blue/green accent anywhere.

struct DunaNavBar: View {
    @Binding var tab: SubvoxTab
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 28) {
            SubvoxWordmark(size: 18)

            HStack(spacing: 4) {
                ForEach(SubvoxTab.allCases) { item in
                    Button(item.rawValue) {
                        tab = item
                    }
                    .font(DunaFont.headline(15))
                    .foregroundStyle(tab == item ? Color.dunaInk : Color.dunaWarmAsh)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        tab == item
                            ? Color.dunaBone
                            : Color.clear
                    )
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            trialPill
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Color.dunaPaper)
        .overlay(
            Rectangle()
                .fill(Color.dunaRing)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var trialPill: some View {
        Button {
            appState.showPaywall = true
        } label: {
            HStack(spacing: 6) {
                switch appState.license.state {
                case .notStarted:
                    Text("Start 7-day trial")
                case .trial(let daysLeft):
                    Text("Trial · \(daysLeft)d left")
                case .expired:
                    Text("Trial ended — activate")
                case .licensed(let kind):
                    Text("Licensed · \(kind)")
                }
            }
            .font(DunaFont.headline(13))
            .foregroundStyle(Color.dunaInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.dunaBone)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.dunaRing, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
