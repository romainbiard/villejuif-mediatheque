// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

/// "Où voulez-vous le retirer ?" sheet, then confirmation.
struct HoldSheet: View {
    @State private var viewModel: HoldViewModel
    @Environment(\.dismiss) private var dismiss

    init(notice: Notice, defaultPickup: Library?) {
        _viewModel = State(initialValue: HoldViewModel(notice: notice, defaultPickup: defaultPickup))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    CoverImage(url: viewModel.notice.coverURL, title: viewModel.notice.title, seed: viewModel.notice.id)
                        .frame(width: 44, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.notice.title).font(.headline).lineLimit(2)
                        Text(viewModel.notice.authors.first ?? viewModel.notice.kind.label)
                            .font(.subheadline).foregroundStyle(Color.inkSecondary)
                    }
                }
                .cardStyle(padding: 12)

                content
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.surfaceGrouped)
            .navigationTitle("Réserver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await viewModel.prepare() }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .preparing:
            ProgressView("Recherche des lieux de retrait…").frame(maxWidth: .infinity).padding(.top, 20)
        case let .choosing(request), let .submitting(request):
            Text("Où voulez-vous le retirer ?").font(.headline)
            VStack(spacing: 0) {
                ForEach(request.pickupLibraries) { library in
                    Button { viewModel.pickup = library } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(library.name).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                                if library == request.defaultPickup {
                                    Text("Votre médiathèque").font(.footnote).foregroundStyle(Color.inkSecondary)
                                }
                            }
                            Spacer()
                            Image(systemName: viewModel.pickup == library ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(viewModel.pickup == library ? Color.brandViolet : Color.inkSecondary.opacity(0.4))
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.pickup == library ? .isSelected : [])
                    if library != request.pickupLibraries.last { Divider().padding(.leading, 14) }
                }
            }
            .cardStyle(padding: 0)

            Button {
                Task { await viewModel.submit() }
            } label: {
                Text("Confirmer la réservation").frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent(isLoading: viewModel.isSubmitting))
            .disabled(viewModel.pickup == nil || viewModel.isSubmitting)
        case let .confirmed(message, pickup):
            VStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.statusSuccess, in: Circle())
                Text("Réservation enregistrée").font(.title2.weight(.heavy))
                Text("Retrait à \(pickup.shortName). \(message.components(separatedBy: "\n").dropFirst().joined(separator: " "))")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.inkSecondary)
                Button("Fermer") { dismiss() }
                    .buttonStyle(.prominent(size: .large))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        case let .failed(message):
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Réservation impossible",
                message: message,
                tint: .statusDanger,
                primary: ("Réessayer", { Task { await viewModel.prepare() } })
            )
        }
    }
}
