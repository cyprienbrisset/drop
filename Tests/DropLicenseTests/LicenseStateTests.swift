import DropLicense
import Testing

@Test func freeStateBelowCapIsDistinctFromPro() {
    let free = LicenseState.free(documentCount: 42, cap: 100)
    #expect(free != .pro)
    #expect(free != .invalid)
}

@Test func invalidLicenseNeverEqualsProOrFree() {
    #expect(LicenseState.invalid != .pro)
    #expect(LicenseState.invalid != .free(documentCount: 0, cap: 100))
}
