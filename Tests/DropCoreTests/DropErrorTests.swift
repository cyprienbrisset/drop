import DropCore
import Testing

@Test func dropErrorDescriptionIncludesCode() {
    let error = DropError(code: "DROP-ING-004", message: "Divergence de hash")
    #expect(error.description == "[DROP-ING-004] Divergence de hash")
}

@Test func systemClockAdvances() async throws {
    let clock = SystemClock()
    let first = clock.now()
    try await Task.sleep(for: .milliseconds(10))
    let second = clock.now()
    #expect(second > first)
}
