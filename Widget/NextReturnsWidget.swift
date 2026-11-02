// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import MediathequeCore
import SwiftUI
import WidgetKit

/// "Prochains retours" widget: reads the account snapshot from the App Group.
@main
struct MediathequeWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextReturnsWidget()
    }
}

struct NextReturnsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextReturns", provider: Provider()) { entry in
            NextReturnsView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Prochains retours")
        .description("Vos prochains documents à rendre et les réservations qui vous attendent.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: AccountSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: SnapshotClient.previewValue.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Entry(date: .now, snapshot: SnapshotClient.liveValue.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = SnapshotClient.liveValue.load()
        // One entry per day at midnight: "dans N jours" stays correct without relaunching the app.
        let calendar = Calendar.paris
        let today = calendar.startOfDay(for: .now)
        let entries = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { Entry(date: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: [Entry(date: .now, snapshot: snapshot)] + entries.dropFirst(), policy: .atEnd))
    }
}

struct NextReturnsView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    // Same light/dark pairs as the app's palette: the light-mode colors alone fell to 2.2–2.7:1
    // on the dark widget background.
    private let violet = Color.adaptive(light: 0x773DBD, dark: 0xA27BE0)
    private let danger = Color.adaptive(light: 0xA60A3D, dark: 0xFF6B8E)
    private let success = Color.adaptive(light: 0x006E43, dark: 0x4CC38A)
    private let warning = Color.adaptive(light: 0x7A4F00, dark: 0xF5C451)

    private var loans: [Loan] { entry.snapshot?.upcomingLoans ?? [] }
    private var readyHolds: [Hold] { entry.snapshot?.holds.filter(\.isReadyForPickup) ?? [] }

    var body: some View {
        if entry.snapshot == nil {
            empty("Connectez-vous dans l'app pour voir vos retours.")
        } else if loans.isEmpty, readyHolds.isEmpty {
            empty("Rien à rendre pour l'instant.")
        } else {
            switch family {
            case .accessoryInline:
                Text(inlineText).privacySensitive()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Médiathèque").font(.caption2.weight(.bold))
                    ForEach(loans.prefix(2)) { loan in
                        Text(verbatim: "\(loan.title) · \(dueText(loan))").font(.caption2).lineLimit(1)
                            // Titles are redacted on the Lock Screen while the iPhone is locked.
                            .privacySensitive()
                    }
                }
            default:
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "books.vertical.fill").foregroundStyle(violet)
                Text("À rendre").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
            }
            if let hold = readyHolds.first {
                Label("\(hold.title) vous attend", systemImage: "shippingbox.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(success)
                    .lineLimit(1)
                    .privacySensitive()
            }
            ForEach(loans.prefix(family == .systemSmall ? 2 : 3)) { loan in
                VStack(alignment: .leading, spacing: 1) {
                    Text(loan.title).font(.subheadline.weight(.semibold)).lineLimit(1).privacySensitive()
                    Text(dueText(loan)).font(.caption.weight(.semibold)).foregroundStyle(color(loan))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func empty(_ message: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "books.vertical.fill").foregroundStyle(violet)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var inlineText: String {
        guard let loan = loans.first else { return String(localized: "\(readyHolds.count) réservations à retirer") }
        return "\(loan.title) · \(dueText(loan))"
    }

    private func dueText(_ loan: Loan) -> String {
        switch loan.dueState(now: entry.date, calendar: .paris) {
        case let .late(days): String(localized: "en retard de \(days) j", comment: "Short: a loan is overdue by N days")
        case .dueSoon(0): String(localized: "aujourd'hui", comment: "A loan is due today")
        case .dueSoon(1): String(localized: "demain", comment: "A loan is due tomorrow")
        case let .dueSoon(days), let .onTime(days): String(localized: "dans \(days) jours", comment: "A loan is due in N days")
        }
    }

    private func color(_ loan: Loan) -> Color {
        switch loan.dueState(now: entry.date, calendar: .paris) {
        case .late: danger
        case .dueSoon: warning
        case .onTime: success
        }
    }
}

private extension Color {
    /// A color that follows the widget's light or dark appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
