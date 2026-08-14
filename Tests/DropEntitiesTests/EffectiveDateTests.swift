import DropEntities
import Testing

@Test func userVerifiedDateAlwaysWins() {
    let result = EffectiveDate.resolve(
        userVerified: "2025-01-01", emissionContextDate: "2025-02-02", allDates: ["2025-03-03"],
        contentCreatedAt: "2025-04-04", filenameDate: "2025-05-05", addedAt: "2025-06-06"
    )
    #expect(result.date == "2025-01-01")
    #expect(result.source == .user)
    #expect(!result.isUnreliable)
}

@Test func emissionContextWinsOverFrequencyAndMetadata() {
    let result = EffectiveDate.resolve(
        userVerified: nil, emissionContextDate: "2025-02-02", allDates: ["2025-03-03", "2025-03-03"],
        contentCreatedAt: "2025-04-04", filenameDate: nil, addedAt: "2025-06-06"
    )
    #expect(result.date == "2025-02-02")
    #expect(result.source == .emissionContext)
}

@Test func mostFrequentDateWinsWhenNoEmissionContext() {
    let result = EffectiveDate.resolve(
        userVerified: nil, emissionContextDate: nil,
        allDates: ["2025-01-01", "2025-03-03", "2025-03-03"],
        contentCreatedAt: "2025-04-04", filenameDate: nil, addedAt: "2025-06-06"
    )
    #expect(result.date == "2025-03-03")
    #expect(result.source == .mostFrequent)
}

@Test func fallsBackToContentMetadataThenFilenameThenAddedAt() {
    let metadataOnly = EffectiveDate.resolve(
        userVerified: nil, emissionContextDate: nil, allDates: [],
        contentCreatedAt: "2025-04-04", filenameDate: "2025-05-05", addedAt: "2025-06-06"
    )
    #expect(metadataOnly.date == "2025-04-04")
    #expect(metadataOnly.source == .contentMetadata)

    let filenameOnly = EffectiveDate.resolve(
        userVerified: nil, emissionContextDate: nil, allDates: [],
        contentCreatedAt: nil, filenameDate: "2025-05-05", addedAt: "2025-06-06"
    )
    #expect(filenameOnly.date == "2025-05-05")
    #expect(filenameOnly.source == .filename)

    let addedAtOnly = EffectiveDate.resolve(
        userVerified: nil, emissionContextDate: nil, allDates: [],
        contentCreatedAt: nil, filenameDate: nil, addedAt: "2025-06-06"
    )
    #expect(addedAtOnly.date == "2025-06-06")
    #expect(addedAtOnly.source == .addedAt)
    #expect(addedAtOnly.isUnreliable) // affichée en gris (§5.3.3).
}
