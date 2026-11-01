// Ma médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import DesignSystem
import MediathequeCore
import SwiftUI

/// Sheet opened by the Mon compte bell.
struct NotificationsView: View {
    let openSettings: () -> Void
    @State private var viewModel = NotificationsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.inbox.items.isEmpty {
                        EmptyStateView(
                            systemImage: "bell",
                            title: "Rien de nouveau",
                            message: "Les rappels de retour, les réservations arrivées et les messages de la médiathèque apparaîtront ici.",
                            primary: ("Régler les notifications", openSettings)
                        )
                    } else {
                        ForEach(viewModel.sections) { section in
                            Text(section.title)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.inkSecondary)
                                .textCase(.uppercase)
                                .padding(.top, 6)
                            VStack(spacing: 0) {
                                ForEach(section.items) { item in
                                    NotificationRow(item: item, viewModel: viewModel)
                                    if item.id != section.items.last?.id { Divider().padding(.leading, 64) }
                                }
                            }
                            .cardStyle(padding: 0)
                        }
                        Text("Historique gardé \(Inbox.retentionDays) jours sur cet appareil.")
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.surfaceGrouped)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Tout lire") { viewModel.markAllRead() }
                        .disabled(viewModel.inbox.unreadCount == 0)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Réglages des notifications", systemImage: "gearshape", action: openSettings)
                }
            }
            .onAppear { viewModel.load() }
            .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) { viewModel.dismissMessage() } }
            .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
        }
    }
}

struct NotificationRow: View {
    let item: InboxItem
    let viewModel: NotificationsViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: style.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.tint)
                .frame(width: 38, height: 38)
                .background(Color.soft(style.tint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).font(.subheadline.weight(item.isRead ? .semibold : .bold))
                    Spacer(minLength: 4)
                    Text(item.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Color.inkSecondary)
                }
                Text(item.body).font(.footnote).foregroundStyle(Color.inkSecondary)
                if viewModel.canRenew(item) {
                    renewButton.padding(.top, 2)
                }
            }
        }
        .padding(12)
        .overlay(alignment: .topLeading) {
            if !item.isRead {
                Circle().fill(Color.brandMagenta).frame(width: 8, height: 8).padding(6).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.markRead(item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isRead ? item.title : "Non lu, \(item.title)")
        .accessibilityAction(named: "Marquer comme lu") { viewModel.markRead(item) }
    }

    @ViewBuilder
    private var renewButton: some View {
        if let loanID = item.loanID, viewModel.renewing.contains(loanID) {
            ProgressView()
        } else {
            Button("Prolonger") { Task { await viewModel.renew(item) } }
                .buttonStyle(.glass)
                .tint(.brandVioletDeep)
                .font(.footnote.weight(.bold))
        }
    }

    private var style: (icon: String, tint: Color) {
        switch item.kind {
        case .loanLate: ("exclamationmark.circle.fill", .statusDanger)
        case .loanDueSoon: ("calendar.badge.clock", .statusWarning)
        case .holdReady: ("shippingbox.fill", .statusSuccess)
        case .libraryMessage: ("text.bubble.fill", .brandViolet)
        }
    }
}
