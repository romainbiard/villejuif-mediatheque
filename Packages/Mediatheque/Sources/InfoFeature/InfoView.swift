import DesignSystem
import MapKit
import MediathequeCore
import SwiftUI

public struct InfoView: View {
    @State private var viewModel = InfoViewModel()
    @State private var selection: LibraryInfo.ID?
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    map
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle("Infos pratiques")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var map: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.790, longitude: 2.360),
            latitudinalMeters: 2_600,
            longitudinalMeters: 2_600
        ))) {
            ForEach(Library.allCases) { library in
                Marker(library.shortName, systemImage: "books.vertical", coordinate: library.mapCoordinate)
                    .tint(Color.brandViolet)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel("Carte des 3 médiathèques")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ForEach(0..<3, id: \.self) { _ in SkeletonRow().cardStyle() }
        case let .failed(error):
            EmptyStateView(
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: "Horaires indisponibles",
                message: "Vérifiez votre connexion, puis réessayez.",
                primary: ("Réessayer", { Task { await viewModel.load() } })
            )
        case let .loaded(libraries):
            ForEach(libraries) { library in
                LibraryCard(library: library, viewModel: viewModel, openURL: { openURL($0) })
            }
        }
    }
}

struct LibraryCard: View {
    let library: LibraryInfo
    let viewModel: InfoViewModel
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(library.name).font(.title3.weight(.heavy))
                Text(library.addressLines.joined(separator: ", ")).font(.subheadline).foregroundStyle(Color.inkSecondary)
            }
            StatusPill(viewModel.statusText(of: library), style: viewModel.isOpen(library) ? .success : .danger)

            HStack(spacing: 8) {
                action("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond", prominent: true) {
                    openURL(directionsURL)
                }
                if let phone = library.phone, let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                    action("Appeler", systemImage: "phone") { openURL(url) }
                }
                if let contact = library.contactURL {
                    action("Écrire", systemImage: "envelope") { openURL(contact) }
                }
            }

            VStack(spacing: 0) {
                ForEach(library.hourLines, id: \.self) { line in
                    let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    HStack {
                        Text(parts.first ?? line)
                        Spacer()
                        Text(parts.count > 1 ? parts[1] : "").monospacedDigit().foregroundStyle(Color.inkSecondary)
                    }
                    .font(.subheadline.weight(viewModel.isToday(line) ? .bold : .regular))
                    .padding(.vertical, 7)
                    if line != library.hourLines.last { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .cardStyle(padding: 16)
    }

    private var directionsURL: URL {
        let address = (library.addressLines.joined(separator: ", ")).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?daddr=\(address)")!
    }

    private func action(_ title: String, systemImage: String, prominent: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.body.weight(.semibold))
                Text(title).font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(prominent ? .white : Color.brandVioletDeep)
            .background(prominent ? Color.brandViolet : Color.soft(.brandViolet), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension Library {
    var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

#Preview {
    InfoView()
}
