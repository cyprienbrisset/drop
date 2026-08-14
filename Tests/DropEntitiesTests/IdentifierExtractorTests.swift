import DropEntities
import Testing

private let extractor = IdentifierExtractor()

@Test func extractsAValidFrenchIBAN() {
    let results = extractor.extract(from: "IBAN : FR14 2004 1010 0505 0001 3M02 606")
    #expect(results.contains { $0.kind == .iban && $0.valueText == "FR1420041010050500013M02606" })
}

@Test func extractsAValidSEPAZoneIBAN() {
    let results = extractor.extract(from: "Compte GB29NWBK60161331926819")
    #expect(results.contains { $0.kind == .iban && $0.valueText == "GB29NWBK60161331926819" })
}

@Test func rejectsAnInvalidIBANChecksum() {
    let results = extractor.extract(from: "FR14 2004 1010 0505 0001 3M02 607") // dernier chiffre altéré.
    #expect(!results.contains { $0.kind == .iban })
}

@Test func extractsAValidSIREN() {
    let results = extractor.extract(from: "SIREN : 439 789 918")
    #expect(results.contains { $0.kind == .siren && $0.valueText == "439789918" })
}

@Test func extractsAValidSIRETAndDoesNotAlsoReportItsPrefixAsSiren() {
    let results = extractor.extract(from: "SIRET : 95733545137624")
    #expect(results.contains { $0.kind == .siret && $0.valueText == "95733545137624" })
    #expect(!results.contains { $0.kind == .siren && $0.valueText == "95733545" })
}

@Test func rejectsAnInvalidLuhnChecksum() {
    let results = extractor.extract(from: "Numéro : 123456789") // Luhn invalide.
    #expect(!results.contains { $0.kind == .siren })
}

@Test func extractsAFrenchVATNumber() {
    let results = extractor.extract(from: "N° TVA intracommunautaire : FR32439789918")
    #expect(results.contains { $0.kind == .vat && $0.valueText == "FR32439789918" })
}

@Test func extractsAnInvoiceReferenceFromSeveralPhrasings() {
    #expect(extractor.extract(from: "Facture n° 2024-00123").contains { $0.kind == .invoiceRef })
    #expect(extractor.extract(from: "FA-2024-00123").contains { $0.kind == .invoiceRef })
}

@Test func extractsAnOrderReference() {
    let results = extractor.extract(from: "Commande n° CMD-98765")
    #expect(results.contains { $0.kind == .orderRef && $0.valueText == "CMD-98765" })
}

@Test func extractsAnEmailAddress() {
    let results = extractor.extract(from: "Contact : Jean.Dupont@Exemple.fr pour toute question.")
    #expect(results.contains { $0.kind == .email && $0.valueText == "jean.dupont@exemple.fr" })
}

@Test func extractsAFrenchPhoneNumber() {
    let results = extractor.extract(from: "Tél : 01 23 45 67 89")
    #expect(results.contains { $0.kind == .phone && $0.valueText == "0123456789" })
}

@Test func extractsAnInternationalPhoneNumber() {
    let results = extractor.extract(from: "Tél : +33 1 23 45 67 89")
    #expect(results.contains { $0.kind == .phone && $0.valueText == "+33123456789" })
}
