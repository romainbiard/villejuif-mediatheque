import DesignSystem
import MapKit
import MediathequeCore
import SwiftUI

public struct EventDetailView: View {
    @State private var viewModel: EventDetailViewModel
    @Environment(\.openURL) private var openURL

    public init(event: Event) {
        _viewModel = State(initialValue: EventDetailViewModel(event: event))
    }

    private var event: Event { viewModel.event }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EventArtwork(event: event)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if let type = event.type { StatusPill(type, style: .accent) }
                        if let audience = event.audience { StatusPill(audience, style: .accent) }
                    }
                    Text(event.title).font(.title.weight(.heavy))
                    if let sentence = event.dateDescription {
                        Label(sentence, systemImage: "calendar").font(.subheadline.weight(.medium))
                    }
                    if let place = event.place {
                        Label(event.library?.name ?? place, systemImage: "mappin.and.ellipse").font(.subheadline.weight(.medium))
                    }
                }

                Button {
                    openURL(viewModel.iCalURL)
                } label: {
                    Label("Ajouter au calendrier", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.brandViolet)
                .controlSize(.large)

                switch viewModel.detail {
                case .idle, .loading:
                    SkeletonRow()
                case .failed:
                    EmptyView()
                case let .loaded(detail):
                    if let text = detail.descriptionText {
                        Text(text).font(.body).foregroundStyle(Color.ink)
                    }
                    if let latitude = detail.latitude, let longitude = detail.longitude {
                        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))) {
                            Marker(event.place ?? event.title, coordinate: coordinate).tint(Color.brandViolet)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .allowsHitTesting(false)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.surfaceGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: "https://mediatheque.villejuif.fr/cms/articleview/id/\(event.id)")!, subject: Text(event.title))
            }
        }
        .task { await viewModel.load() }
    }
}
