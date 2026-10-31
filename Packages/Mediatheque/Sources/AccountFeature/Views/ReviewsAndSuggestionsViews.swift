import DesignSystem
import MediathequeCore
import SwiftUI

// MARK: - Mes avis

struct ReviewsView: View {
    enum Tab: Hashable { case toRate, published }

    @State private var viewModel = ReviewsViewModel()
    @State private var tab: Tab = .toRate
    @State private var draft: ReviewDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Avis", selection: $tab) {
                    Text("À noter").tag(Tab.toRate)
                    Text("Publiés").tag(Tab.published)
                }
                .pickerStyle(.segmented)
                switch tab {
                case .toRate: toRate
                case .published: published
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.surfaceGrouped)
        .navigationTitle("Mes avis")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $draft) { draft in
            ReviewSheet(draft: draft, isSubmitting: viewModel.isSubmitting) { rating, title, text in
                await viewModel.submit(draft.record, rating: rating, title: title, text: text)
            }
        }
        .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) { viewModel.dismissMessage() } }
        .sensoryFeedback(.selection, trigger: tab)
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    @ViewBuilder
    private var toRate: some View {
        switch viewModel.toRate {
        case .idle, .loading:
            VStack(spacing: 14) { ForEach(0..<3, id: \.self) { _ in SkeletonRow() } }.cardStyle()
        case let .failed(error):
            ProfileErrorState(error: error) { await viewModel.load() }
        case let .loaded(records) where records.isEmpty:
            EmptyStateView(
                systemImage: "star.bubble",
                title: "Rien à noter pour l'instant",
                message: "Vos documents empruntés apparaîtront ici pour que vous puissiez les noter.",
                tint: .brandYellow
            )
        case let .loaded(records):
            Text("Vos derniers emprunts. Une note suffit, le texte est facultatif.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
            VStack(spacing: 0) {
                ForEach(records) { record in
                    RecordToRateRow(record: record) { rating in draft = ReviewDraft(record: record, rating: rating) }
                    if record.id != records.last?.id { Divider().padding(.leading, 68) }
                }
            }
            .cardStyle(padding: 0)
        }
    }

    @ViewBuilder
    private var published: some View {
        switch viewModel.published {
        case .idle, .loading:
            VStack(spacing: 14) { ForEach(0..<2, id: \.self) { _ in SkeletonRow() } }.cardStyle()
        case let .failed(error):
            ProfileErrorState(error: error) { await viewModel.load() }
        case let .loaded(reviews) where reviews.isEmpty:
            EmptyStateView(
                systemImage: "heart.text.square",
                title: "Partagez vos coups de cœur",
                message: "Vos avis aident les autres lecteurs à choisir. Ils sont publiés après validation par la médiathèque.",
                tint: .brandMagenta,
                primary: ("Noter mes derniers prêts", { tab = .toRate })
            )
        case let .loaded(reviews):
            VStack(spacing: 0) {
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(review.title).font(.headline)
                        if let rating = review.rating { StarsView(rating: rating) }
                        if !review.text.isEmpty {
                            Text(review.text).font(.subheadline).foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    if review.id != reviews.last?.id { Divider().padding(.leading, 14) }
                }
            }
            .cardStyle(padding: 0)
        }
    }
}

struct ReviewDraft: Identifiable {
    let record: RecordToRate
    let rating: Int
    var id: Int { record.id }
}

struct RecordToRateRow: View {
    let record: RecordToRate
    let rate: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: record.coverURL, title: record.title, seed: record.recordID)
                .frame(width: 44, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).font(.headline).lineLimit(2)
                    if let author = record.author {
                        Text(author).font(.subheadline).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                }
                StarRatingInput(rating: 0, size: .title3, onChange: rate)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

/// Cinq étoiles à toucher. Chaque étoile est un bouton pour VoiceOver.
struct StarRatingInput: View {
    var rating: Int
    var size: Font = .title2
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    onChange(value)
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(size)
                        .foregroundStyle(value <= rating ? Color.brandYellow : Color.inkSecondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) étoile\(value > 1 ? "s" : "") sur 5")
                .accessibilityAddTraits(value == rating ? .isSelected : [])
            }
        }
    }
}

struct StarsView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(value <= rating ? Color.brandYellow : Color.inkSecondary.opacity(0.4))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(rating) étoile\(rating > 1 ? "s" : "") sur 5")
    }
}

