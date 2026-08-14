import Foundation

/// Politique d'application de la licence (§5.11, EF-81/82/84). Fonctions pures : la persistance
/// (compteur de documents, indicateur « rappel déjà affiché ») reste à la charge de l'appelant.
public enum LicenseGate {
    public static let freeCap = 100
    public static let reminderThreshold = 80

    public static func state(forVerifiedPayload payload: LicensePayload?, documentCount: Int) -> LicenseState {
        guard payload != nil else { return .free(documentCount: documentCount, cap: freeCap) }
        return .pro
    }

    /// EF-84 : rappel unique et non modal, déclenché la première fois que le coffre atteint 80
    /// documents en licence gratuite — jamais répété, jamais modal, jamais au-delà du plafond
    /// (où EF-82 prend le relais).
    public static func shouldShowCapReminder(
        documentCount: Int, cap: Int = freeCap, threshold: Int = reminderThreshold, alreadyShown: Bool
    ) -> Bool {
        !alreadyShown && documentCount >= threshold && documentCount < cap
    }

    /// EF-82 : aucune dégradation rétroactive. Un coffre déjà au-delà du plafond gratuit reste
    /// pleinement consultable, cherchable et exportable — seule l'ingestion de documents
    /// supplémentaires est bloquée pour l'état `free` au plafond. `pro` et `invalid` n'imposent
    /// jamais de blocage (EF-83 : une licence illisible ne doit jamais priver l'utilisateur de
    /// son propre coffre).
    public static func canIngestNewDocument(state: LicenseState) -> Bool {
        switch state {
        case .pro, .invalid:
            return true
        case .free(let documentCount, let cap):
            return documentCount < cap
        }
    }
}
