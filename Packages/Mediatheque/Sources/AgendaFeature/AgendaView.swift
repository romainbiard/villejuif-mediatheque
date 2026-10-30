import DesignSystem
import MediathequeCore
import SwiftUI

public struct AgendaView: View {
    @State private var viewModel = AgendaViewModel()
    @State private var showsFilters = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DayStrip(viewModel: viewModel)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle("Agenda")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsFilters = true
                    } label: {
                        Label(
                            viewModel.filters.isEmpty ? "Filtres" : "Filtres · \(viewModel.filters.count)",
                            systemImage: "line.3.horizontal.decrease"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
            .sheet(isPresented: $showsFilters) {
                AgendaFiltersView(viewModel: viewModel)
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedDay)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            RoundedRectangle(cornerRadius: 30).fill(Color.inkSecondary.opacity(0.12)).frame(height: 300)
            VStack(spacing: 14) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }.cardStyle()
        case let .failed(error):
            EmptyStateView(
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: error == .offline ? "Pas de connexion" : "L'agenda ne répond pas",
                message: "Vérifiez votre connexion, puis réessayez.",
                primary: ("Réessayer", { Task { await viewModel.load() } })
            )
        case .loaded:
            let events = viewModel.eventsOfSelectedDay
            if let featured = events.first {
                NavigationLink(value: featured) { FeaturedEventCard(event: featured) }.buttonStyle(.plain)
                if events.count > 1 {
                    SectionHeader("Ce jour-là")
                    EventList(events: Array(events.dropFirst()))
                }
            } else {
                emptyDay
            }
            if !viewModel.ongoingEvents.isEmpty {
                SectionHeader("En ce moment")
                EventList(events: viewModel.ongoingEvents)
            }
        }
    }

    private var emptyDay: some View {
        EmptyStateView(
            systemImage: "calendar",
            title: "Pas d'événement ce jour-là",
            message: viewModel.isLibraryClosingDay(viewModel.selectedDay)
                ? "Les médiathèques sont fermées ce jour-là. Essayez un autre jour."
                : "Essayez un autre jour, ou élargissez vos filtres.",
            tint: .brandMagenta,
            primary: viewModel.nextDayWithEvents.map { day in
                ("Voir le \(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))", { viewModel.select(day: day) })
            },
            secondary: viewModel.filters.isEmpty ? nil : ("Retirer les filtres", { viewModel.clearFilters() })
        )
    }
}

// MARK: - Sélecteur de jours

struct DayStrip: View {
    let viewModel: AgendaViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.days, id: \.self) { day in
                    let isSelected = Calendar.paris.isDate(day, inSameDayAs: viewModel.selectedDay)
                    Button { viewModel.select(day: day) } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold))
                            Text(day.formatted(.dateTime.day())).font(.title3.weight(.heavy))
                            Circle()
                                .fill(viewModel.hasEvents(on: day) ? Color.brandMagenta : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .foregroundStyle(isSelected ? Color.brandViolet : viewModel.isLibraryClosingDay(day) ? Color.inkSecondary : Color.ink)
                        .frame(width: 52, height: 62)
                        .background {
                            if isSelected { Capsule().fill(Color.surfaceCard).shadow(color: .black.opacity(0.08), radius: 6, y: 2) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(5)
        }
        .glassEffect(.regular, in: Capsule())
    }
}

// MARK: - Cartes

struct FeaturedEventCard: View {
    let event: Event

    var body: some View {
        ZStack(alignment: .bottom) {
            EventArtwork(event: event)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let type = event.type { StatusPill(type, style: .accent) }
                    if let audience = event.audience { StatusPill(audience, style: .accent) }
                }
                Text(event.title).font(.title2.weight(.heavy)).foregroundStyle(Color.ink).lineLimit(2)
                Text(EventFormatting.schedule(event)).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(10)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct EventArtwork: View {
    let event: Event

    var body: some View {
        let colors = BrandArtwork.colors(for: event.id)
        AsyncImage(url: event.imageURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    colors.background
                    Circle().fill(colors.shape).frame(width: 260).offset(x: 110, y: -90)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct EventList: View {
    let events: [Event]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                NavigationLink(value: event) {
                    HStack(spacing: 14) {
                        EventArtwork(event: event).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.headline).foregroundStyle(Color.ink).lineLimit(2)
                            Text(EventFormatting.schedule(event)).font(.subheadline).foregroundStyle(Color.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if event.id != events.last?.id { Divider().padding(.leading, 82) }
            }
        }
        .cardStyle(padding: 0)
    }
}

enum EventFormatting {
    static func schedule(_ event: Event) -> String {
        guard let start = event.start else { return event.place ?? "" }
        var parts: [String]
        if event.isAllDay {
            parts = event.end.map { ["Jusqu'au \($0.formatted(.dateTime.day().month(.wide)))"] } ?? []
        } else {
            let time = start.formatted(.dateTime.hour().minute())
            parts = [event.end.map { "\(time) – \($0.formatted(.dateTime.hour().minute()))" } ?? time]
        }
        if let place = event.library?.shortName ?? event.place { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    AgendaView()
}
