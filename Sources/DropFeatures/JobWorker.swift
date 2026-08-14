import DropCore
import DropJobs
import Foundation

/// Draine la file `jobs` en tâche de fond (§5.8) — le chaînon qui manquait depuis DRO-31 : la
/// file persistante existait, mais rien ne la vidait jamais, forçant l'appelant (`AppEnvironment`)
/// à lancer l'analyse en ligne et à bloquer sur l'appel au modèle de langage (parfois 20-30 s).
/// Boucle continue tant que non annulée ; file vide → attente avant nouvel essai plutôt que de
/// tourner à vide en CPU (ENF-10, consommation quasi nulle au repos).
public actor JobWorker {
    private let jobQueue: JobQueue
    private let analyzeDocument: AnalyzeDocument
    private let sleeper: Sleeper
    private let idlePollSeconds: Double
    private var runningTask: Task<Void, Never>?

    public init(
        jobQueue: JobQueue, analyzeDocument: AnalyzeDocument, sleeper: Sleeper = SystemSleeper(),
        idlePollSeconds: Double = 2
    ) {
        self.jobQueue = jobQueue
        self.analyzeDocument = analyzeDocument
        self.sleeper = sleeper
        self.idlePollSeconds = idlePollSeconds
    }

    public func start() {
        guard runningTask == nil else { return }
        runningTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        runningTask?.cancel()
        runningTask = nil
    }

    /// Traite au plus un travail en attente ; ne fait rien et renvoie `false` si la file est
    /// vide. Exposé publiquement pour permettre aux tests d'avancer la boucle de façon
    /// déterministe, sans dépendre du minutage réel de `runLoop`.
    @discardableResult
    public func processNext() async -> Bool {
        guard let job = try? await jobQueue.dequeueNext(kinds: [.extract]), let jobID = job.id else { return false }
        do {
            try await analyzeDocument.analyze(documentID: job.documentID)
            try await jobQueue.complete(jobID: jobID)
        } catch {
            try? await jobQueue.fail(jobID: jobID, error: String(describing: error))
        }
        return true
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let processed = await processNext()
            if !processed {
                try? await sleeper.sleep(seconds: idlePollSeconds)
            }
        }
    }
}
