import SwiftUI

// MARK: - Adaptive Color Palette
//
// Epistemic: colors encode certainty, urgency, and provenance.
// Skeuomorphic: layered materials with depth cues (bevels, insets, shadows).
// Compositional: consistent spacing scale, type ramp, and rhythm.

enum Df {

    // MARK: Surfaces — layered depth (back → front)

    /// The deepest background — canvas behind everything.
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.06, green: 0.06, blue: 0.08)
            : Color(red: 0.95, green: 0.94, blue: 0.93)
    }

    /// Raised surface — cards, panels, columns.
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.13)
            : Color(red: 0.99, green: 0.98, blue: 0.97)
    }

    /// Elevated surface — selected cards, popovers, toasts.
    static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.17)
            : .white
    }

    /// Inset surface — search fields, text inputs.
    static func inset(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.10)
            : Color(red: 0.91, green: 0.90, blue: 0.89)
    }

    // MARK: Text — contrast-safe hierarchy

    /// Primary text — titles, selected items. ≥ 7:1 contrast.
    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.93)
            : Color(white: 0.08)
    }

    /// Secondary text — descriptions, metadata. ≥ 4.5:1.
    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.60)
            : Color(white: 0.35)
    }

    /// Tertiary text — timestamps, counts, subtle labels. ≥ 3:1.
    static func textTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.38)
            : Color(white: 0.52)
    }

    /// Quaternary text — watermarks, disabled. Decorative, not readable.
    static func textQuaternary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.20)
            : Color(white: 0.72)
    }

    // MARK: Borders & Separators

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    static func borderStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.15)
    }

    /// Top-edge highlight for skeuomorphic bevel.
    static func bevelHighlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.8)
    }

    /// Bottom-edge shadow for skeuomorphic bevel.
    static func bevelShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.3)
            : Color.black.opacity(0.06)
    }

    // MARK: Semantic — epistemic status

    /// Something known, confirmed, live.
    static let certain = Color(red: 0.30, green: 0.72, blue: 0.50)
    /// Tentative, in-progress, hypothetical.
    static let tentative = Color(red: 0.85, green: 0.72, blue: 0.30)
    /// Needs attention, warning, uncertain.
    static let uncertain = Color(red: 0.92, green: 0.55, blue: 0.25)
    /// Error, failure, critical.
    static let critical = Color(red: 0.88, green: 0.30, blue: 0.28)
    /// Informational, neutral, cool.
    static let info = Color(red: 0.40, green: 0.62, blue: 0.90)
    /// Agent/AI activity.
    static let agent = Color(red: 0.55, green: 0.45, blue: 0.85)

    // MARK: Accent

    static let accent = Color(red: 0.38, green: 0.68, blue: 0.55)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.68, blue: 0.55), Color(red: 0.28, green: 0.58, blue: 0.72)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Type Ramp

    static let displayFont   = Font.system(size: 22, weight: .bold, design: .rounded)
    static let titleFont     = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let headlineFont  = Font.system(size: 13, weight: .semibold)
    static let bodyFont      = Font.system(size: 12, weight: .regular)
    static let captionFont   = Font.system(size: 10, weight: .medium)
    static let microFont     = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let monoFont      = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoSmallFont = Font.system(size: 9, weight: .regular, design: .monospaced)

    // MARK: Spacing Scale (4-point grid)

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    // MARK: Radii

    static let radiusSmall: CGFloat = 4
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 14
}

// MARK: - Skeuomorphic Card

/// A raised card with bevel edges, inner highlight, and drop shadow.
/// Epistemic: the visual weight of the card signals the importance of its content.
struct DfCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = Df.radiusMedium
    var isSelected: Bool = false
    var accentColor: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isSelected ? Df.elevated(scheme) : Df.surface(scheme))
                    .shadow(color: Df.bevelShadow(scheme), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Df.bevelHighlight(scheme),
                                .clear,
                                Df.bevelShadow(scheme).opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                // Accent left-edge for selected or colored cards
                Group {
                    if let color = accentColor ?? (isSelected ? Df.accent : nil) {
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: 3)
                                .padding(.vertical, 4)
                            Spacer()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    }
                }
            )
    }
}

// MARK: - Inset Field (search bars, text inputs)

/// A recessed, engraved-looking container for inputs.
struct DfInsetField<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, Df.space2)
            .padding(.vertical, Df.space2)
            .background(
                RoundedRectangle(cornerRadius: Df.radiusSmall + 2)
                    .fill(Df.inset(scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: Df.radiusSmall + 2)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Df.bevelShadow(scheme).opacity(0.4),
                                        .clear,
                                        Df.bevelHighlight(scheme).opacity(0.3)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
            )
    }
}

// MARK: - Pill Badge

/// Small colored pill for tags, counts, metrics.
struct DfPill: View {
    let text: String
    var color: Color = Df.info
    var mono: Bool = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(mono ? Df.monoSmallFont : .system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(scheme == .dark ? 0.15 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: Df.radiusSmall))
    }
}

// MARK: - Section Header

struct DfSectionHeader: View {
    let title: String
    var count: Int? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(Df.microFont)
                .foregroundStyle(Df.textTertiary(scheme))
            Rectangle()
                .fill(Df.border(scheme))
                .frame(height: 1)
            if let count {
                Text("\(count)")
                    .font(Df.microFont)
                    .foregroundStyle(Df.textQuaternary(scheme))
            }
        }
    }
}

// MARK: - Keycap (keyboard hint in footers)

struct DfKeycap: View {
    let key: String
    let label: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(Df.monoSmallFont)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Df.surface(scheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Df.bevelHighlight(scheme), Df.bevelShadow(scheme).opacity(0.5)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: Df.bevelShadow(scheme).opacity(0.3), radius: 1, y: 1)
                )
            Text(label)
                .font(Df.monoSmallFont)
                .foregroundStyle(Df.textQuaternary(scheme))
        }
    }
}

// MARK: - Status Dot (animated pulse for live items)

struct DfStatusDot: View {
    let color: Color
    var isLive: Bool = false

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .scaleEffect(isLive ? 1.5 : 1.0)
                    .opacity(isLive ? 0 : 1)
                    .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isLive)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.4), radius: 3)
        }
    }
}
