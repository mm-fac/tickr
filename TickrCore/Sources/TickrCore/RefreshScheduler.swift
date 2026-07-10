import Foundation

public protocol RefreshSchedulerClock: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

public struct ContinuousRefreshSchedulerClock: RefreshSchedulerClock {
    public init() {}

    public func sleep(for seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

public struct RefreshSchedulerConfiguration: Equatable, Sendable {
    public var interval: TimeInterval
    public var requestsPerMinute: Int

    public init(interval: TimeInterval = 15, requestsPerMinute: Int = 60) {
        self.interval = interval
        self.requestsPerMinute = requestsPerMinute
    }
}

public struct RefreshSchedulerUpdate: Equatable, Sendable {
    public let symbol: String
    public let quote: Quote

    public init(symbol: String, quote: Quote) {
        self.symbol = symbol
        self.quote = quote
    }
}

public final class RefreshScheduler: @unchecked Sendable {
    private let symbols: [String]
    private let provider: any QuoteProvider
    private let configuration: RefreshSchedulerConfiguration
    private let clock: any RefreshSchedulerClock
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<RefreshSchedulerUpdate>.Continuation?

    public var requestSpacing: TimeInterval {
        Self.requestSpacing(symbolCount: symbols.count, configuration: configuration)
    }

    public init(
        symbols: some Sequence<String>,
        provider: any QuoteProvider,
        configuration: RefreshSchedulerConfiguration = RefreshSchedulerConfiguration(),
        clock: any RefreshSchedulerClock = ContinuousRefreshSchedulerClock()
    ) {
        self.symbols = symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        self.provider = provider
        self.configuration = configuration
        self.clock = clock
    }

    deinit {
        stop()
    }

    public func start() -> AsyncStream<RefreshSchedulerUpdate> {
        var streamContinuation: AsyncStream<RefreshSchedulerUpdate>.Continuation?
        let stream = AsyncStream<RefreshSchedulerUpdate> { continuation in
            streamContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { self?.stop() }
            }
        }

        lock.lock()
        stopLocked()
        continuation = streamContinuation

        let task = Task { [symbols, provider, configuration, clock] in
            await Self.run(
                symbols: symbols,
                provider: provider,
                configuration: configuration,
                clock: clock,
                yield: { [weak self] update in
                    self?.lock.lock()
                    let continuation = self?.continuation
                    self?.lock.unlock()
                    continuation?.yield(update)
                }
            )
        }
        self.task = task
        lock.unlock()
        return stream
    }

    public func stop() {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    private func stopLocked() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }

    private static func run(
        symbols: [String],
        provider: any QuoteProvider,
        configuration: RefreshSchedulerConfiguration,
        clock: any RefreshSchedulerClock,
        yield: @escaping @Sendable (RefreshSchedulerUpdate) -> Void
    ) async {
        guard !symbols.isEmpty else { return }
        let spacing = requestSpacing(symbolCount: symbols.count, configuration: configuration)

        while !Task.isCancelled {
            for symbol in symbols {
                if Task.isCancelled { return }

                do {
                    let quote = try await provider.quote(for: symbol)
                    yield(RefreshSchedulerUpdate(symbol: symbol, quote: quote))
                } catch is CancellationError {
                    return
                } catch {
                    // Keep the scheduler alive when an individual provider request fails.
                }

                if Task.isCancelled { return }

                do {
                    try await clock.sleep(for: spacing)
                } catch {
                    return
                }
            }
        }
    }

    private static func requestSpacing(
        symbolCount: Int,
        configuration: RefreshSchedulerConfiguration
    ) -> TimeInterval {
        guard symbolCount > 0 else { return 0 }
        let intervalSpacing = max(0, configuration.interval) / Double(symbolCount)
        let budgetSpacing: TimeInterval
        if configuration.requestsPerMinute > 0 {
            budgetSpacing = 60 / Double(configuration.requestsPerMinute)
        } else {
            budgetSpacing = .infinity
        }
        return max(intervalSpacing, budgetSpacing)
    }
}
