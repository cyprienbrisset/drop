import Foundation

/// Dictionnaire d'émetteurs récurrents en France (§5.3.5). Tourne en premier ; le modèle de
/// langage n'intervient que sur les émetteurs non reconnus (Phase 5). Un émetteur trouvé ici
/// porte une confiance de 1,0 et n'est jamais contredit par le modèle (ADR-09).
///
/// Note de portée : ~120 organisations couvertes ici (énergie, télécoms, banques, assurances,
/// administrations, transporteurs, grande distribution, plateformes) — un socle réel et vérifié,
/// pas les ~400 visées à terme par le CDC (§5.3.5). Étendre cette liste est un travail de curation
/// de données à part entière, distinct de la logique de correspondance elle-même.
public struct IssuerDictionary: Sendable {
    public init() {}

    public func match(in text: String) -> [ExtractedEntity] {
        var results: [ExtractedEntity] = []
        var seenCanonical: Set<String> = []

        for entry in Self.entries {
            for alias in entry.aliases {
                guard let regex = Self.regex(forAlias: alias) else { continue }
                let nsText = text as NSString
                guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
                      let range = Range(match.range, in: text)
                else { continue }

                guard !seenCanonical.contains(entry.canonical) else { break }
                seenCanonical.insert(entry.canonical)
                results.append(ExtractedEntity(
                    kind: .org, valueText: entry.canonical, rawText: String(text[range]), extractor: .regex, confidence: 1.0
                ))
                break
            }
        }
        return results
    }

    private static func regex(forAlias alias: String) -> NSRegularExpression? {
        if let cached = regexCache.withLock({ $0[alias] }) { return cached }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: alias))\\b"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        regexCache.withLock { $0[alias] = regex }
        return regex
    }

    private static let regexCache = Mutex<[String: NSRegularExpression?]>([:])

    private struct Entry {
        let canonical: String
        let aliases: [String]
    }

    private static func entry(_ canonical: String, _ aliases: String...) -> Entry {
        Entry(canonical: canonical, aliases: [canonical] + aliases)
    }

    private static let entries: [Entry] = [
        // Énergie
        entry("EDF"), entry("Engie", "GDF Suez"), entry("TotalEnergies", "Total Energies"),
        entry("Enedis"), entry("GRDF"), entry("Eni"), entry("ekWateur"), entry("Ovo Energy"),
        entry("Alpiq"), entry("Vattenfall"), entry("Plüm énergie"), entry("Mint Énergie"),

        // Télécoms
        entry("Orange"), entry("SFR"), entry("Bouygues Telecom"), entry("Free", "Free Mobile"),
        entry("La Poste Mobile"), entry("Sosh"), entry("RED by SFR"), entry("Coriolis Télécom"),
        entry("NRJ Mobile"), entry("Prixtel"), entry("Lebara"),

        // Banques
        entry("BNP Paribas"), entry("Société Générale"), entry("Crédit Agricole"), entry("LCL"),
        entry("La Banque Postale"), entry("Caisse d'Épargne"), entry("CIC"), entry("HSBC"),
        entry("Crédit Mutuel"), entry("Boursorama Banque", "Boursorama"), entry("BforBank"),
        entry("Hello bank!", "Hello Bank"), entry("Fortuneo"), entry("Monabanq"), entry("N26"),
        entry("Revolut"), entry("Qonto"), entry("Nickel"),

        // Assurances
        entry("AXA"), entry("Allianz"), entry("MAIF"), entry("MACIF"), entry("Groupama"),
        entry("MMA"), entry("Matmut"), entry("GMF"), entry("Generali"), entry("Aviva"),
        entry("April"), entry("Malakoff Humanis"), entry("Harmonie Mutuelle"), entry("MGEN"),
        entry("Swiss Life"), entry("Crédit Agricole Assurances"),

        // Administrations
        entry("URSSAF"), entry("CAF"), entry("France Travail", "Pôle Emploi", "Pole Emploi"),
        entry("CPAM"), entry("Assurance Maladie"), entry("DGFIP", "Direction Générale des Finances Publiques"),
        entry("Impots.gouv.fr", "impots.gouv"), entry("Préfecture"), entry("Mairie de Paris"),
        entry("CNAV"), entry("MSA"), entry("Trésor Public"), entry("Ameli"), entry("ANTS"),
        entry("Service-Public.fr"),

        // Transporteurs
        entry("SNCF", "SNCF Connect"), entry("RATP"), entry("Colissimo"), entry("Chronopost"),
        entry("DHL"), entry("UPS"), entry("FedEx"), entry("Mondial Relay"), entry("GLS"),
        entry("La Poste"), entry("Air France"), entry("Transavia"), entry("BlaBlaCar"),
        entry("Uber"), entry("Ouigo"), entry("Flixbus"),

        // Grande distribution
        entry("Carrefour"), entry("E.Leclerc", "Leclerc"), entry("Auchan"), entry("Intermarché"),
        entry("Casino"), entry("Monoprix"), entry("Lidl"), entry("Aldi"), entry("Système U", "Super U"),
        entry("Cora"), entry("Franprix"), entry("Picard"), entry("Fnac"), entry("Darty"),
        entry("Boulanger"), entry("Ikea"), entry("Decathlon"), entry("Leroy Merlin"), entry("Castorama"),

        // Plateformes
        entry("Amazon"), entry("PayPal"), entry("Apple"), entry("Google"), entry("Netflix"),
        entry("Spotify"), entry("Deliveroo"), entry("Just Eat", "JustEat"), entry("Airbnb"),
        entry("Booking.com", "Booking"), entry("Vinted"), entry("Leboncoin"), entry("Cdiscount"),
        entry("Microsoft"), entry("Adobe"), entry("Disney+", "Disney Plus"), entry("Canal+", "Canal Plus"),
        entry("OVHcloud", "OVH"),

        // Divers services fréquents
        entry("Veolia"), entry("Suez"), entry("SACEM"), entry("Pôle Santé"), entry("Doctolib"),
        entry("Vinci Autoroutes"), entry("APRR"), entry("Sanef"),
    ]
}

/// Verrou minimal pour un cache thread-safe — évite une dépendance supplémentaire pour un simple
/// dictionnaire mémoïsé.
private final class Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
