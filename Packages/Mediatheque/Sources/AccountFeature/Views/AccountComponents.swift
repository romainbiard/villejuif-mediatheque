// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import SwiftUI

struct CounterTile: View {
    let value: Int
    let label: String
    let color: Color
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.title.weight(.heavy)).foregroundStyle(color)
            Text(label).font(.subheadline).foregroundStyle(Color.inkSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

struct MenuRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let accessory: Accessory
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The icon tile grows with the text size, capped so the title keeps its width.
    @ScaledMetric(relativeTo: .body) private var scaledTileSize: CGFloat = 32
    private var tileSize: CGFloat { min(scaledTileSize, 44) }

    var body: some View {
        // Badge next to the title, under it at accessibility text sizes.
        let textLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .foregroundStyle(Color.onTint)
                .frame(width: tileSize, height: tileSize)
                .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            textLayout {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Minimum only: the row grows with the text instead of cutting the title off.
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}
