// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

struct LoansView: View {
    @State private var viewModel = LoansViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .readableContentWidth()
        .background(Color.surfaceGrouped)
        .navigationTitle(Text(.local("Mes prêts")))
        .toolbar {
            if let loans = viewModel.state.value, loans.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(.local("Tout prolonger")) { Task { await viewModel.renewAll() } }
                        .disabled(!viewModel.renewing.isEmpty)
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) { viewModel.dismissMessage() } }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 14) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }.cardStyle()
        case let .failed(error):
            EmptyStateView(
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: error == .offline ? String.local("Pas de connexion") : String.local("Le site de la médiathèque ne répond pas"),
                message: .local("Vérifiez votre connexion, puis réessayez."),
                primary: (String.local("Réessayer"), { Task { await viewModel.load() } })
            )
        case let .loaded(loans) where loans.isEmpty:
            EmptyStateView(
                systemImage: "books.vertical",
                title: .local("Rien à rendre pour l'instant"),
                message: .local("Vos emprunts apparaîtront ici avec leur date de retour.")
            )
        case .loaded:
            ForEach(viewModel.sections) { section in
                Text(section.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(section.kind == .late ? Color.statusDanger : Color.inkSecondary)
                    .textCase(.uppercase)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(section.loans) { loan in
                        LoanRow(loan: loan, viewModel: viewModel)
                        if loan.id != section.loans.last?.id { Divider().padding(.leading, 76) }
                    }
                }
                .cardStyle(padding: 0)
            }
        }
    }
}

struct LoanRow: View {
    let loan: Loan
    let viewModel: LoansViewModel

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: loan.coverURL, title: loan.title, seed: loan.recordID ?? loan.id.hashValue)
                .frame(width: 48, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(loan.title).font(.headline).lineLimit(2)
                Text([loan.author, loan.library?.shortName ?? loan.libraryName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
                dueBadge
            }
            Spacer(minLength: 0)
            renewButton
        }
        .padding(12)
    }

    @ViewBuilder
    private var dueBadge: some View {
        let date = loan.dueDate.formatted(.dateTime.day().month(.abbreviated))
        switch viewModel.dueState(of: loan) {
        case let .late(days):
            StatusPill(.local("En retard de \(days) jours"), style: .danger)
        case let .dueSoon(days):
            StatusPill(days == 0 ? String.local("À rendre aujourd'hui") : String.local("À rendre le \(date)"), style: .warning)
        case .onTime:
            StatusPill(.local("À rendre le \(date)"), style: .success)
        }
    }

    @ViewBuilder
    private var renewButton: some View {
        if viewModel.renewing.contains(loan.id) {
            ProgressView()
        } else if viewModel.refused.contains(loan.id) {
            Text(.local("Non\nprolongeable")).font(.caption).multilineTextAlignment(.trailing).foregroundStyle(Color.inkSecondary)
        } else {
            Button(.local("Prolonger")) { Task { await viewModel.renew(loan) } }
                .buttonStyle(.glass)
                .tint(.brandVioletDeep)
                .font(.subheadline.weight(.bold))
        }
    }
}

struct HoldsView: View {
    @State private var viewModel = HoldsViewModel()
    @State private var pendingCancel: Hold?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .readableContentWidth()
        .background(Color.surfaceGrouped)
        .navigationTitle(Text(.local("Mes réservations")))
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .confirmationDialog(
            Text(.local("Annuler la réservation de « \(pendingCancel?.title ?? "") » ?")),
            isPresented: Binding(get: { pendingCancel != nil }, set: { if !$0 { pendingCancel = nil } }),
            titleVisibility: .visible
        ) {
            Button(.local("Annuler la réservation"), role: .destructive) {
                if let hold = pendingCancel { Task { await viewModel.cancel(hold) } }
            }
            Button(.local("Garder"), role: .cancel) {}
        }
        .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) {} }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 14) { ForEach(0..<2, id: \.self) { _ in SkeletonRow() } }.cardStyle()
        case let .failed(error):
            EmptyStateView(
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                title: error == .offline ? String.local("Pas de connexion") : String.local("Le site de la médiathèque ne répond pas"),
                message: .local("Vérifiez votre connexion, puis réessayez."),
                primary: (String.local("Réessayer"), { Task { await viewModel.load() } })
            )
        case let .loaded(holds) where holds.isEmpty:
            EmptyStateView(
                systemImage: "bookmark",
                title: .local("Aucune réservation"),
                message: .local("Un document est emprunté ? Réservez-le depuis sa fiche et choisissez où le retirer."),
                tint: .statusSuccess
            )
        case .loaded:
            if !viewModel.ready.isEmpty {
                sectionTitle(.local("Prêtes à retirer"), color: .statusSuccess)
                ForEach(viewModel.ready) { hold in
                    HoldRow(hold: hold, isCancelling: viewModel.cancelling.contains(hold.id)) { pendingCancel = hold }
                        .cardStyle(padding: 0)
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.statusSuccess, lineWidth: 1.5))
                }
            }
            if !viewModel.waiting.isEmpty {
                sectionTitle(.local("En attente"), color: .inkSecondary)
                VStack(spacing: 0) {
                    ForEach(viewModel.waiting) { hold in
                        HoldRow(hold: hold, isCancelling: viewModel.cancelling.contains(hold.id)) { pendingCancel = hold }
                        if hold.id != viewModel.waiting.last?.id { Divider().padding(.leading, 76) }
                    }
                }
                .cardStyle(padding: 0)
            }
        }
    }

    private func sectionTitle(_ title: String, color: Color) -> some View {
        Text(title).font(.footnote.weight(.bold)).foregroundStyle(color).textCase(.uppercase).padding(.top, 6)
    }
}

struct HoldRow: View {
    let hold: Hold
    let isCancelling: Bool
    let cancel: () -> Void

    /// "Pas avant le 14 nov." rather than the site's raw text when a date is given.
    private var statusText: String {
        guard !hold.isReadyForPickup, let date = hold.expectedDate else { return hold.statusText }
        return .local("Pas avant le \(date.formatted(.dateTime.day().month(.abbreviated)))")
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: hold.coverURL, title: hold.title, seed: hold.recordID ?? 0).frame(width: 48, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(hold.title).font(.headline).lineLimit(2)
                Text(.local("Retrait à \(hold.pickupLibrary?.shortName ?? hold.pickupLibraryName)"))
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                HStack(spacing: 6) {
                    StatusPill(statusText, style: hold.isReadyForPickup ? .success : .accent)
                    if let rank = hold.rank, !hold.isReadyForPickup {
                        StatusPill(.local("Rang \(rank)"), style: .neutral)
                    }
                }
            }
            Spacer(minLength: 0)
            if isCancelling {
                ProgressView()
            } else {
                Menu {
                    Button(.local("Annuler la réservation"), systemImage: "xmark.circle", role: .destructive, action: cancel)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Color.inkSecondary)
                }
                .accessibilityLabel(Text(.local("Actions pour \(hold.title)")))
            }
        }
        .padding(12)
    }
}

/// Temporary glass message at the bottom of the screen.
struct MessageToast: View {
    let message: String?
    let dismiss: () -> Void

    var body: some View {
        if let message {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(3))
                    dismiss()
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
