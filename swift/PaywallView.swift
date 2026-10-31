// PaywallView.swift — trial + license-key paywall.
//
// 7-day free trial, then a license key. No audio is ever sent for
// activation: the key lives in an offline file in Application Support.
// An optional online check may be added later — it would send only the
// key, never audio or text.
//
// Pricing is a suggestion in one place (LicenseManager.Pricing):
//   $12/mo or $99 one-time.
// Justification vs the market: Wispr Flow Free is 2,000 words/week and
// Pro is $15/mo; Superwhisper is $8.49/mo. Subvox Local is fully
// on-device with no server to pay for, so $12/mo undercuts Wispr Pro
// while the $99 lifetime option fits buyers who hate subscriptions.
//
// CHECKOUT_URL is an empty placeholder. The Buy button stays disabled
// until Francis pastes a real Stripe / Lemon Squeezy link into
// Pricing.checkoutURLString. Do NOT invent a URL.
//
// LICENSE BLOCKER: this paywall must NOT be turned on commercially
// until the LRS3 weights problem is solved (see CHARGING_PLAN).
// The banner below says so in the UI. The trial exists so Francis can
// test the flow himself.
//
// UNTESTED ON INTEL MAC: never compiled or run.

import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var appState: AppState
    @State private var licenseKey: String = ""
    @State private var licenseKind: String = "lifetime"
    @State private var activationError: String?
    @State private var activationSuccess = false

    private var license: LicenseManager { appState.license }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LicenseBlockerBanner()

                header
                trialCard
                pricingCard
                activationCard
                compareCard
            }
            .frame(maxWidth: DunaLayout.pageMaxWidth)
            .padding(32)
        }
        .background(Color.dunaLinen)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subvox Local")
                .font(DunaFont.display(48))
                .foregroundStyle(Color.dunaInk)
            Text("Silent dictation, entirely on your Mac. No cloud, no microphone, no subscription to a server.")
                .font(DunaFont.body(17))
                .foregroundStyle(Color.dunaWarmAsh)
        }
    }

    // MARK: Trial

    private var trialCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your trial")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                switch license.state {
                case .notStarted:
                    Text("You have not started your \(Pricing.trialDays)-day free trial yet. Full dictation, no card, no account.")
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaGraphite)
                    Button("Start my 7-day free trial") {
                        license.startTrial()
                    }
                    .buttonStyle(DunaPrimaryButtonStyle(large: true))
                case .trial(let daysLeft):
                    Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") left in your free trial.")
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaInk)
                    Text("When the trial ends, dictation locks until you activate a license key.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaWarmAsh)
                case .expired:
                    Text("Your trial has ended. Activate a license key below to keep dictating.")
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaInk)
                case .licensed(let kind):
                    Text("Licensed — \(kind). Thank you.")
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaInk)
                    Button("Deactivate license (testing)") {
                        license.deactivateLicense()
                    }
                    .buttonStyle(DunaSecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: Pricing

    private var pricingCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pricing")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                HStack(alignment: .top, spacing: 24) {
                    priceOption(
                        title: "Monthly",
                        price: "$\(Pricing.monthlyUSD)",
                        per: "/ month",
                        note: "Cancel anytime. Same app, same models."
                    )
                    priceOption(
                        title: "Lifetime",
                        price: "$\(Pricing.lifetimeUSD)",
                        per: "one time",
                        note: "Pay once, keep it. For people who hate subscriptions."
                    )
                }
                if let url = license.checkoutURL {
                    Link("Buy — opens checkout in your browser", destination: url)
                        .font(DunaFont.body(15))
                        .foregroundStyle(Color.dunaInk)
                } else {
                    Text("Checkout is not set up yet. Francis needs to paste the real checkout link into Pricing.checkoutURLString — the Buy button stays off until then.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
                Button("Buy Subvox Local") {
                    if let url = license.checkoutURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(DunaPrimaryButtonStyle(large: true))
                .disabled(license.checkoutURL == nil)
                Button("Restore purchase") {
                    license.restorePurchase()
                }
                .buttonStyle(DunaSecondaryButtonStyle())
            }
        }
    }

    private func priceOption(title: String, price: String, per: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(DunaFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(Color.dunaStone)
            HStack(alignment: .bottom, spacing: 4) {
                Text(price)
                    .font(DunaFont.title(36))
                    .foregroundStyle(Color.dunaInk)
                Text(per)
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                    .padding(.bottom, 6)
            }
            Text(note)
                .font(DunaFont.body(13))
                .foregroundStyle(Color.dunaWarmAsh)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.dunaBone)
        .clipShape(RoundedRectangle(cornerRadius: DunaLayout.cardRadius))
    }

    // MARK: Activation

    private var activationCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activate with a license key")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                Text("Bought on the web? Paste your key. It is stored offline in ~/Library/Application Support/SubvoxLocal/license.json. No audio or text is sent to activate.")
                    .font(DunaFont.body(14))
                    .foregroundStyle(Color.dunaWarmAsh)
                TextField("SUBVOX-XXXX-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(DunaTextFieldStyle())
                    .font(DunaFont.mono(14))
                Picker("License type", selection: $licenseKind) {
                    Text("Lifetime").tag("lifetime")
                    Text("Monthly").tag("monthly")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Button("Activate license") {
                    if license.activateLicense(key: licenseKey, kind: licenseKind) {
                        activationSuccess = true
                        activationError = nil
                    } else {
                        activationSuccess = false
                        activationError = "That key could not be saved. Check it and try again."
                    }
                }
                .buttonStyle(DunaPrimaryButtonStyle())
                .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if activationSuccess {
                    Text("License activated.")
                        .font(DunaFont.body(14))
                        .foregroundStyle(Color.dunaInk)
                }
                if let activationError {
                    Text(activationError)
                        .font(DunaFont.body(13))
                        .foregroundStyle(Color.dunaWarmAsh)
                }
            }
        }
    }

    // MARK: Honest comparison

    private var compareCard: some View {
        DunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("How it compares")
                    .font(DunaFont.headline(17))
                    .foregroundStyle(Color.dunaInk)
                compareRow(
                    name: "Wispr Flow",
                    detail: "Free: \(Pricing.wisprFreeWordsPerWeek.formatted()) words/week. Pro: $\(Pricing.wisprProMonthlyUSD)/mo. Cloud-based voice dictation."
                )
                compareRow(
                    name: "Superwhisper",
                    detail: "About $\(Pricing.superwhisperMonthlyUSD, specifier: "%.2f")/mo. Cloud-based voice dictation."
                )
                compareRow(
                    name: "Subvox Local",
                    detail: "$\(Pricing.monthlyUSD)/mo or $\(Pricing.lifetimeUSD) once. Silent lip reading, fully on-device, no cloud, no microphone."
                )
                Text("Prices for Wispr and Superwhisper are the figures Francis quoted when the paywall was designed. Check them again before publishing this page.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaWarmAsh)
            }
        }
    }

    private func compareRow(name: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name)
                .font(DunaFont.headline(14))
                .foregroundStyle(Color.dunaInk)
                .frame(width: 120, alignment: .leading)
            Text(detail)
                .font(DunaFont.body(14))
                .foregroundStyle(Color.dunaGraphite)
        }
    }
}
