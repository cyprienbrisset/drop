import SwiftUI

/// Page de confidentialité (§7.4) : langage clair et opposable, pas un mur juridique. Contenu
/// aligné sur la posture RGPD du CDC (§9 : aucune collecte, aucun transfert, aucun sous-traitant)
/// — cette formulation reste une proposition de rédaction produit, pas un avis juridique ; à faire
/// relire par le RSSI/juridique avant publication, comme pour toute page opposable aux clients.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Confidentialité")
                    .font(.largeTitle.bold())

                section(
                    title: "Ce que Drop ne fait jamais",
                    body: """
                    Drop ne crée aucun compte, ne demande aucune adresse courriel, n'envoie aucune \
                    donnée sur un serveur, n'installe aucun mouchard de suivi ou de mesure d'audience \
                    — y compris dans ses rapports de plantage, désactivés par principe.
                    """
                )

                section(
                    title: "Où vivent vos documents",
                    body: """
                    Tout reste sur cet ordinateur : les fichiers, l'index de recherche et les \
                    vecteurs sémantiques sont stockés dans un seul dossier, que vous pouvez déplacer, \
                    sauvegarder ou supprimer vous-même à tout moment.
                    """
                )

                section(
                    title: "Ce que l'intelligence embarquée voit",
                    body: """
                    L'analyse des documents (OCR, extraction, résumé) s'exécute entièrement sur cette \
                    machine, avec les modèles d'Apple installés sur ce Mac. Aucun contenu ni extrait \
                    de document ne quitte l'appareil à aucun moment de ce traitement.
                    """
                )

                section(
                    title: "La seule connexion réseau possible",
                    body: """
                    Drop ne se connecte à Internet que pour une chose, et seulement quand vous le \
                    décidez explicitement : vérifier si une nouvelle version est disponible. Aucune \
                    autre requête sortante n'existe dans l'application.
                    """
                )

                section(
                    title: "Vos droits",
                    body: """
                    Comme Drop ne collecte ni ne transmet aucune donnée, il n'y a rien à demander de \
                    supprimer ou de rectifier ailleurs que sur votre propre disque : effacer le dossier \
                    du coffre efface tout, définitivement et immédiatement.
                    """
                )
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PrivacyView()
}
