// LicenseManager.swift — trial + license-key paywall for Subvox Local.
//
// Charging-ready UI + logic. There is NO real checkout wired in yet:
// CHECKOUT_URL is an empty placeholder Francis must fill in with his
// real Stripe / Lemon Squeezy link. Do NOT invent a URL.
//
// Pricing justification (code comment, also shown in PaywallView):
//   Wispr Flow Free is 2,000 words/week, Pro is $15/mo.
//   Superwhisper is $8.49/mo.
//   Subvox Local is fully on-device, no cloud, no subscription to a
//   server — so $12/mo undercuts Wispr Pro while the $99 one-time
//   lifetime option fits buyers who hate subscriptions.
//
// LICENSE BLOCKER — read before charging anyone:
//   The Auto-AVSR weights are LRS3, non-commercial research only
//   (see LICENSES.md). This paywall must NOT be turned on commercially
//   until replacement weights exist. See CHARGING_PLAN (written by
//   another agent). The banner in DunaTheme.swift says this in the UI.
//   The trial and license code below is for Francis's own testing and
//   for the day the weights problem is solved — not a green light to sell.

import Foundation

// MARK: - Pricing config (single place — change here, everywhere updates)

enum Pricing {
    /// Free trial length, in days.
    static let trialDays = 7
    /// Suggested monthly price, USD.
    static let monthlyUSD = 12
    /// Suggested one-time lifetime price, USD.
    static let lifetimeUSD = 99

    /// TODO (Francis): paste the real checkout link here.
    /// Leave empty until then — the Buy button stays disabled and says so.
    static let checkoutURLString = ""

    /// Competitor anchors shown on the paywall for honest comparison.
    static let wisprFreeWordsPerWeek = 2_000
    static let wisprProMonthlyUSD = 15
    static let superwhisperMonthlyUSD = 8.49
}

// MARK: - License state

enum LicenseState: Equatable {
    /// Never started the trial.
    case notStarted
    /// Inside the 7-day trial. `daysLeft` counts whole days remaining.
    case trial(daysLeft: Int)
    /// Trial over, no license. Dictation is locked until a key is entered.
    case expired
    /// A valid license key is on file. `kind` is "monthly" or "lifetime".
    case licensed(kind: String)
}

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var state: LicenseState = .notStarted

    private let trialStartKey = "subvox.trialStartDate"
    private let licenseFileName = "license.json"

    /// Offline license file:
    /// ~/Library/Application Support/SubvoxLocal/license.json
    /// {"key": "SUBVOX-XXXX-XXXX", "kind": "lifetime", "issued": "2026-10-31"}
    /// No audio is ever sent for activation. An optional online check may
    /// be added later; it would send only the key, never audio or text.
    var licenseFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubvoxLocal")
            .appendingPathComponent(licenseFileName)
    }

    var checkoutURL: URL? {
        guard !Pricing.checkoutURLString.isEmpty else { return nil }
        return URL(string: Pricing.checkoutURLString)
    }

    /// Is dictation usable right now? Trial active or licensed.
    var dictationUnlocked: Bool {
        switch state {
        case .notStarted, .trial, .licensed: return true
        case .expired: return false
        }
    }

    /// Days left in the trial, if trialling. Nil otherwise.
    var trialDaysLeft: Int? {
        if case .trial(let days) = state { return days }
        return nil
    }

    func refresh() {
        if let data = try? Data(contentsOf: licenseFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let kind = json["kind"] as? String,
           let key = json["key"] as? String,
           !key.isEmpty {
            // NOTE: this build accepts any non-empty key stored in the file.
            // A real release must validate the key format / signature here
            // (offline HMAC or an online check). Do not ship key validation
            // as "any string works".
            state = .licensed(kind: kind)
            return
        }
        if let start = UserDefaults.standard.object(forKey: trialStartKey) as? Date {
            let daysUsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
            let left = Pricing.trialDays - daysUsed
            state = left > 0 ? .trial(daysLeft: left) : .expired
        } else {
            state = .notStarted
        }
    }

    /// Start the 7-day trial. Called once, from onboarding or the paywall.
    func startTrial() {
        guard state == .notStarted else { return }
        UserDefaults.standard.set(Date(), forKey: trialStartKey)
        refresh()
    }

    /// Store a license key offline. Returns false if the key is blank.
    /// Real key validation (format/signature) is still TODO — see note above.
    @discardableResult
    func activateLicense(key: String, kind: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let url = licenseFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "key": trimmed,
            "kind": kind,
            "issued": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        refresh()
        return true
    }

    /// Remove the stored license (for testing / support). Trial is not reset.
    func deactivateLicense() {
        try? FileManager.default.removeItem(at: licenseFileURL)
        refresh()
    }

    /// Restore a previous purchase: re-reads the license file. There is no
    /// App Store receipt here (this is a direct-download .app, not a
    /// Mac App Store app), so "restore" means "re-check the key file and
    /// let the user re-enter a key they bought on the web".
    func restorePurchase() {
        refresh()
    }
}
