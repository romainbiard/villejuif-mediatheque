import DesignSystem
import MediathequeCore
import SwiftUI

struct AgendaFiltersView: View {
    let viewModel: AgendaViewModel
    @State private var draft: AgendaFilters
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AgendaViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.filters)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Lieu", values: viewModel.availablePlaces, selection: $draft.places)
                    group("Type d'animation", values: viewModel.availableTypes, selection: $draft.types)
                    group("Public", values: viewModel.availableAudiences, selection: $draft.audiences)
                }
                .padding(16)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Réinitialiser") { draft = AgendaFilters() }.disabled(draft.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    viewModel.filters = draft
                    dismiss()
                } label: {
                    let count = viewModel.upcomingCount(with: draft)
                    Text(count == 0 ? "Aucun événement" : "Voir \(count) événement\(count > 1 ? "s" : "")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.brandViolet)
                .controlSize(.extraLarge)
                .padding(16)
            }
        }
        .sensoryFeedback(.selection, trigger: draft)
    }

    private func group(_ title: String, values: [String], selection: Binding<Set<String>>) -> some View {
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

/// Disposition en lignes qui passent à la ligne, pour les puces de filtres.
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
