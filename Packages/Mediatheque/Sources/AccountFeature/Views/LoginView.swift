import DesignSystem
import MediathequeCore
import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = LoginViewModel()
    @State private var showsLostPassword = false
    @FocusState private var focus: Field?

    enum Field { case card, password }

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    VillejuifLogo.white
                        .resizable()
                        .scaledToFit()
                        .frame(height: 56)
                        .accessibilityLabel("Ville de Villejuif")
                    Text("Médiathèques").font(.largeTitle.weight(.heavy)).foregroundStyle(.white)
                    Text("Vos prêts, vos réservations et la médiathèque numérique, dans votre poche.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 28)
                .padding(.top, 72)
                Spacer()
                form
            }
        }
        .sheet(isPresented: $showsLostPassword) {
            LostPasswordView(cardNumber: viewModel.cardNumber)
        }
        .sensoryFeedback(trigger: viewModel.feedback) { _, event in event.map(\.sensoryFeedback) }
    }

    private var background: some View {
        ZStack {
            Color.brandViolet
            Circle().fill(Color.brandMagenta).frame(width: 330).offset(x: 150, y: -330)
            Circle().fill(Color.brandVioletDeep).frame(width: 190).offset(x: -170, y: -120)
            Circle().stroke(Color.brandCyan, lineWidth: 10).frame(width: 66).offset(x: 140, y: -60)
            Circle().fill(Color.brandYellow).frame(width: 22).offset(x: 130, y: -200)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connexion").font(.title2.weight(.heavy))

            VStack(alignment: .leading, spacing: 6) {
                Text("Numéro de carte").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                TextField("Au dos de votre carte", text: $viewModel.cardNumber)
                    .textContentType(.username)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .card)
                    .fieldStyle(isFocused: focus == .card)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Mot de passe").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                SecureField("Votre mot de passe", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.submit(into: session) } }
                    .fieldStyle(isFocused: focus == .password)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.statusDanger)
            }

            HStack {
                Spacer()
                Button("Mot de passe oublié ?") { showsLostPassword = true }
                    .font(.subheadline.weight(.semibold))
            }

            Button {
                Task { await viewModel.submit(into: session) }
            } label: {
                Group {
                    if viewModel.isSubmitting { ProgressView().tint(.white) } else { Text("Se connecter") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.brandViolet)
            .controlSize(.extraLarge)
            .disabled(!viewModel.canSubmit)

            Text("Pas encore inscrit ? L'inscription est gratuite, à l'accueil de chaque médiathèque.")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

extension View {
    func fieldStyle(isFocused: Bool) -> some View {
        self.font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isFocused ? Color.brandViolet : Color.inkSecondary.opacity(0.2), lineWidth: isFocused ? 1.5 : 1)
            }
    }
}

struct LostPasswordView: View {
    @State private var viewModel: LostPasswordViewModel
    @Environment(\.dismiss) private var dismiss

    init(cardNumber: String) {
        _viewModel = State(initialValue: LostPasswordViewModel(cardNumber: cardNumber))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "key.horizontal")
                    .font(.title)
                    .foregroundStyle(Color.brandVioletDeep)
                    .frame(width: 64, height: 64)
                    .background(Color.soft(.brandViolet), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("Indiquez votre numéro de carte. Vous recevrez un e-mail pour choisir un nouveau mot de passe, à l'adresse enregistrée sur votre compte.")
                    .foregroundStyle(Color.inkSecondary)

                TextField("Numéro de carte", text: $viewModel.cardNumber)
                    .textContentType(.username)
                    .keyboardType(.numberPad)
                    .fieldStyle(isFocused: false)

                switch viewModel.state {
                case .sent:
                    Label("E-mail envoyé. Pensez à vérifier vos indésirables.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.statusSuccess)
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.statusDanger)
                case .idle, .sending:
                    EmptyView()
                }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Group {
                        if viewModel.state == .sending { ProgressView().tint(.white) } else { Text("Recevoir l'e-mail") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.brandViolet)
                .controlSize(.extraLarge)

                Text("Pas d'e-mail sur votre compte ? L'équipe peut réinitialiser votre mot de passe à l'accueil, sur présentation de votre carte.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                Spacer()
            }
            .padding(20)
            .background(Color.surfaceGrouped)
            .navigationTitle("Mot de passe oublié")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.state == .sent)
    }
}

extension FeedbackEvent {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .success: .success
        case .error: .error
        case .selection: .selection
        case .lightImpact: .impact(weight: .light)
        }
    }
}
