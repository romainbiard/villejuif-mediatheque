import AgendaFeature
import DesignSystem
import InfoFeature
import SearchFeature
import SwiftUI

enum AppTab: Hashable {
    case account, agenda, digital, info, search
}

/// Barre d'onglets iOS 26 : Liquid Glass flottante, Recherche en onglet de rôle `.search`
/// (champ en bas sur iPhone), et barre latérale adaptable sur iPad.
struct RootTabView: View {
    @State private var selection: AppTab = .account

    var body: some View {
        TabView(selection: $selection) {
            Tab("Compte", systemImage: "person.crop.circle", value: .account) {
                ComingSoonView(
                    title: "Mon compte",
                    systemImage: "person.crop.circle",
                    message: "Prêts, réservations et carte d'abonné arrivent dans la prochaine version."
                )
            }
            Tab("Agenda", systemImage: "calendar", value: .agenda) {
                AgendaView()
            }
            Tab("Numérique", systemImage: "play.rectangle.on.rectangle", value: .digital) {
                ComingSoonView(
                    title: "Numérique",
                    systemImage: "play.rectangle.on.rectangle",
                    message: "Arte VOD, Cafeyn, Mozaik, musicMe et les e-books, inclus dans votre abonnement."
                )
            }
            Tab("Infos", systemImage: "mappin.and.ellipse", value: .info) {
                InfoView()
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.brandViolet)
    }
}

/// Onglets prévus en P3 (compte) et P4 (numérique).
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ScrollView {
                EmptyStateView(systemImage: systemImage, title: "Bientôt disponible", message: message)
                    .padding(16)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle(title)
        }
    }
}

#Preview {
    RootTabView()
}
