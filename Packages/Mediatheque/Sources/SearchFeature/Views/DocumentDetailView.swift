// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

public struct DocumentDetailView: View {
    @State private var viewModel: DocumentDetailViewModel
    @State private var showsHold = false
    @State private var showsLoginHint = false
    @Environment(SessionStore.self) private var session

    public init(document: Notice) {
        _viewModel = State(initialValue: DocumentDetailViewModel(document: document))
    }

    private var document: Notice { viewModel.document }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 24) {
                    identity
                    if !document.kind.isDigital { reserveButton }
                    if document.kind.isDigital {
                        onlineCard
                    } else {
                        whereToFind
                    }
                    information
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .background(Color.surfaceGrouped, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
                .offset(y: -32)
                .padding(.bottom, -32)
            }
        }
        .background(Color.surfaceGrouped)
        .ignoresSafeArea(edges: .top)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let permalink = document.permalink {
                    ShareLink(item: permalink, subject: Text(document.title))
                }
            }
        }
        .sheet(isPresented: $showsHold) {
            HoldSheet(notice: document, defaultPickup: session.patron?.homeLibrary)
        }
        .alert(Text(.local("Connectez-vous pour réserver")), isPresented: $showsLoginHint) {
            Button(role: .cancel) {} label: { Text(.local("OK")) }
        } message: {
            Text(.local("Ouvrez l'onglet Compte et connectez-vous avec votre carte d'abonné."))
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var header: some View {
        let colors = BrandArtwork.colors(for: document.id)
        return ZStack {
            colors.background
            Circle().fill(colors.shape).frame(width: 320).offset(x: 140, y: -120)
            CoverImage(url: document.coverURL, title: document.title, seed: document.id &+ 1)
                .frame(width: 160, height: 236)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 16)
                .padding(.top, 60)
        }
        .frame(height: 400)
        .clipped()
    }

    @ViewBuilder
    private var reserveButton: some View {
        if session.patron?.permissions.holdForbidden == true {
            Label(.local("Les réservations sont suspendues sur votre compte. Renseignez-vous à l'accueil."), systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        } else {
            Button {
                if session.patron == nil { showsLoginHint = true } else { showsHold = true }
            } label: {
                Label(.local("Réserver", comment: "Button: place a hold on the item"), systemImage: "bookmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent())
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StatusPill(document.kind.label, style: .accent)
                if let volume = document.volume, !volume.isEmpty { StatusPill(
                    String.local("Tome \(volume)", comment: "Volume number in a series"),
                    style: .accent
                ) }
            }
            Text(document.title).font(.title.weight(.heavy)).foregroundStyle(Color.ink)
            Text([document.authors.joined(separator: ", "), document.publisher].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private var whereToFind: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(String.local("Où le trouver"))
            switch viewModel.copies {
            case .idle, .loading:
                VStack(spacing: 14) { ForEach(0..<2, id: \.self) { _ in SkeletonRow() } }.cardStyle()
            case .failed:
                Text(.local("Disponibilité indisponible pour le moment.")).foregroundStyle(Color.inkSecondary).cardStyle()
            case let .loaded(copies) where copies.isEmpty:
                Text(.local("Aucun exemplaire en rayon.")).foregroundStyle(Color.inkSecondary).cardStyle()
            case .loaded:
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.copiesByLibrary.enumerated()), id: \.element.name) { index, group in
                        ForEach(Array(group.copies.enumerated()), id: \.offset) { _, copy in
                            CopyRow(copy: copy)
                        }
                        if index < viewModel.copiesByLibrary.count - 1 { Divider().padding(.leading, 36) }
                    }
                }
                .cardStyle(padding: 0)
            }
        }
    }

    private var onlineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(.local("Disponible en ligne"), systemImage: "play.rectangle.on.rectangle")
                .font(.headline)
            Text(.local("Cette ressource est incluse dans votre abonnement. Ouvrez-la depuis l'onglet Numérique."))
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        }
        .cardStyle()
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(String.local("Informations"))
            VStack(spacing: 0) {
                InfoLine(label: .local("Type", comment: "Item details: kind of item"), value: document.kind.label)
                if let publisher = document.publisher { InfoLine(label: .local("Éditeur"), value: publisher) }
                if let year = document.year { InfoLine(label: .local("Année"), value: year) }
                if let series = document.series {
                    InfoLine(
                        label: .local("Série"),
                        value: [series, document.volume.map { String.local("tome \($0)", comment: "Volume number, after the series name") }].compactMap(\.self)
                            .joined(separator: ", ")
                    )
                }
            }
            .cardStyle(padding: 0)
        }
    }
}

struct CopyRow: View {
    let copy: LiveCopy

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(copy.status.isAvailable ? Color.statusSuccess : .clear)
                .strokeBorder(copy.status.isAvailable ? .clear : Color.inkSecondary, lineWidth: 2)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.library?.name ?? copy.libraryName).font(.headline)
                Text(details).font(.subheadline).foregroundStyle(Color.inkSecondary)
            }
            Spacer()
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [copy.statusLabel]
        if case let .onLoan(dueDate?) = copy.status {
            parts = [String.local("En prêt · retour prévu le \(dueDate.formatted(.dateTime.day().month(.wide)))")]
        }
        parts += [copy.section, copy.shelfMark].compactMap(\.self)
        if copy.holdCount > 0 { parts.append(String.local("\(copy.holdCount) réservations", comment: "Number of holds on a copy")) }
        return parts.joined(separator: " · ")
    }
}

struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Color.inkSecondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

#Preview {
    NavigationStack { DocumentDetailView(document: SampleData.documents[0]) }
        .environment(SessionStore())
}
