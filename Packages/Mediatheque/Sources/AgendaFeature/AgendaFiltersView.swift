// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

struct AgendaFiltersView: View {
    let viewModel: AgendaViewModel
    @State private var draft: AgendaFilters
    @State private var showsAllPlaces = false
    @Environment(\.dismiss) private var dismiss

    /// Libraries first; other venues (schools, parks…) are collapsed beyond them.
    static let visiblePlaces = 4

    init(viewModel: AgendaViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.filters)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    periodGroup
                    group(.local("Lieu", comment: "Filter group: event venue"), values: visiblePlaces, selection: $draft.places)
                    if hiddenPlaceCount > 0 {
                        Button(showsAllPlaces ? LocalizedStringResource.local("Moins de lieux") : .local("+ \(hiddenPlaceCount) autres lieux", comment: "Shows the collapsed venues")) {
                            withAnimation { showsAllPlaces.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(.brandViolet)
                        .padding(.top, -12)
                    }
                    group(.local("Type d'animation"), values: viewModel.availableTypes, selection: $draft.types)
                    group(.local("Public", comment: "Filter group: event audience"), values: viewModel.availableAudiences, selection: $draft.audiences)
                }
                .padding(16)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle(Text(.local("Filtres")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(.local("Annuler")) { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button(.local("Réinitialiser")) { draft = AgendaFilters() }.disabled(draft.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    viewModel.filters = draft
                    dismiss()
                } label: {
                    let count = viewModel.upcomingCount(with: draft)
                    Text(count == 0 ? LocalizedStringResource.local("Aucun événement") : .local("Voir \(count) événements", comment: "Button applying the filters"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.prominent())
                .padding(16)
            }
        }
        .sensoryFeedback(.selection, trigger: draft)
    }

    /// Collapsed venues stay visible when they are checked.
    private var visiblePlaces: [String] {
        let all = viewModel.availablePlaces
        guard !showsAllPlaces, all.count > Self.visiblePlaces + 1 else { return all }
        return all.enumerated().filter { $0.offset < Self.visiblePlaces || draft.places.contains($0.element) }.map(\.element)
    }

    private var hiddenPlaceCount: Int {
        showsAllPlaces ? 0 : viewModel.availablePlaces.count - visiblePlaces.count
    }

    private var periodGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.local("Quand", comment: "Agenda period filters")).font(.footnote.weight(.bold)).foregroundStyle(Color.inkSecondary).textCase(.uppercase)
            FlowLayout(spacing: 8) {
                ForEach(AgendaPeriod.allCases) { period in
                    let isOn = draft.period == period
                    Button { draft.period = period } label: {
                        Label(period.label, systemImage: "checkmark").labelStyle(FilterChipLabelStyle(isOn: isOn))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private func group(_ title: LocalizedStringResource, values: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.footnote.weight(.bold)).foregroundStyle(Color.inkSecondary).textCase(.uppercase)
            FlowLayout(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    let isOn = selection.wrappedValue.contains(value)
                    Button {
                        if isOn { selection.wrappedValue.remove(value) } else { selection.wrappedValue.insert(value) }
                    } label: {
                        Label(value, systemImage: "checkmark")
                            .labelStyle(FilterChipLabelStyle(isOn: isOn))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}

struct FilterChipLabelStyle: LabelStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if isOn { configuration.icon.font(.caption.weight(.heavy)) }
            configuration.title
        }
        .font(.subheadline.weight(isOn ? .bold : .medium))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(isOn ? Color.brandViolet : Color.surfaceCard, in: Capsule())
        .foregroundStyle(isOn ? .white : Color.ink)
    }
}

/// Wrapping row layout for the filter chips.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
