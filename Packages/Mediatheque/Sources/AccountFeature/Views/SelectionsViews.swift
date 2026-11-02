// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

// MARK: - My selections

struct SelectionsView: View {
    @State private var viewModel = SelectionsViewModel()
    @State private var showsCreate = false
    @State private var newName = ""

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
        .navigationTitle(Text(.local("Mes sélections")))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(.local("Nouvelle sélection"), systemImage: "plus") { showsCreate = true }
                    .disabled(viewModel.isCreating || viewModel.state.value == nil)
            }
        }
        .alert(Text(.local("Nouvelle sélection")), isPresented: $showsCreate) {
            TextField(text: $newName) { Text(.local("Nom de la sélection")) }
            Button(.local("Créer")) {
                let name = newName
                newName = ""
                Task { await viewModel.create(named: name) }
            }
            Button(.local("Annuler"), role: .cancel) { newName = "" }
        } message: {
            Text(.local("Par exemple « Vacances » ou « Idées cadeaux »."))
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
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.surfaceCard).frame(height: 190)
                }
            }
            .redacted(reason: .placeholder)
        case let .failed(error):
            EmptyStateView(error: error) { await viewModel.load() }
        case let .loaded(selections):
            if selections.allSatisfy({ $0.count == 0 }) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.fill").font(.title3).foregroundStyle(Color.brandMagenta)
                    Text(.local("Touchez le cœur sur la fiche d'un document pour l'ajouter à « Mes préférés »."))
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                }
                .cardStyle()
            }
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(selections) { selection in
                    NavigationLink(value: AccountRoute.selection(selection)) {
                        SelectionTile(selection: selection)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
}

struct SelectionTile: View {
    let selection: Selection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mosaic
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .background(Color.soft(tint), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.name).font(.headline).foregroundStyle(Color.ink).lineLimit(1)
                Text(subtitle).font(.footnote).foregroundStyle(Color.inkSecondary).lineLimit(1)
            }
        }
        .padding(10)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mosaic: some View {
        if selection.coverURLs.isEmpty {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(tint)
        } else {
            HStack(spacing: -18) {
                ForEach(Array(selection.coverURLs.prefix(3).enumerated()), id: \.offset) { index, url in
                    CoverImage(url: url, title: selection.name, seed: selection.id + index)
                        .frame(width: 58, height: 86)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .zIndex(Double(3 - index))
                }
            }
        }
    }

    private var subtitle: String {
        let count = selection.count == 0 ? String.local("Vide") : String.local("\(selection.count) documents")
        guard let updatedAt = selection.updatedAt, selection.count > 0 else { return count }
        return "\(count) · \(updatedAt.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var icon: String {
        switch selection.name {
        case "Mes préférés": "heart.fill"
        case "Déjà lu": "checkmark.circle.fill"
        case "À lire": "bookmark.fill"
        default: "list.star"
        }
    }

    private var tint: Color {
        switch selection.name {
        case "Mes préférés": .brandMagenta
        case "Déjà lu": .statusSuccess
        case "À lire": .brandViolet
        default: .brandVioletDeep
        }
    }
}

// MARK: - Selection contents

struct SelectionDetailView: View {
    @State private var viewModel: SelectionDetailViewModel

    init(selection: Selection) {
        _viewModel = State(initialValue: SelectionDetailViewModel(selection: selection))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ScrollView {
                    VStack(spacing: 14) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }
                        .cardStyle()
                        .padding(16)
                }
            case let .failed(error):
                ScrollView { EmptyStateView(error: error) { await viewModel.load() }.padding(16) }
            case let .loaded(notices) where notices.isEmpty:
                ScrollView {
                    EmptyStateView(
                        systemImage: "heart",
                        title: .local("Sélection vide"),
                        message: .local("Ajoutez des documents depuis leur fiche, avec le cœur ou le menu Partager."),
                        tint: .brandMagenta
                    )
                    .padding(16)
                }
            case let .loaded(notices):
                List {
                    ForEach(notices) { notice in
                        NavigationLink(value: AccountRoute.notice(notice)) {
                            SelectionNoticeRow(notice: notice, isRemoving: viewModel.removing.contains(notice.id))
                        }
                        .listRowBackground(Color.surfaceCard)
                        .disabled(viewModel.removing.contains(notice.id))
                        .swipeActions {
                            Button(.local("Retirer"), systemImage: "trash", role: .destructive) {
                                Task { await viewModel.remove(notice) }
                            }
                        }
                        .contextMenu {
                            Button(.local("Retirer de la sélection"), systemImage: "trash", role: .destructive) {
                                Task { await viewModel.remove(notice) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .readableContentWidth()
        .background(Color.surfaceGrouped)
        .navigationTitle(viewModel.selection.name)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) { viewModel.dismissMessage() } }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }
}

struct SelectionNoticeRow: View {
    let notice: Notice
    let isRemoving: Bool

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: notice.coverURL, title: notice.title, seed: notice.id)
                .frame(width: 44, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title).font(.headline).lineLimit(2)
                Text([notice.authors.first, notice.year].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isRemoving { ProgressView() }
        }
        .opacity(isRemoving ? 0.5 : 1)
    }
}
