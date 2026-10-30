import AccountFeature
import AgendaFeature
import DesignSystem
import DigitalFeature
import InfoFeature
import MediathequeCore
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
                AccountView()
            }
            Tab("Agenda", systemImage: "calendar", value: .agenda) {
                AgendaView()
            }
            Tab("Numérique", systemImage: "play.rectangle.on.rectangle", value: .digital) {
                DigitalView()
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

#Preview {
    RootTabView()
        .environment(SessionStore())
}
