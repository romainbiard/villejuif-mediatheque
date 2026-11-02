// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

public struct AgendaView: View {
    @State private var viewModel = AgendaViewModel()
    @State private var showsFilters = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var contentWidth: CGFloat = .infinity

    /// Mini calendar (320 pt), at least two 240 pt cards, margins.
    static let columnsMinWidth: CGFloat = 900

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular && contentWidth >= Self.columnsMinWidth {
                    regularLayout
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let error = viewModel.staleError {
                                StaleBanner(error.staleText, systemImage: error.staleSystemImage)
                            }
                            if viewModel.filters.period == .all {
                                DayStrip(viewModel: viewModel)
                                content
                            } else {
                                PeriodHeader(viewModel: viewModel)
                                periodContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color.surfaceGrouped)
            .navigationTitle(Text(.local("Agenda", comment: "Screen title: the libraries' events")))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsFilters = true
                    } label: {
                        Label(
                            viewModel.filters.isEmpty ? LocalizedStringResource.local("Filtres") : .local("Filtres · \(viewModel.filters.count)", comment: "Button; number of active filters"),
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
            .refreshable { await viewModel.load(.reload) }
        }
        .measuringWidth($contentWidth)
        .sensoryFeedback(.selection, trigger: viewModel.selectedDay)
    }

    /// iPad: mini calendar and quick filters on the left, card grid on the right.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MonthCalendar(viewModel: viewModel)
                    QuickPeriods(viewModel: viewModel)
                }
                .padding(.bottom, 24)
            }
            .frame(width: 320)
            .scrollIndicators(.hidden)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = viewModel.staleError {
                        StaleBanner(error.staleText, systemImage: error.staleSystemImage)
                    }
                    if viewModel.filters.period == .all {
                        Text(viewModel.selectedDay.formatted(EventFormatting.dayTitle))
                            .font(.title2.weight(.heavy))
                        regularDayContent
                    } else {
                        PeriodHeader(viewModel: viewModel)
                        regularPeriodContent
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var regularDayContent: some View {
        switch viewModel.state {
        case .idle, .loading, .failed:
            content
        case .loaded:
            let events = viewModel.eventsOfSelectedDay
            if events.isEmpty {
                emptyDay
            } else {
                EventGrid(events: events)
            }
            if !viewModel.ongoingEvents.isEmpty {
                SectionHeader(String.local("En ce moment", comment: "Section: ongoing exhibitions and long events"))
                EventGrid(events: viewModel.ongoingEvents)
            }
        }
    }

    @ViewBuilder
    private var regularPeriodContent: some View {
        switch viewModel.state {
        case .idle, .loading, .failed:
            periodContent
        case .loaded:
            if viewModel.periodDays.isEmpty && viewModel.periodOngoingEvents.isEmpty {
                periodContent
            }
            ForEach(viewModel.periodDays) { periodDay in
                SectionHeader(periodDay.day.formatted(EventFormatting.dayTitle))
                EventGrid(events: periodDay.events)
            }
            if !viewModel.periodOngoingEvents.isEmpty {
                SectionHeader(String.local("Pendant cette période"))
                EventGrid(events: viewModel.periodOngoingEvents)
            }
        }
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
                title: error == .offline ? String.local("Pas de connexion") : String.local("L'agenda ne répond pas"),
                message: String.local("Vérifiez votre connexion, puis réessayez."),
                primary: (String.local("Réessayer"), { Task { await viewModel.load() } })
            )
        case .loaded:
            let events = viewModel.eventsOfSelectedDay
            if let featured = events.first {
                NavigationLink(value: featured) { FeaturedEventCard(event: featured) }.buttonStyle(.plain)
                if events.count > 1 {
                    SectionHeader(String.local("Ce jour-là", comment: "Section: other events on the selected day"))
                    EventList(events: Array(events.dropFirst()))
                }
            } else {
                emptyDay
            }
            if !viewModel.ongoingEvents.isEmpty {
                SectionHeader(String.local("En ce moment", comment: "Section: ongoing exhibitions and long events"))
                EventList(events: viewModel.ongoingEvents)
            }
        }
    }

    @ViewBuilder
    private var periodContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 14) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }.cardStyle()
        case .failed:
            content
        case .loaded:
            let days = viewModel.periodDays
            if days.isEmpty && viewModel.periodOngoingEvents.isEmpty {
                EmptyStateView(
                    systemImage: "calendar.badge.exclamationmark",
                    title: String.local("Rien de prévu sur cette période"),
                    message: String.local("Aucune animation ne correspond. Essayez une autre période ou retirez des filtres."),
                    tint: .brandMagenta,
                    primary: (String.local("Voir tout l'agenda"), { viewModel.clearPeriod() }),
                    secondary: viewModel.filters.count > 1 ? (String.local("Retirer tous les filtres"), { viewModel.clearFilters() }) : nil
                )
            }
            ForEach(days) { periodDay in
                SectionHeader(periodDay.day.formatted(EventFormatting.dayTitle))
                EventList(events: periodDay.events)
            }
            if !viewModel.periodOngoingEvents.isEmpty {
                SectionHeader(String.local("Pendant cette période"))
                EventList(events: viewModel.periodOngoingEvents)
            }
        }
    }

    private var emptyDay: some View {
        EmptyStateView(
            systemImage: "calendar",
            title: String.local("Pas d'événement ce jour-là"),
            message: viewModel.isLibraryClosingDay(viewModel.selectedDay)
                ? String.local("Les médiathèques sont fermées ce jour-là. Essayez un autre jour.")
                : String.local("Essayez un autre jour, ou élargissez vos filtres."),
            tint: .brandMagenta,
            primary: viewModel.nextDayWithEvents.map { day in
                (String.local("Voir le \(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))", comment: "Button; %@ is a day, e.g. Saturday, November 7"), { viewModel.select(day: day) })
            },
            secondary: viewModel.filters.isEmpty ? nil : (String.local("Retirer les filtres"), { viewModel.clearFilters() })
        )
    }
}

