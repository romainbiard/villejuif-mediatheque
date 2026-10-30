import MediathequeCore
import SwiftUI
import WidgetKit

/// Widget « Prochains retours » : lit le snapshot du compte dans l'App Group.
@main
struct VillejuifWidgetBundle: WidgetBundle {
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
        // Une entrée par jour à minuit : « dans N jours » reste juste sans relancer l'app.
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

    private let violet = Color(red: 0x77 / 255, green: 0x3D / 255, blue: 0xBD / 255)
    private let danger = Color(red: 0xA6 / 255, green: 0x0A / 255, blue: 0x3D / 255)
    private let success = Color(red: 0x00, green: 0x6E / 255, blue: 0x43 / 255)

    private var loans: [Loan] { entry.snapshot?.upcomingLoans ?? [] }
    private var readyHolds: [Hold] { entry.snapshot?.holds.filter(\.isReadyForPickup) ?? [] }

    var body: some View {
        if entry.snapshot == nil {
            empty("Connectez-vous dans l'app pour voir vos retours.")
        } else if loans.isEmpty && readyHolds.isEmpty {
            empty("Rien à rendre pour l'instant.")
        } else {
            switch family {
            case .accessoryInline:
                Text(inlineText)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Médiathèques").font(.caption2.weight(.bold))
                    ForEach(loans.prefix(2)) { loan in
                        Text("\(loan.title) · \(dueText(loan))").font(.caption2).lineLimit(1)
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
            }
            ForEach(loans.prefix(family == .systemSmall ? 2 : 3)) { loan in
                VStack(alignment: .leading, spacing: 1) {
                    Text(loan.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(dueText(loan)).font(.caption.weight(.semibold)).foregroundStyle(color(loan))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func empty(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "books.vertical.fill").foregroundStyle(violet)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var inlineText: String {
        guard let loan = loans.first else { return "\(readyHolds.count) réservation à retirer" }
        return "\(loan.title) · \(dueText(loan))"
    }

    private func dueText(_ loan: Loan) -> String {
        switch loan.dueState(now: entry.date, calendar: .paris) {
        case let .late(days): "en retard de \(days) j"
        case .dueSoon(0): "aujourd'hui"
        case .dueSoon(1): "demain"
        case let .dueSoon(days), let .onTime(days): "dans \(days) jours"
        }
    }

    private func color(_ loan: Loan) -> Color {
        switch loan.dueState(now: entry.date, calendar: .paris) {
        case .late: danger
        case .dueSoon: Color(red: 0x7A / 255, green: 0x4F / 255, blue: 0)
        case .onTime: success
        }
    }
}
