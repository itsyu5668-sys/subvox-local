// DunaTheme.swift — Subvox Local design tokens (Duna style).
//
// EXACT Duna tokens, no deviation. Sunset watercolor is the ONLY color
// moment in the whole app; everything else is achromatic.
//
// UNTESTED ON INTEL MAC: this file has never been compiled. It was written
// on a Linux VM with no Xcode. See swift/README.md before building.

import SwiftUI

// MARK: - Color tokens (exact hex from the Duna brief)

extension Color {
    /// Canvas.
    static let dunaLinen = Color(hex: 0xF7F7F5)
    /// Cards.
    static let dunaPaper = Color(hex: 0xFFFFFF)
    /// Panels.
    static let dunaBone = Color(hex: 0xEDECE7)
    /// Text.
    static let dunaInk = Color(hex: 0x1B0624)
    /// Primary buttons.
    static let dunaEspresso = Color(hex: 0x160F0C)
    /// Secondary text.
    static let dunaWarmAsh = Color(hex: 0x766A7C)
    static let dunaGraphite = Color(hex: 0x444444)
    static let dunaStone = Color(hex: 0x898683)
    /// Inputs.
    static let dunaMist = Color(hex: 0xEEEEEE)
    static let dunaOnyx = Color(hex: 0x0D0D0D)
    static let dunaSmoke = Color(hex: 0x1A1816)
    static let dunaCharcoal = Color(hex: 0x292421)

    /// 1px inset ring — the ONLY shadow allowed in Duna.
    static let dunaRing = Color.black.opacity(0.05)

    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Typography
//
// GT America is the Duna display face. It is not bundled with macOS, so
// Inter is the named substitute; if Inter is not installed, SwiftUI falls
// back to the system font. Display 72px, tracking -0.06em; body 400,
// emphasis 500. No other weights in the UI.

enum DunaFont {
    static func display(_ size: CGFloat = 72) -> Font {
        .custom("Inter", size: size).weight(.medium)
    }

    static func title(_ size: CGFloat = 28) -> Font {
        .custom("Inter", size: size).weight(.medium)
    }

    static func headline(_ size: CGFloat = 17) -> Font {
        .custom("Inter", size: size).weight(.medium)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .custom("Inter", size: size).weight(.regular)
    }

    static func caption(_ size: CGFloat = 13) -> Font {
        .custom("Inter", size: size).weight(.regular)
    }

    static func mono(_ size: CGFloat = 13) -> Font {
        .custom("SF Mono", size: size).weight(.regular)
    }
}

// MARK: - Shape / layout tokens

enum DunaLayout {
    /// Page max width.
    static let pageMaxWidth: CGFloat = 1200
    /// Card padding.
    static let cardPadding: CGFloat = 28
    /// Card corner radius.
    static let cardRadius: CGFloat = 16
    /// Image corner radius.
    static let imageRadius: CGFloat = 24
    /// Input corner radius.
    static let inputRadius: CGFloat = 8
    /// Large button height.
    static let largeButtonHeight: CGFloat = 60
    /// Pill buttons are fully round.
    static let pillRadius: CGFloat = 999
}

// MARK: - Sunset watercolor (the ONLY color moment)
//
// Used sparingly: the asterisk wordmark, the onboarding hero band, and the
// "listening" state glow. Everything else stays achromatic. These are warm
// sunset hues at low opacity, never a blue or green accent.

struct SunsetWatercolor: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: 0xF2A65A).opacity(0.55), // warm amber
                Color(hex: 0xE07856).opacity(0.45), // terracotta
                Color(hex: 0xC96F7B).opacity(0.35), // dusty rose
                Color(hex: 0xE8B4A0).opacity(0.30), // pale peach
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// The Subvox wordmark: an asterisk mark + SUBVOX in tracked caps.
struct SubvoxWordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            Text("✳")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0xE07856), Color(hex: 0xC96F7B)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("SUBVOX")
                .font(DunaFont.headline(size))
                .tracking(2.5)
                .foregroundStyle(Color.dunaInk)
        }
    }
}

// MARK: - Button styles

/// Primary Duna button: Espresso pill, 60px tall when large, white text.
struct DunaPrimaryButtonStyle: ButtonStyle {
    var large: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DunaFont.headline(large ? 17 : 15))
            .foregroundStyle(Color.dunaPaper)
            .padding(.horizontal, large ? 32 : 20)
            .frame(height: large ? DunaLayout.largeButtonHeight : 44)
            .background(Color.dunaEspresso)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// Secondary Duna button: Bone pill, ink text, inset ring only.
struct DunaSecondaryButtonStyle: ButtonStyle {
    var large: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DunaFont.headline(large ? 17 : 15))
            .foregroundStyle(Color.dunaInk)
            .padding(.horizontal, large ? 32 : 20)
            .frame(height: large ? DunaLayout.largeButtonHeight : 44)
            .background(Color.dunaBone)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.dunaRing, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Card / input primitives

/// Duna card: Paper White, 16px radius, 1px inset ring. No shadow.
struct DunaCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DunaLayout.cardPadding)
            .background(Color.dunaPaper)
            .clipShape(RoundedRectangle(cornerRadius: DunaLayout.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DunaLayout.cardRadius)
                    .stroke(Color.dunaRing, lineWidth: 1)
            )
    }
}

/// Duna text field: Mist background, 8px radius, inset ring.
struct DunaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DunaFont.body())
            .foregroundStyle(Color.dunaInk)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.dunaMist)
            .clipShape(RoundedRectangle(cornerRadius: DunaLayout.inputRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DunaLayout.inputRadius)
                    .stroke(Color.dunaRing, lineWidth: 1)
            )
    }
}

/// Small "local only" badge. No color accent — ink on bone.
struct LocalOnlyBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.dunaInk)
                .frame(width: 6, height: 6)
            Text("LOCAL ONLY — NO AUDIO LEAVES THIS MAC")
                .font(DunaFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(Color.dunaInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.dunaBone)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.dunaRing, lineWidth: 1))
    }
}

/// The license blocker banner. Shown on Dictate, Models, and Paywall
/// until the LRS3 weights problem is resolved (see CHARGING_PLAN, owned
/// by another agent). Never hidden, never softened.
struct LicenseBlockerBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("⚠")
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text("Not shippable as a paid product yet")
                    .font(DunaFont.headline(15))
                    .foregroundStyle(Color.dunaInk)
                Text("The Auto-AVSR weights are trained on LRS3 and licensed for non-commercial research only. This app is fine for your own use, but it cannot be sold or charged for with these weights as-is. See CHARGING_PLAN for the replacement-weights path.")
                    .font(DunaFont.body(13))
                    .foregroundStyle(Color.dunaGraphite)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.dunaBone)
        .clipShape(RoundedRectangle(cornerRadius: DunaLayout.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DunaLayout.cardRadius)
                .stroke(Color.dunaRing, lineWidth: 1)
        )
    }
}