struct ReviewSheet: View {
    let draft: ReviewDraft
    let isSubmitting: Bool
    let submit: (Int, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int
    @State private var title = ""
    @State private var text = ""

    init(draft: ReviewDraft, isSubmitting: Bool, submit: @escaping (Int, String, String) async -> Bool) {
        self.draft = draft
        self.isSubmitting = isSubmitting
        self.submit = submit
        _rating = State(initialValue: draft.rating)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CoverImage(url: draft.record.coverURL, title: draft.record.title, seed: draft.record.recordID)
                            .frame(width: 44, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.record.title).font(.headline)
                            if let author = draft.record.author {
                                Text(author).font(.subheadline).foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }
                    StarRatingInput(rating: rating) { rating = $0 }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                Section {
                    TextField("Titre (facultatif)", text: $title)
                    TextField("Votre avis (facultatif)", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                } footer: {
                    Text("Votre avis est publié sous votre pseudo, après validation par la médiathèque.")
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Donner mon avis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Envoyer") {
                            Task { if await submit(rating, title, text) { dismiss() } }
                        }
                        .disabled(rating == 0)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.impact(weight: .light), trigger: rating)
    }
}

// MARK: - Mes suggestions

struct SuggestionsView: View {
    @State private var viewModel = SuggestionsViewModel()
    @State private var showsScanner = false
    @FocusState private var focused: Field?

    enum Field: Hashable { case title, author, isbn, comment }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Un document manque au catalogue ? Proposez-le : la médiathèque étudie chaque suggestion.")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                form
                SectionHeader("Envoyées")
                sent
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .dismissesKeyboardOnTap()
        .background(Color.surfaceGrouped)
        .navigationTitle("Mes suggestions")
        .scrollDismissesKeyboard(.interactively)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .overlay(alignment: .bottom) { MessageToast(message: viewModel.message) { viewModel.dismissMessage() } }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
        #if canImport(VisionKit) && os(iOS)
        .fullScreenCover(isPresented: $showsScanner) {
            CardScannerView(prompt: "Visez le code-barres au dos du livre", detectedTitle: "ISBN détecté") { value in
                viewModel.draft.isbn = value
            }
        }
        #endif
    }

    private var form: some View {
        @Bindable var model = viewModel
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Type de document", selection: $model.draft.kind) {
                ForEach(SuggestionKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(.brandViolet)

            field("Titre", text: $model.draft.title, field: .title, required: true)
            field("Auteur", text: $model.draft.author, field: .author, required: true)
            HStack {
                field("ISBN ou code-barres", text: $model.draft.isbn, field: .isbn, required: false)
                    .keyboardType(.numbersAndPunctuation)
                #if canImport(VisionKit) && os(iOS)
                if CardScannerView.isAvailable {
                    Button("Scanner l'ISBN", systemImage: "barcode.viewfinder") { showsScanner = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                }
                #endif
            }
            TextField("Commentaire (facultatif)", text: $model.draft.comment, axis: .vertical)
                .lineLimit(2...5)
                .focused($focused, equals: .comment)
                .padding(12)
                .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                focused = nil
                Task { await model.send() }
            } label: {
                Text("Envoyer la suggestion").frame(maxWidth: .infinity)
            }
            .buttonStyle(.prominent(size: .large, isLoading: model.isSending))
            .disabled(!model.draft.isValid || model.isSending)
        }
        .cardStyle()
    }

    private func field(_ label: String, text: Binding<String>, field: Field, required: Bool) -> some View {
        TextField(required ? "\(label) *" : label, text: text)
            .focused($focused, equals: field)
            .submitLabel(.next)
            .padding(12)
            .background(Color.surfaceGrouped, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(required ? "\(label), obligatoire" : label)
    }

    @ViewBuilder
    private var sent: some View {
        switch viewModel.sent {
        case .idle, .loading:
            SkeletonRow().cardStyle()
        case .failed:
            Text("La liste de vos suggestions n'a pas pu être chargée.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        case let .loaded(suggestions) where suggestions.isEmpty:
            Text("Vos suggestions envoyées apparaîtront ici.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        case let .loaded(suggestions):
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).font(.headline)
                        if let detail = suggestion.detail {
                            Text(detail).font(.subheadline).foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    if suggestion.id != suggestions.last?.id { Divider().padding(.leading, 14) }
                }
            }
            .cardStyle(padding: 0)
        }
    }
}
