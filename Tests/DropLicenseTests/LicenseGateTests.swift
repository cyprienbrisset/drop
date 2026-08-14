import DropLicense
import Testing

@Test func stateResolvesToProWhenAPayloadIsPresent() {
    let payload = LicensePayload(v: 1, sku: "drop-pro-v1", orderID: "o1", issuedAt: "2026-01-01T00:00:00Z", buyerHash: "h", seats: 1)
    #expect(LicenseGate.state(forVerifiedPayload: payload, documentCount: 5) == .pro)
}

@Test func stateResolvesToFreeWithCapWhenNoPayload() {
    #expect(LicenseGate.state(forVerifiedPayload: nil, documentCount: 42) == .free(documentCount: 42, cap: 100))
}

@Test func reminderShowsOnceThresholdIsCrossedAndNotAlreadyShown() {
    #expect(LicenseGate.shouldShowCapReminder(documentCount: 80, alreadyShown: false))
    #expect(LicenseGate.shouldShowCapReminder(documentCount: 95, alreadyShown: false))
}

@Test func reminderDoesNotShowBelowThreshold() {
    #expect(!LicenseGate.shouldShowCapReminder(documentCount: 79, alreadyShown: false))
}

@Test func reminderDoesNotShowAgainOnceAlreadyShown() {
    #expect(!LicenseGate.shouldShowCapReminder(documentCount: 85, alreadyShown: true))
}

@Test func reminderDoesNotShowAtOrAboveTheCap() {
    #expect(!LicenseGate.shouldShowCapReminder(documentCount: 100, alreadyShown: false))
}

@Test func ingestionIsBlockedOnlyForFreeAtOrAboveCap() {
    #expect(LicenseGate.canIngestNewDocument(state: .free(documentCount: 99, cap: 100)))
    #expect(!LicenseGate.canIngestNewDocument(state: .free(documentCount: 100, cap: 100)))
}

@Test func ingestionIsNeverBlockedForProOrInvalid() {
    #expect(LicenseGate.canIngestNewDocument(state: .pro))
    #expect(LicenseGate.canIngestNewDocument(state: .invalid))
}
