// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import SwiftUI

// MARK: - Section title

/// Section title with the 4 pt purple bar above it, a pattern taken from the website.
public struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.brandViolet).frame(width: 28, height: 4)
                Text(title).font(.title3.weight(.bold)).foregroundStyle(Color.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

// MARK: - Status badge

public struct StatusPill: View {
    public enum Style: Sendable { case success, danger, warning, accent, neutral }

    let text: String
    let style: Style

    public init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var foreground: Color {
        switch style {
        case .success: .statusSuccess
        case .danger: .statusDanger
        case .warning: .statusWarning
        case .accent: .brandVioletDeep
        case .neutral: .inkSecondary
        }
    }

    private var background: Color {
        switch style {
        case .success: .soft(.statusSuccess)
        case .danger: .soft(.statusDanger)
        case .warning: Color.brandYellow.opacity(0.3)
        case .accent: .soft(.brandViolet)
        case .neutral: .soft(.inkSecondary)
        }
    }
}

// MARK: - Cover

/// The item's cover art, or a cover generated in the brand guidelines colors when it is missing.
public struct CoverImage: View {
    let url: URL?
    let title: String
    let seed: Int

    public init(url: URL?, title: String, seed: Int) {
        self.url = url
        self.title = title
        self.seed = seed
    }

    public var body: some View {
        // The frame is set by the caller: the image fills it without overflowing.
        Color.clear
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        GeneratedCover(title: title, seed: seed)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct GeneratedCover: View {
    let title: String
    let seed: Int

    var body: some View {
        let colors = BrandArtwork.colors(for: seed)
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                colors.background
                Circle()
                    .fill(colors.shape)
                    .frame(width: proxy.size.width * 1.1)
                    .offset(x: -proxy.size.width * 0.35, y: -proxy.size.height * 0.45)
                if proxy.size.width > 80 {
                    Text(title)
                        .font(.system(size: proxy.size.width / 9, weight: .heavy))
                        .foregroundStyle(BrandArtwork.foreground(for: seed))
                        .lineLimit(3)
                        .padding(proxy.size.width / 12)
                }
            }
        }
    }
}

// MARK: - Empty state

/// Empty state component: tinted badge, brand guidelines shapes, title, message and actions.
public struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    let tint: Color
    let primary: (label: String, action: () -> Void)?
    let secondary: (label: String, action: () -> Void)?

    public init(
        systemImage: String,
        title: String,
        message: String,
        tint: Color = .brandViolet,
        primary: (label: String, action: () -> Void)? = nil,
        secondary: (label: String, action: () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
        self.primary = primary
        self.secondary = secondary
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.soft(tint)).frame(width: 96, height: 96)
                Circle().fill(Color.brandYellow).frame(width: 24).offset(x: 52, y: -44)
                Circle().fill(Color.brandMagenta).frame(width: 14).offset(x: -56, y: 42)
                Circle().stroke(Color.brandCyan, lineWidth: 3).frame(width: 10).offset(x: 48, y: 46)
                Image(systemName: systemImage).font(.system(size: 40, weight: .medium)).foregroundStyle(tint)
            }
            .frame(height: 120)
            .accessibilityHidden(true)

            Text(title).font(.title2.weight(.heavy)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text(message).font(.subheadline).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)

            if let primary {
                Button(primary.label, action: primary.action)
                    .buttonStyle(.prominent(tint: tint, size: .large))
                    .padding(.top, 8)
            }
            if let secondary {
                Button(secondary.label, action: secondary.action).tint(tint)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Messages

/// Temporary glass message at the bottom of the screen.
public struct MessageToast: View {
    let message: String?
    let dismiss: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    public init(message: String?, dismiss: @escaping () -> Void) {
        self.message = message
        self.dismiss = dismiss
    }

    public var body: some View {
        if let message {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    // Read out by VoiceOver: otherwise the result of an action is silent.
                    AccessibilityNotification.Announcement(message).post()
                    // Longer with VoiceOver, so the toast can still be found after the announcement.
                    try? await Task.sleep(for: .seconds(voiceOverEnabled ? 8 : 3))
                    dismiss()
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Errors

/// Line above the data already on screen when the refresh failed ("Hors ligne · dernières données enregistrées").
public struct StaleBanner: View {
    let text: String
    let systemImage: String

    public init(_ text: String, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.statusWarning)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brandYellow.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // A status that appears over data already read: VoiceOver says it without moving focus.
            .onAppear { AccessibilityNotification.Announcement(text).post() }
    }
}

// MARK: - Card

public extension View {
    /// Solid card: content stays opaque, glass is reserved for navigation.
    func cardStyle(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Loading skeleton

public struct SkeletonRow: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).frame(width: 52, height: 76)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 12)
            }
        }
        .foregroundStyle(Color.inkSecondary.opacity(0.15))
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - Available width

extension View {
    /// Reads the width actually available. The size class is not enough: an unfolded iPhone Duo
    /// is `.regular`, but once the sidebar is shown barely 670 pt remain for the content.
    public func measuringWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.wrappedValue = $0 }
    }

    /// Caps the width of a scroll view's or a form's content, while its background keeps the full width:
    /// on iPad, rows no longer stretch across the whole detail column. The content stays aligned
    /// with the large navigation title, on the leading side.
    public func readableContentWidth(_ maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }
}

private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.trailing, max(0, width - maxWidth), for: .scrollContent)
            .measuringWidth($width)
    }
}

// MARK: - Keyboard

extension View {
    /// Tapping an empty area (outside fields and buttons) dismisses the keyboard.
    /// Child fields and buttons keep priority over this gesture.
    public func dismissesKeyboardOnTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture {
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
    }
}
