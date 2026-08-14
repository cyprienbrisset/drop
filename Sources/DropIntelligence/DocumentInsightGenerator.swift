import FoundationModels

/// Génère un `DocumentInsight` via le modèle système, en génération guidée exclusivement
/// (EF-44) : aucun texte libre du modèle n'est consommé sans passer par le schéma `@Generable`.
///
/// Note de portée : la stratégie de sélection du contexte (§5.4.3, plafond ~2500 tokens) et la
/// matrice de dégradation complète (§5.4.4) sont traitées séparément (DRO-39, DRO-40). Ce type se
/// limite à l'appel structuré lui-même.
public struct DocumentInsightGenerator: Sendable {
    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    public var availability: SystemLanguageModel.Availability {
        model.availability
    }

    public func generate(fromText text: String) async throws -> DocumentInsight {
        let session = LanguageModelSession(model: model) {
            """
            Tu analyses un document administratif ou personnel pour un coffre documentaire local.
            Tu produis uniquement : le type du document, son émetteur si présent, un résumé factuel
            d'une phrase, et des mots-clés. Tu ne dois jamais produire de montant, de date, d'IBAN
            ou de référence — ces valeurs sont extraites séparément par des règles déterministes.
            """
        }
        let response = try await session.respond(to: text, generating: DocumentInsight.self)
        return response.content
    }
}
