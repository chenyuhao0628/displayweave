import Foundation

/// One-shot pipeline ownership. Startup/runtime failures release resources before reporting
/// failure; stop also waits for a suspended start to finish its cancellation path.
@MainActor
final class SessionLifetime {
    private let startPipeline: () async throws -> Void
    private let stopPipeline: () -> Task<Void, Never>
    private let onFailure: (Error) -> Void
    private var startup: Task<Void, Never>?
    private var pipelineCleanup: Task<Void, Never>?
    private var completion: Task<Void, Never>?
    private var failure: Task<Void, Never>?
    private var stopped = false

    init(start: @escaping () async throws -> Void,
         stop: @escaping () -> Task<Void, Never>,
         onFailure: @escaping (Error) -> Void) {
        self.startPipeline = start
        self.stopPipeline = stop
        self.onFailure = onFailure
    }

    func start() {
        guard startup == nil, failure == nil, !stopped else { return }
        startup = Task {
            do {
                try Task.checkCancellation()
                try await startPipeline()
            } catch {
                await fail(error).value
            }
        }
    }

    /// A rebuild can fail after startup has returned. Share the same cleanup
    /// and error row without reporting a transport loss or starting recovery.
    @discardableResult
    func fail(_ error: Error) -> Task<Void, Never> {
        if stopped { return Task {} }
        if let failure { return failure }
        startup?.cancel()
        let pipeline = cleanup()
        let task = Task {
            await pipeline.value
            guard !stopped else { return }
            onFailure(error)
        }
        failure = task
        return task
    }

    private func cleanup() -> Task<Void, Never> {
        if let pipelineCleanup { return pipelineCleanup }
        let task = stopPipeline()
        pipelineCleanup = task
        return task
    }

    func stop() -> Task<Void, Never> {
        if let completion { return completion }
        stopped = true
        startup?.cancel()
        let pipeline = cleanup(), starting = startup, failing = failure
        let task = Task {
            await pipeline.value
            await starting?.value
            await failing?.value
        }
        completion = task
        return task
    }
}
