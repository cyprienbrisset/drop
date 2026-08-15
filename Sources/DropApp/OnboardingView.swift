import SwiftUI

/// Onboarding en 4 écrans maximum (EX-06) : promesse/confidentialité, emplacement du coffre,
/// raccourci et conflits, premier dépôt de démonstration. Aucun compte ni courriel demandé à
/// aucune étape — c'est un engagement produit, pas une contrainte technique de cette vue.
struct OnboardingView: View {
    let vaultLocation: URL
    let globalShortcut: String
    var onChooseVaultLocation: () -> Void = {}
    var onTryDemoDrop: () -> Void = {}
    var onFinish: () -> Void = {}

    @State private var step = 0
    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                promiseStep.tag(0)
                vaultLocationStep.tag(1)
                shortcutStep.tag(2)
                demoDropStep.tag(3)
            }
            .tabViewStyle(.automatic)

            HStack {
                stepIndicator
                Spacer()
                if step > 0 {
                    Button("Précédent") { step -= 1 }
                }
                Button(step == stepCount - 1 ? "Commencer" : "Continuer") {
                    if step == stepCount - 1 {
                        onFinish()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 420)
        .tint(.dropBrand)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.dropBrand : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel("Étape \(step + 1) sur \(stepCount)")
    }

    private var promiseStep: some View {
        VStack(spacing: 16) {
            Spacer()
            CrowMark(size: 120)
            Text("Drop")
                .font(.system(.largeTitle, design: .serif).italic().weight(.semibold))
            Text("Un corbeau garde vos documents. Aucun compte. Aucun cloud. Aucun suivi — Drop les retrouve en langage naturel, entièrement sur cet ordinateur.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(32)
    }

    private var vaultLocationStep: some View {
        stepContainer(
            symbol: "folder",
            title: "Le coffre vit ici",
            message: "Vos fichiers, l'index et les vecteurs de recherche seront stockés dans ce dossier. Vous pourrez le déplacer à tout moment."
        ) {
            VStack(spacing: 8) {
                Text(vaultLocation.path)
                    .font(.callout.monospaced())
                    .padding(8)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                Button("Choisir un autre emplacement…", action: onChooseVaultLocation)
            }
        }
    }

    private var shortcutStep: some View {
        stepContainer(
            symbol: "keyboard",
            title: "Toujours à portée de main",
            message: "\(globalShortcut) ouvre la recherche globale depuis n'importe quelle application. Si ce raccourci est déjà pris, vous pourrez en choisir un autre dans les préférences."
        )
    }

    private var demoDropStep: some View {
        stepContainer(
            symbol: "arrow.down.doc",
            title: "Essayez maintenant",
            message: "Déposez un premier fichier de démonstration pour voir Drop l'analyser et le rendre immédiatement cherchable."
        ) {
            Button("Déposer un fichier de démonstration", action: onTryDemoDrop)
        }
    }

    private func stepContainer<Extra: View>(
        symbol: String, title: String, message: String, @ViewBuilder extra: () -> Extra
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(.title2, design: .serif).weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            extra()
            Spacer()
        }
        .padding(32)
    }

    private func stepContainer(symbol: String, title: String, message: String) -> some View {
        stepContainer(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

#Preview {
    OnboardingView(
        vaultLocation: URL(fileURLWithPath: "/Users/exemple/Library/Application Support/Drop"),
        globalShortcut: "⌥ Espace"
    )
}