// MARK: - Period

/// Replaces the day picker when a "Quand" filter is active.
struct PeriodHeader: View {
    let viewModel: AgendaViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandViolet)
                .frame(width: 44, height: 44)
                .background(Color.soft(.brandViolet), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.filters.period.label).font(.headline)
                if let summary = viewModel.periodSummary {
                    Text(summary).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button(.local("Revenir aux jours", comment: "Leaves the period view and goes back to the day picker"), systemImage: "xmark") { viewModel.clearPeriod() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var icon: String {
        switch viewModel.filters.period {
        case .all: "calendar"
        case .weekend: "sun.max.fill"
        case .wednesdays: "figure.and.child.holdinghands"
        case .schoolHolidays: "backpack.fill"
        }
    }
}

// MARK: - Day picker

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

// MARK: - iPad

/// Month mini calendar: dots under days with an event, closed days greyed out.
struct MonthCalendar: View {
    let viewModel: AgendaViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    /// Narrow weekday names in the user's language, Monday first.
    private static var weekdays: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return Array(symbols.dropFirst()) + symbols.prefix(1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(viewModel.displayedMonth.formatted(EventFormatting.monthTitle))
                    .font(.headline)
                Spacer()
                Button(.local("Mois précédent"), systemImage: "chevron.left") { viewModel.showPreviousMonth() }
                    .disabled(!viewModel.canShowPreviousMonth)
                Button(.local("Mois suivant"), systemImage: "chevron.right") { viewModel.showNextMonth() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.caption.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                }
                ForEach(Array(viewModel.monthGrid.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = Calendar.paris.isDate(day, inSameDayAs: viewModel.selectedDay)
        let isSelectable = viewModel.isSelectable(day)
        return Button { viewModel.select(day: day) } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isSelected ? .heavy : .medium))
                Circle()
                    .fill(viewModel.hasEvents(on: day) ? (isSelected ? Color.white : Color.brandMagenta) : .clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(isSelected ? Color.white : !isSelectable || viewModel.isLibraryClosingDay(day) ? Color.inkSecondary : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background { if isSelected { Circle().fill(Color.brandViolet) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .opacity(isSelectable ? 1 : 0.4)
        .hoverEffect(.highlight)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Quand" shortcuts under the mini calendar.
struct QuickPeriods: View {
    let viewModel: AgendaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(String.local("Quand", comment: "Agenda period filters"))
            VStack(spacing: 0) {
                ForEach(AgendaPeriod.allCases) { period in
                    Button { viewModel.filters.period = period } label: {
                        HStack {
                            Text(period == .all ? String.local("Jour par jour") : period.label).foregroundStyle(Color.ink)
                            Spacer()
                            if viewModel.filters.period == period {
                                Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Color.brandViolet)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityAddTraits(viewModel.filters.period == period ? .isSelected : [])
                    if period != AgendaPeriod.allCases.last { Divider().padding(.leading, 14) }
                }
            }
            .cardStyle(padding: 0)
        }
    }
}

/// Grid of event cards, with the poster as background and a glass banner.
struct EventGrid: View {
    let events: [Event]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
            ForEach(events) { event in
                NavigationLink(value: event) { FeaturedEventCard(event: event, height: 300, compact: true) }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
            }
        }
    }
}

// MARK: - Cards

struct FeaturedEventCard: View {
    let event: Event
    var height: CGFloat = 340
    var compact = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // The poster fills the card without dictating its width (iPad grid).
            Color.clear.overlay { EventArtwork(event: event) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let type = event.type { StatusPill(type, style: .accent) }
                    if let audience = event.audience { StatusPill(audience, style: .accent) }
                }
                Text(event.title).font(compact ? .headline : .title2.weight(.heavy)).foregroundStyle(Color.ink).lineLimit(2)
                Text(EventFormatting.schedule(event)).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(10)
        }
        .frame(height: height)
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
    /// Times in the user's format ("10:30", "10:30 AM").
    static let time = Date.FormatStyle.dateTime.hour().minute()

    /// "Samedi 7 novembre", "Saturday, November 7": capitalized at the start of a title.
    static let dayTitle = sentenceCase(.dateTime.weekday(.wide).day().month(.wide))
    static let monthTitle = sentenceCase(.dateTime.month(.wide).year())

    private static func sentenceCase(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var style = style
        style.capitalizationContext = .beginningOfSentence
        return style
    }

    static func schedule(_ event: Event) -> String {
        guard let start = event.start else { return event.place ?? "" }
        var parts: [String]
        if event.isAllDay {
            parts = event.end.map { [String.local("Jusqu'au \($0.formatted(.dateTime.day().month(.wide)))", comment: "Last day of an exhibition")] } ?? []
        } else {
            let time = start.formatted(Self.time)
            parts = [event.end.map { "\(time) – \($0.formatted(Self.time))" } ?? time]
        }
        if let place = event.library?.shortName ?? event.place { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    AgendaView()
}
