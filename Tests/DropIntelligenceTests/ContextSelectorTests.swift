import DropIntelligence
import Testing

@Test func selectsTheFullFirstPageWhenItFitsInBudget() {
    let selector = ContextSelector(tokenBudget: 2500)
    let pages = [PageContent(pageNumber: 0, text: "Facture EDF. Montant à régler 84,20 euros.")]

    let context = selector.select(pages: pages, filename: "facture.pdf")

    #expect(context.contains("Facture EDF"))
    #expect(context.contains("facture.pdf"))
}

@Test func truncatesTheFirstPageAtTwelveHundredTokens() {
    let selector = ContextSelector(tokenBudget: 2500)
    let longText = String(repeating: "a", count: 10_000)
    let pages = [PageContent(pageNumber: 0, text: longText)]

    let context = selector.select(pages: pages, filename: "long.pdf")

    // 1200 tokens (première page) + 400 tokens (fin de la dernière page — ici la même unique
    // page) ≈ 6400 caractères avec l'heuristique ~4 car./token : bien moins que les 10 000 saisis.
    #expect(context.count < 7000)
}

@Test func includesWindowsAroundDenseEntityOffsets() {
    let selector = ContextSelector(tokenBudget: 2500)
    let text = String(repeating: "x", count: 2000) + "MONTANT_CLE" + String(repeating: "y", count: 2000)
    let pages = [
        PageContent(pageNumber: 0, text: "Première page, courte."),
        PageContent(pageNumber: 1, text: text),
    ]

    let context = selector.select(pages: pages, denseEntityOffsets: [1: [2000]], filename: "doc.pdf")

    #expect(context.contains("MONTANT_CLE"))
}

@Test func includesTheLastPageTail() {
    let selector = ContextSelector(tokenBudget: 2500)
    let pages = [
        PageContent(pageNumber: 0, text: "Première page."),
        PageContent(pageNumber: 1, text: String(repeating: "z", count: 500) + "SIGNATURE_FINALE"),
    ]

    let context = selector.select(pages: pages, filename: "doc.pdf")

    #expect(context.contains("SIGNATURE_FINALE"))
}

@Test func includesFilenameAndVisualLabelsAsFooter() {
    let selector = ContextSelector(tokenBudget: 2500)
    let pages = [PageContent(pageNumber: 0, text: "Contenu bref.")]

    let context = selector.select(pages: pages, filename: "photo.jpg", visualLabels: ["reçu", "restaurant"])

    #expect(context.contains("photo.jpg"))
    #expect(context.contains("reçu"))
    #expect(context.contains("restaurant"))
}

@Test func neverExceedsTheTokenBudgetSubstantially() {
    let selector = ContextSelector(tokenBudget: 100)
    let hugePage = PageContent(pageNumber: 0, text: String(repeating: "a", count: 100_000))
    let pages = [hugePage, PageContent(pageNumber: 1, text: String(repeating: "b", count: 100_000))]

    let context = selector.select(
        pages: pages, denseEntityOffsets: [0: [50_000], 1: [50_000]], filename: "big.pdf"
    )

    // Budget de 100 tokens ≈ 400 caractères ; on tolère le nom de fichier et un peu de structure
    // en plus, mais pas des dizaines de milliers de caractères.
    #expect(context.count < 1000)
}

@Test func returnsOnlyTheFilenameWhenThereIsNoPage() {
    let selector = ContextSelector()
    let context = selector.select(pages: [], filename: "vide.pdf")
    #expect(context == "vide.pdf")
}
