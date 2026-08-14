import DropIntelligence
import FoundationModels
import Testing

@Test func availableModelUsesTheFullPipeline() {
    #expect(DegradationPolicy.behavior(for: .available) == .fullPipeline)
}

@Test func deviceNotEligibleFallsBackToHeuristicsWithTheExpectedMessage() {
    let behavior = DegradationPolicy.behavior(for: .unavailable(.deviceNotEligible))
    #expect(behavior == .heuristicsAndDictionaryOnly(
        message: "Ce Mac ne prend pas en charge Apple Intelligence. Drop fonctionne, sans résumé automatique."
    ))
}

@Test func appleIntelligenceNotEnabledFallsBackToHeuristicsWithTheExpectedMessage() {
    let behavior = DegradationPolicy.behavior(for: .unavailable(.appleIntelligenceNotEnabled))
    #expect(behavior == .heuristicsAndDictionaryOnly(
        message: "Activez Apple Intelligence pour les résumés et la classification fine."
    ))
}

@Test func modelNotReadyRetriesLaterWithTheExpectedMessage() {
    let behavior = DegradationPolicy.behavior(for: .unavailable(.modelNotReady))
    #expect(behavior == .retryLater(
        message: "Modèle en cours de préparation par le système. Analyse reprise automatiquement."
    ))
}

@Test func inferenceFailureRetriesBeforeExhaustingAttempts() {
    let behavior = DegradationPolicy.behaviorAfterInferenceFailure(attempts: 1)
    guard case .retryLater = behavior else {
        Issue.record("expected retryLater, got \(behavior)"); return
    }
}

@Test func inferenceFailureIsSkippedSilentlyAfterMaxAttempts() {
    let behavior = DegradationPolicy.behaviorAfterInferenceFailure(attempts: DegradationPolicy.maxInferenceAttempts)
    #expect(behavior == .skippedAfterRetries)
}
